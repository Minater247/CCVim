local Runtime = {}

local Highlight = loadModule("lib.highlight")
local VimRegex = loadModule("lib.excmd.vim_regex")
local str_sub = string.sub

local RECOMPUTE_BATCH = 96
local DEFAULT_RESYNC_MAXLINES = 200
local OFFSET_KEYS = {
    ms = true, me = true,
    hs = true, he = true,
    rs = true, re = true,
    lc = true,
}
local PROFILE_CTX = nil

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function profile_now()
    if os.clock then
        return os.clock()
    end
    return os.epoch("utc") / 1000
end

local function profile_record(spec, matched, elapsed)
    local ctx = PROFILE_CTX
    if not ctx then return end
    local profile = ctx.profile
    if not profile or not profile.enabled then return end

    local key = tostring(spec.profile_key or spec.raw or spec.pattern or "")
    local counters = profile.counters
    local entry = counters[key]
    if not entry then
        entry = {
            key = key,
            name = spec.profile_name or "",
            pattern = spec.pattern or "",
            calls = 0,
            matches = 0,
            time = 0,
            slowest = 0,
        }
        counters[key] = entry
    end

    entry.calls = entry.calls + 1
    if matched then
        entry.matches = entry.matches + 1
    end
    entry.time = entry.time + elapsed
    if elapsed > entry.slowest then
        entry.slowest = elapsed
    end
end

local function clamp(value, lo, hi)
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

local function is_whitespace_char(ch)
    return ch == " " or ch == "\t"
end

local function is_blank_line(line)
    return (line or ""):match("^%s*$") ~= nil
end

local function buffer_line_count(buffer)
    return buffer:line_count(true)
end

local function buffer_get_line(buffer, line_nr)
    return buffer:get_line(line_nr, true) or ""
end

local function bit_has(bits, id)
    if not bits or not id or id < 1 then return false end
    local word = math.floor((id - 1) / 32) + 1
    local bit = (id - 1) % 32
    local value = bits[word] or 0
    if bit32 then
        return bit32.band(value, bit32.lshift(1, bit)) ~= 0
    end
    local mask = 2 ^ bit
    return (value % (mask * 2)) >= mask
end

local function merge_offsets(a, b)
    if not a and not b then
        return nil
    end
    local out = {}
    if a then
        for k, v in pairs(a) do out[k] = v end
    end
    if b then
        for k, v in pairs(b) do out[k] = v end
    end
    return out
end

local function offsets_from_attrs(attrs)
    if not attrs then return nil end
    local parts = {}
    for k, v in pairs(attrs) do
        local key = tostring(k):lower()
        if OFFSET_KEYS[key] then
            parts[#parts + 1] = key .. "=" .. tostring(v)
        end
    end
    if #parts == 0 then return nil end
    return VimRegex.parse_syntax_offsets(table.concat(parts, ","))
end

local function split_delim_pattern(raw)
    local token = tostring(raw or "")
    local n = #token
    local q = token:sub(1, 1)
    local is_quoted = n >= 2 and (q == "'" or q == "\"") and token:sub(n, n) == q
    local s = is_quoted and token:sub(2, n - 1) or token
    if s == "" then
        return "", nil
    end

    -- Quoted syntax arguments are literal regex patterns.
    -- Do not reinterpret a leading punctuation/backslash as delimiter syntax.
    if is_quoted then
        return s, nil
    end

    local d = s:sub(1, 1)
    if d:match("[%w_]") then
        return s, nil
    end

    local i = 2
    n = #s
    local esc = false
    local in_class = false
    local class_count = 0
    local class_leading_caret = false
    while i <= n do
        local ch = s:sub(i, i)
        if esc then
            esc = false
            if in_class then
                class_count = class_count + 1
            end
        elseif ch == "\\" then
            esc = true
        elseif in_class then
            class_count = class_count + 1
            if class_count == 1 and ch == "^" then
                class_leading_caret = true
            elseif ch == "]" then
                if class_count > 1 and not (class_leading_caret and class_count == 2) then
                    in_class = false
                end
            end
        elseif ch == "[" then
            in_class = true
            class_count = 0
            class_leading_caret = false
        elseif ch == d then
            local patt = s:sub(2, i - 1)
            local tail = s:sub(i + 1)
            local offs = (tail ~= "") and VimRegex.parse_syntax_offsets(tail)
            return patt, offs
        end
        i = i + 1
    end

    return s, nil
end

local function parse_iskeyword(spec)
    local set = {}
    for b = string.byte("0"), string.byte("9") do set[b] = true end
    for b = string.byte("A"), string.byte("Z") do set[b] = true end
    for b = string.byte("a"), string.byte("z") do set[b] = true end
    set[string.byte("_")] = true

    if not spec or spec == "" then
        return set
    end

    local function apply_range(lo, hi, remove)
        lo = clamp(lo, 0, 255)
        hi = clamp(hi, 0, 255)
        if lo > hi then lo, hi = hi, lo end
        for b = lo, hi do
            if remove then
                set[b] = nil
            else
                set[b] = true
            end
        end
    end

    for tok in tostring(spec):gmatch("[^,]+") do
        local t = trim(tok)
        if t ~= "" then
            local remove = false
            if t:sub(1, 1) == "^" then
                remove = true
                t = t:sub(2)
            end

            if t == "@" then
                apply_range(string.byte("0"), string.byte("9"), remove)
                apply_range(string.byte("A"), string.byte("Z"), remove)
                apply_range(string.byte("a"), string.byte("z"), remove)
            else
                local n = tonumber(t)
                if n then
                    apply_range(n, n, remove)
                else
                    local n1, n2 = t:match("^(%-?%d+)%-(%-?%d+)$")
                    if n1 and n2 then
                        apply_range(tonumber(n1) or 0, tonumber(n2) or 0, remove)
                    else
                        local c1, c2 = t:match("^(.)%-(.)$")
                        if c1 and c2 then
                            apply_range(string.byte(c1), string.byte(c2), remove)
                        elseif #t == 1 then
                            apply_range(string.byte(t), string.byte(t), remove)
                        end
                    end
                end
            end
        end
    end

    return set
end

local function state_hash(state)
    local parts = {}
    local stack = state.stack or {}
    for i = 1, #stack do
        parts[#parts + 1] = stack[i].hash_token
    end
    local p = state.pending_next
    if p then
        parts[#parts + 1] = p.hash_token
    end
    return table.concat(parts, "|")
end

local function make_pending_next(bits, skipwhite, skipnl, skipempty)
    local p = {
        bits = bits,
        skipwhite = skipwhite and true or false,
        skipnl = skipnl and true or false,
        skipempty = skipempty and true or false,
    }
    p.hash_token = ("n.%s.%d.%d.%d"):format(
        tostring(bits),
        p.skipwhite and 1 or 0,
        p.skipnl and 1 or 0,
        p.skipempty and 1 or 0
    )
    return p
end

local function clone_pending_next(p)
    if not p then return nil end
    return make_pending_next(p.bits, p.skipwhite, p.skipnl, p.skipempty)
end

local function clone_state(state)
    local out = {
        stack = {},
        pending_next = clone_pending_next(state.pending_next),
    }
    local stack = state.stack or {}
    for i = 1, #stack do
        out.stack[i] = stack[i]
    end
    return out
end

local function new_state()
    return {
        stack = {},
        pending_next = nil,
    }
end

local function ensure_line_count_consistency(ctx, line_count)
    if ctx._line_count == nil then
        ctx._line_count = line_count
        return
    end
    if ctx._line_count ~= line_count then
        ctx._line_count = line_count
        ctx._structure_changed = true
    end
end

local function region_entry_hash_token(entry)
    return ("r%d.%d.%d.%s"):format(
        entry.item_id or 0,
        entry.group_id or 0,
        entry.transparent and 1 or 0,
        entry.ext_key or ""
    )
end

local function trim_caches_to_buffer(ctx, line_count)
    for ln in pairs(ctx.span_cache) do
        if ln > line_count then
            ctx.span_cache[ln] = nil
        end
    end
    for ln in pairs(ctx.checkpoints) do
        if ln > line_count + 1 then
            ctx.checkpoints[ln] = nil
        end
    end
end

local function compiled_pattern(pattern)
    local ok, mod_or_err, err2 = pcall(VimRegex.compile, pattern or "")
    if not ok then
        return nil, tostring(mod_or_err)
    end
    if not mod_or_err then
        return nil, tostring(err2)
    end
    return mod_or_err
end

local function build_compiled_spec(raw_pattern, ignore_case, attrs, matchgroup, excludenl, profile)
    local patt, offs_from_patt = split_delim_pattern(raw_pattern)
    local offs_from_attrs = offsets_from_attrs(attrs)
    local offsets = merge_offsets(offs_from_patt, offs_from_attrs)
    local lc = offsets and tonumber(offsets.lc) or 0
    local comp, emsg = compiled_pattern(patt)
    return {
        raw = raw_pattern,
        pattern = patt,
        compiled = comp,
        compile_error = emsg,
        ignore_case = ignore_case,
        offsets = offsets,
        lc = lc,
        matchgroup = matchgroup,
        excludenl = excludenl and true or false,
        profile_key = profile and profile.key,
        profile_name = profile and profile.name,
    }
end

local function pattern_uses_external_backref(patt)
    local i = 1
    while true do
        local p = string.find(patt, "\\z", i, true)
        if not p then
            return false
        end
        local d = string.sub(patt, p + 2, p + 2)
        if d ~= "" and d:match("%d") then
            return true
        end
        i = p + 2
    end
end

local function ext_captures_key(ext)
    if not ext then
        return ""
    end
    local keys = {}
    for k in pairs(ext) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    local parts = {}
    for i = 1, #keys do
        local k = keys[i]
        parts[#parts + 1] = tostring(k) .. "=" .. tostring(ext[k] or "")
    end
    return table.concat(parts, ";")
end

local function build_plan(ir)
    local plan = {
        ir = ir,
        items = {},
        order = {},
        non_keyword_order = {},
        keyword_items = {},
        keyword_cs_by_first = {},
        keyword_ci_by_first = {},
        non_keyword_context_cache = {},
        keyword_context_cache = {},
        group_blit_cache = {},
        group_has_non_keyword = {},
        has_ignore_case = false,
        iskeyword = parse_iskeyword(ir.syntax_iskeyword),
        has_items = false,
        sync = ir.sync or {},
        _sync_linecont = nil,
    }

    local function add_keyword_index(dst, first_byte, item)
        if not first_byte then
            return
        end
        local bucket = dst[first_byte]
        if not bucket then
            bucket = {}
            dst[first_byte] = bucket
        end
        bucket[#bucket + 1] = item
    end

    for i = 1, #(ir.item_order or {}) do
        local item_id = ir.item_order[i]
        local src = ir.items[item_id]
        if src then
            local item = {
                id = src.id,
                kind = src.kind,
                group_id = src.group_id,
                group_name = src.group,
                ignore_case = src.ignore_case and true or false,
                options = src.options or { flags = {}, attrs = {}, unknown = {} },
                payload = src.payload or {},
                order = i,
            }
            if item.ignore_case then
                plan.has_ignore_case = true
            end

            if item.kind == "keyword" then
                local kw = tostring(item.payload.keyword or "")
                item.keyword = kw
                item.keyword_lower = kw:lower()
                item.keyword_len = #kw
                plan.keyword_items[#plan.keyword_items + 1] = item
                if kw ~= "" then
                    if item.ignore_case then
                        add_keyword_index(plan.keyword_ci_by_first, string.byte(item.keyword_lower, 1), item)
                    else
                        add_keyword_index(plan.keyword_cs_by_first, string.byte(kw, 1), item)
                    end
                end
            elseif item.kind == "match" then
                item.match_specs = {
                    build_compiled_spec(
                        item.payload.pattern,
                        item.ignore_case,
                        item.options.attrs,
                        item.options.matchgroup,
                        false,
                        { key = ("item:%d:match"):format(item.id), name = item.group_name }
                    )
                }
            elseif item.kind == "region" then
                item.start_specs = {}
                item.skip_specs = {}
                item.end_specs = {}
                item.needs_external_caps = false

                local starts = item.payload.start or {}
                for s = 1, #starts do
                    local spec = starts[s] or {}
                    item.start_specs[#item.start_specs + 1] = build_compiled_spec(
                        spec.pattern,
                        item.ignore_case,
                        item.options.attrs,
                        spec.matchgroup or item.options.matchgroup,
                        spec.excludenl or false,
                        { key = ("item:%d:start:%d"):format(item.id, s), name = item.group_name }
                    )
                end

                local skips = item.payload.skip or {}
                for s = 1, #skips do
                    local spec = skips[s] or {}
                    item.skip_specs[#item.skip_specs + 1] = build_compiled_spec(
                        spec.pattern,
                        item.ignore_case,
                        item.options.attrs,
                        spec.matchgroup or item.options.matchgroup,
                        spec.excludenl or false,
                        { key = ("item:%d:skip:%d"):format(item.id, s), name = item.group_name }
                    )
                end

                local ends = item.payload["end"] or {}
                for s = 1, #ends do
                    local spec = ends[s] or {}
                    local built = build_compiled_spec(
                        spec.pattern,
                        item.ignore_case,
                        item.options.attrs,
                        spec.matchgroup or item.options.matchgroup,
                        spec.excludenl or false,
                        { key = ("item:%d:end:%d"):format(item.id, s), name = item.group_name }
                    )
                    item.end_specs[#item.end_specs + 1] = built
                    if pattern_uses_external_backref(built.pattern or "") then
                        item.needs_external_caps = true
                    end
                end
            end

            if item.kind ~= "keyword" then
                plan.group_has_non_keyword[item.group_id] = true
            end

            plan.items[item_id] = item
            plan.order[#plan.order + 1] = item_id
            if item.kind ~= "keyword" then
                plan.non_keyword_order[#plan.non_keyword_order + 1] = item_id
            end
            plan.has_items = true
        end
    end

    if plan.sync and plan.sync.linecont then
        local patt, _ = split_delim_pattern(plan.sync.linecont)
        if patt and patt ~= "" then
            plan._sync_linecont = build_compiled_spec(patt, false, nil, nil, false)
        end
    end

    return plan
end

local function ensure_plan(ctx)
    local ir = ctx.syntax_ir
    if not ir then
        ctx.runtime_plan = nil
        return nil
    end
    local plan = ctx.runtime_plan
    if plan and plan.ir == ir then
        return plan
    end
    plan = build_plan(ir)
    ctx.runtime_plan = plan
    return plan
end

local function get_group_blit(plan, group_ref)
    local cache_key = 0
    if type(group_ref) == "number" then
        cache_key = group_ref
    elseif type(group_ref) == "string" and group_ref ~= "" then
        cache_key = "s:" .. group_ref
    end

    local cached = plan.group_blit_cache[cache_key]
    if cached then
        return cached[1], cached[2]
    end

    local name = "Normal"
    if type(group_ref) == "number" then
        local g = plan.ir.groups and plan.ir.groups[group_ref]
        if g and g.name and g.name ~= "" then
            name = g.name
        end
    elseif type(group_ref) == "string" and group_ref ~= "" then
        name = group_ref
    end

    local hl = Highlight.For(name)
    local fg = colors.toBlit(hl[1])
    local bg = colors.toBlit(hl[2])
    plan.group_blit_cache[cache_key] = { fg, bg }
    return fg, bg
end

local function active_visible_group(state)
    local stack = state.stack
    for i = #stack, 1, -1 do
        if not stack[i].transparent then
            return stack[i].group_id
        end
    end
    return nil
end

local function keyword_boundary_ok(line, s, e, iskw)
    local b1 = (s > 1) and string.byte(line, s - 1)
    local b2 = (e < #line) and string.byte(line, e + 1)
    if b1 and iskw[b1] then return false end
    if b2 and iskw[b2] then return false end
    return true
end

local function keyword_matches_at(hay, keyword, start_pos, keyword_len)
    local end_pos = start_pos + keyword_len - 1
    if end_pos > #hay then
        return false, end_pos
    end
    return str_sub(hay, start_pos, end_pos) == keyword, end_pos
end

local function normalize_match_span(line_len, s, e, offsets)
    local mstart, mend = s, e
    local hstart, hend = s, e

    if offsets then
        local applied = VimRegex.apply_syntax_offsets(s, e, offsets)
        mstart = applied.ms or applied.rs or mstart
        mend = applied.me or applied.re or mend
        hstart = applied.hs or mstart
        hend = applied.he or mend
    end

    mstart = clamp(mstart, 1, math.max(1, line_len))
    mend = clamp(mend, 0, line_len)
    hstart = clamp(hstart, 1, math.max(1, line_len))
    hend = clamp(hend, 0, line_len)

    return mstart, mend, hstart, hend
end

local function find_in_spec(line, lower_line, start_pos, spec, anchored, ext_in, capture_caps)
    if not spec or not spec.compiled then return nil end
    if start_pos > (#line + 1) then return nil end

    local hay = spec.ignore_case and lower_line or line
    local lc = spec.lc or 0
    local search_pos = start_pos
    if lc > 0 then
        search_pos = start_pos - lc
        if search_pos < 1 then search_pos = 1 end
    end

    local caps, p_start = nil, nil
    local s, e
    local profile = PROFILE_CTX and PROFILE_CTX.profile
    if profile and profile.enabled then
        p_start = profile_now()
    end
    if capture_caps or ext_in then
        s, e, caps = VimRegex.find_compiled_with_caps(hay, spec.compiled, not spec.ignore_case, ext_in, search_pos)
    else
        s, e = VimRegex.find_compiled(hay, spec.compiled, not spec.ignore_case, search_pos)
    end
    if p_start then
        profile_record(spec, s ~= nil, profile_now() - p_start)
    end
    if not s then
        return nil
    end
    local abs_s = s
    local abs_e = e

    local ms, me, hs, he = abs_s, abs_e, abs_s, abs_e
    if spec.offsets then
        ms, me, hs, he = normalize_match_span(#line, abs_s, abs_e, spec.offsets)
    end
    if anchored and ms ~= start_pos then
        return nil
    end
    return {
        match_start = ms,
        match_end = me,
        hi_start = hs,
        hi_end = he,
        raw_start = abs_s,
        raw_end = abs_e,
        ext_captures = caps,
        spec = spec,
    }
end

local function pick_earliest_event(current, candidate)
    if not candidate then return current end
    if not current then return candidate end

    if candidate.match_start < current.match_start then
        return candidate
    elseif candidate.match_start > current.match_start then
        return current
    end

    local ck = current.kind == "keyword"
    local nk = candidate.kind == "keyword"
    if nk ~= ck then
        return nk and candidate or current
    end

    if nk and ck then
        local ci = current.item and current.item.ignore_case or false
        local ni = candidate.item and candidate.item.ignore_case or false
        if ci ~= ni then
            -- For equal-start keywords, case-sensitive wins over ignore-case.
            return (not ni) and candidate or current
        end
    end

    local co = current.item and current.item.order or math.huge
    local no = candidate.item and candidate.item.order or math.huge
    -- For equal starts, later-defined items take precedence.
    if no > co then
        return candidate
    end
    return current
end

local function container_allows(item, top)
    if not top then
        return not item.options.flags.contained
    end

    local containedin_ok = bit_has(item.options.containedin_bits, top.group_id)
    local contains_bits = top.contains_bits
    if contains_bits then
        if bit_has(contains_bits, item.group_id) or containedin_ok then
            return true
        end
        return false
    end

    if item.options.flags.contained then
        return containedin_ok
    end
    return true
end

local function allows_by_nextgroup(item, pending_next)
    if not pending_next then return true end
    return bit_has(pending_next.bits, item.group_id)
end

local function find_match_or_region_event(item, line, lower_line, pos, anchored)
    local specs = item.kind == "match" and item.match_specs or item.start_specs
    local capture_caps = item.kind == "region" and item.needs_external_caps
    local event = nil
    for i = 1, #specs do
        local found = find_in_spec(line, lower_line, pos, specs[i], anchored, nil, capture_caps)
        if found then
            found.kind = item.kind
            found.item = item
            event = pick_earliest_event(event, found)
        end
    end
    return event
end

local function keyword_allowed_in_context(item, top, pending_next)
    if not allows_by_nextgroup(item, pending_next) then
        return false
    end
    if pending_next then
        -- nextgroup explicitly selects allowed follow-up items; those
        -- matches should not be blocked by current container contains=.
        return true
    end
    return container_allows(item, top)
end

local function context_cache_key(top)
    if not top then
        return "__TOP__"
    end
    if top.item_id then
        return "__ITEM__" .. tostring(top.item_id)
    end
    return "__CTX__" .. tostring(top.group_id) .. ":" .. tostring(top.contains_bits)
end

local function non_keyword_candidates(plan, top, pending_next)
    if pending_next then
        return plan.non_keyword_order
    end

    local key = context_cache_key(top)
    local cached = plan.non_keyword_context_cache[key]
    if cached then
        return cached
    end

    local out = {}
    for i = 1, #plan.non_keyword_order do
        local item_id = plan.non_keyword_order[i]
        local item = plan.items[item_id]
        if item and container_allows(item, top) then
            out[#out + 1] = item_id
        end
    end
    plan.non_keyword_context_cache[key] = out
    return out
end

local function keyword_context_buckets(plan, top, pending_next)
    if pending_next then
        return plan.keyword_cs_by_first, plan.keyword_ci_by_first, false
    end

    local key = context_cache_key(top)
    local cached = plan.keyword_context_cache[key]
    if cached then
        return cached.cs, cached.ci, true
    end

    local cs = {}
    local ci = {}
    for i = 1, #plan.keyword_items do
        local item = plan.keyword_items[i]
        if container_allows(item, top) then
            local first = item.ignore_case and string.byte(item.keyword_lower, 1) or string.byte(item.keyword, 1)
            if first then
                local dst = item.ignore_case and ci or cs
                local bucket = dst[first]
                if not bucket then
                    bucket = {}
                    dst[first] = bucket
                end
                bucket[#bucket + 1] = item
            end
        end
    end

    plan.keyword_context_cache[key] = { cs = cs, ci = ci }
    return cs, ci, true
end

local function find_best_keyword_event(plan, top, pending_next, line, lower_line, pos, anchored, syn_limit)
    local scan_end = math.min(#line, syn_limit)
    if pos > scan_end then
        return nil
    end

    local cs_buckets, ci_buckets, context_filtered = keyword_context_buckets(plan, top, pending_next)

    local function try_bucket(bucket, start_pos, best)
        if not bucket then
            return best
        end
        for i = 1, #bucket do
            local item = bucket[i]
            if context_filtered or keyword_allowed_in_context(item, top, pending_next) then
                local hay = item.ignore_case and lower_line or line
                local kw = item.ignore_case and item.keyword_lower or item.keyword
                local ok, e = keyword_matches_at(hay, kw, start_pos, item.keyword_len)
                if ok then
                    if keyword_boundary_ok(line, start_pos, e, plan.iskeyword) then
                        best = pick_earliest_event(best, {
                            kind = "keyword",
                            match_start = start_pos,
                            match_end = e,
                            hi_start = start_pos,
                            hi_end = e,
                            raw_start = start_pos,
                            raw_end = e,
                            item = item,
                        })
                    end
                end
            end
        end
        return best
    end

    local scan = pos
    while scan <= scan_end do
        local best = nil
        local ch = string.byte(line, scan)
        best = try_bucket(cs_buckets[ch], scan, best)
        local lch = string.byte(lower_line, scan)
        best = try_bucket(ci_buckets[lch], scan, best)

        if best then
            return best
        end
        if anchored then
            return nil
        end
        scan = scan + 1
    end

    return nil
end

local function find_best_start_event(plan, state, line, lower_line, pos, anchored, syn_limit)
    local best = nil
    local stack = state.stack
    local top = stack[#stack]
    local pending_next = state.pending_next

    local keyword_at_pos = find_best_keyword_event(plan, top, pending_next, line, lower_line, pos, true, pos)
    if keyword_at_pos then
        return keyword_at_pos
    end

    local candidate_ids = non_keyword_candidates(plan, top, pending_next)
    for i = #candidate_ids, 1, -1 do
        local item = plan.items[candidate_ids[i]]
        if item then
            if allows_by_nextgroup(item, pending_next) then
                local candidate = find_match_or_region_event(item, line, lower_line, pos, anchored)
                if candidate and candidate.match_start <= syn_limit then
                    best = pick_earliest_event(best, candidate)
                    if candidate.match_start == pos then
                        return candidate
                    end
                end
            end
        end
    end

    local keyword_limit = syn_limit
    if best and best.match_start < keyword_limit then
        keyword_limit = best.match_start
    end
    local keyword_best = find_best_keyword_event(
        plan,
        top,
        pending_next,
        line,
        lower_line,
        pos,
        anchored,
        keyword_limit
    )
    if keyword_best then
        best = pick_earliest_event(best, keyword_best)
    end

    return best
end

local function find_region_end_event(entry, line, lower_line, pos, syn_limit)
    local function earliest_in_specs(specs, from_pos)
        local found = nil
        local found_idx = nil
        for i = 1, #specs do
            local hit = find_in_spec(line, lower_line, from_pos, specs[i], false, entry.ext_captures, false)
            if hit and hit.match_start <= syn_limit then
                if not found or hit.match_start < found.match_start then
                    found = hit
                    found_idx = i
                elseif hit.match_start == found.match_start and (found_idx == nil or i > found_idx) then
                    -- For equal-start region end/skip specs, prefer later-defined specs.
                    -- This matches help.vim behavior where a later end= pattern can refine
                    -- an earlier broad one at the same position.
                    found = hit
                    found_idx = i
                end
            end
        end
        return found
    end

    local search_from = pos
    while search_from <= syn_limit do
        local fin = earliest_in_specs(entry.end_specs or {}, search_from)
        if not fin then
            return nil
        end

        local skip = earliest_in_specs(entry.skip_specs or {}, search_from)
        if skip and skip.match_start <= fin.match_start then
            local nxt = math.max(skip.raw_end + 1, skip.match_end + 1, search_from + 1)
            if nxt <= search_from then
                nxt = search_from + 1
            end
            search_from = nxt
        else
            fin.kind = "end"
            fin.item = entry.item
            fin.entry = entry
            return fin
        end
    end

    return nil
end

local function resolve_resync_start(plan, buffer, target_line)
    local sync = plan.sync or {}
    if sync.fromstart then
        return 1
    end

    local maxlines = tonumber(sync.maxlines) or tonumber(sync.minlines) or DEFAULT_RESYNC_MAXLINES
    if maxlines < 0 then maxlines = 0 end
    local start = math.max(1, target_line - maxlines)

    local minlines = tonumber(sync.minlines)
    if minlines and minlines > 0 then
        local must_start = math.max(1, target_line - minlines)
        if start > must_start then
            start = must_start
        end
    end

    local linecont = plan._sync_linecont
    if linecont and linecont.compiled then
        local probe = start
        while probe > 1 do
            local prev = buffer_get_line(buffer, probe - 1)
            local low = prev:lower()
            local hit = find_in_spec(prev, low, 1, linecont, false)
            if not hit or hit.match_end ~= #prev then
                break
            end
            probe = probe - 1
        end
        start = probe
    end

    local items = sync.items or {}
    if #items > 0 then
        local anchor = nil
        for ln = target_line, start, -1 do
            local text = buffer_get_line(buffer, ln)
            local low = text:lower()
            for i = 1, #items do
                local it = items[i]
                local patt = nil
                if it.kind == "sync_match" then
                    patt = it.pattern
                elseif it.kind == "sync_region" and it.patterns and it.patterns.start and it.patterns.start[1] then
                    patt = it.patterns.start[1].pattern
                end
                if patt and patt ~= "" then
                    local spec = build_compiled_spec(patt, false, it.options and it.options.attrs, nil, false)
                    local ev = find_in_spec(text, low, 1, spec, false)
                    if ev then
                        if it.sync_point == "groupthere" then
                            anchor = math.min(target_line, ln + 1)
                        else
                            anchor = ln
                        end
                        break
                    end
                end
            end
            if anchor then break end
        end
        if anchor then start = anchor end
    end

    if sync.ccomment then
        local probe = target_line
        local bound = start
        while probe >= bound do
            local text = buffer_get_line(buffer, probe)
            if text:find("/%*") or text:find("%*/") then
                start = probe
                break
            end
            probe = probe - 1
        end
    end

    return clamp(start, 1, math.max(1, target_line))
end

local function nearest_checkpoint_line(ctx, line)
    local ln = line
    while ln > 1 do
        if ctx.checkpoints[ln] then
            return ln
        end
        ln = ln - 1
    end
    return 1
end

local function checkpoint_hash(cp)
    if not cp then
        return nil
    end
    local h = cp.hash
    if h == nil and cp.state then
        h = state_hash(cp.state)
        cp.hash = h
    end
    return h
end

local function line_blit_from_spans(plan, line, spans)
    local len = #line
    if len == 0 then
        return "", ""
    end

    local groups = {}
    local assigned = 0
    for i = #spans, 1, -1 do
        local span = spans[i]
        local s = clamp(span.s or 1, 1, len)
        local e = clamp(span.e or len, 1, len)
        if e >= s then
            for j = s, e do
                if groups[j] == nil then
                    groups[j] = span.group_id
                    assigned = assigned + 1
                end
            end
            if assigned >= len then
                break
            end
        end
    end

    local fg_parts = {}
    local bg_parts = {}

    local run_gid = groups[1]
    local run_start = 1
    for i = 2, len do
        local gid = groups[i]
        if gid ~= run_gid then
            local fg, bg = get_group_blit(plan, run_gid)
            local count = i - run_start
            fg_parts[#fg_parts + 1] = string.rep(fg, count)
            bg_parts[#bg_parts + 1] = string.rep(bg, count)
            run_gid = gid
            run_start = i
        end
    end
    do
        local fg, bg = get_group_blit(plan, run_gid)
        local count = len - run_start + 1
        fg_parts[#fg_parts + 1] = string.rep(fg, count)
        bg_parts[#bg_parts + 1] = string.rep(bg, count)
    end

    return table.concat(fg_parts), table.concat(bg_parts)
end

local function ensure_highlight_version(ctx, plan)
    local version = Highlight.Version()
    if ctx._hl_version == version then
        return
    end

    ctx._hl_version = version
    plan.group_blit_cache = {}
    for _, entry in pairs(ctx.span_cache) do
        entry.blit_fg = nil
        entry.blit_bg = nil
        entry.blit_hl_version = nil
    end
end

local function get_matchgroup_name(spec)
    local mg = spec and spec.matchgroup
    if not mg or mg == "" or mg == "NONE" then
        return nil
    end
    return mg
end

local function resolved_matchgroup_ref(plan, spec)
    local mg = get_matchgroup_name(spec)
    if not mg then
        return nil
    end
    if not (plan and plan.ir and plan.ir.group_ids) then
        return mg
    end
    return plan.ir.group_ids[mg] or mg
end

local function should_paint_region_delim(entry, spec)
    if not entry then
        return false
    end
    if not entry.transparent then
        return true
    end
    return get_matchgroup_name(spec) ~= nil
end

local function contains_has_non_keyword(plan, contains_ids)
    if not contains_ids then
        return false
    end
    for i = 1, #contains_ids do
        if plan.group_has_non_keyword[contains_ids[i]] then
            return true
        end
    end
    return false
end

local function paint_match_contained_keywords(plan, item, line, lower_line, range_s, range_e, max_col, spans)
    local contains_bits = item.options.contains_bits
    if not contains_bits then
        return
    end

    local container = {
        group_id = item.group_id,
        contains_bits = contains_bits,
    }
    local pos = range_s
    while pos <= range_e do
        local best = find_best_keyword_event(plan, container, nil, line, lower_line, pos, false, range_e)
        if not best then
            break
        end
        local hs = clamp(best.hi_start, range_s, max_col)
        local he = clamp(best.hi_end, 0, range_e)
        if he >= hs then
            spans[#spans + 1] = {
                s = hs,
                e = he,
                group_id = best.item.group_id,
                conceal = best.item.options.flags.conceal or false,
                concealends = best.item.options.flags.concealends or false,
                cchar = best.item.options.cchar,
                fold = best.item.options.flags.fold or false,
                display = best.item.options.flags.display or false,
            }
        end
        pos = math.max(best.match_end + 1, pos + 1)
    end
end

local function paint_match_contained_items(plan, item, line, lower_line, range_s, range_e, max_col, spans)
    local contains_bits = item.options.contains_bits
    if not contains_bits then
        return
    end

    local contains_ids = item.options.contains_ids
    if not contains_has_non_keyword(plan, contains_ids) then
        paint_match_contained_keywords(plan, item, line, lower_line, range_s, range_e, max_col, spans)
        return
    end

    local container = {
        group_id = item.group_id,
        contains_bits = contains_bits,
    }
    local state = {
        stack = { container },
        pending_next = nil,
    }

    local pos = range_s
    while pos <= range_e do
        local best = find_best_start_event(plan, state, line, lower_line, pos, false, range_e)
        if not best then
            break
        end

        local inner = best.item
        if inner and best.kind ~= "region" and not inner.options.flags.transparent then
            local group_id = inner.group_id
            local mgref = resolved_matchgroup_ref(plan, best.spec)
            if mgref then group_id = mgref end
            local hs = clamp(best.hi_start, range_s, max_col)
            local he = clamp(best.hi_end, 0, range_e)
            if he >= hs then
                spans[#spans + 1] = {
                    s = hs,
                    e = he,
                    group_id = group_id,
                    conceal = inner.options.flags.conceal or false,
                    concealends = inner.options.flags.concealends or false,
                    cchar = inner.options.cchar,
                    fold = inner.options.flags.fold or false,
                    display = inner.options.flags.display or false,
                }
            end
        end

        pos = math.max(best.raw_end + 1, best.match_end + 1, pos + 1)
    end
end

local function region_start_has_span_marker(event)
    local patt = event and event.spec and event.spec.pattern or ""
    if patt:find("\\zs", 1, true) or patt:find("\\ze", 1, true) then
        return true
    end
    return false
end

local function region_start_advance(event, cursor_pos)
    if region_start_has_span_marker(event) then
        return math.max(event.match_start + 1, cursor_pos + 1)
    end
    return math.max(event.raw_end + 1, event.match_end + 1, cursor_pos + 1)
end

local function paint_anchored_contained_start(plan, state, line, lower_line, start_pos, max_col, spans)
    local anchored = find_best_start_event(plan, state, line, lower_line, start_pos, true, max_col)
    if not anchored or anchored.kind == "region" then
        return nil
    end

    local item = anchored.item
    if item and not item.options.flags.transparent then
        local group_id = item.group_id
        local mgref = resolved_matchgroup_ref(plan, anchored.spec)
        if mgref then group_id = mgref end
        local hs = clamp(anchored.hi_start, 1, max_col)
        local he = clamp(anchored.hi_end, 0, max_col)
        if he >= hs then
            spans[#spans + 1] = {
                s = hs,
                e = he,
                group_id = group_id,
                conceal = item.options.flags.conceal or false,
                concealends = item.options.flags.concealends or false,
                cchar = item.options.cchar,
                fold = item.options.flags.fold or false,
                display = item.options.flags.display or false,
            }
        end
    end

    if item and item.kind == "match" then
        local rs = clamp(anchored.match_start, 1, max_col)
        local re = clamp(anchored.match_end, 0, max_col)
        if re >= rs then
            paint_match_contained_items(plan, item, line, lower_line, rs, re, max_col, spans)
        end
    end

    return math.max(anchored.raw_end + 1, anchored.match_end + 1, start_pos + 1)
end

local function highlight_line(plan, state_in, line, syn_limit)
    local len = #line
    local max_col = syn_limit
    if max_col <= 0 then
        max_col = len
    else
        max_col = math.min(len, max_col)
    end

    local state = clone_state(state_in)
    local lower_line = plan.has_ignore_case and line:lower() or line

    local spans = {}
    local pos = 1

    local function apply_end_event(event, cursor_pos)
        local popped = table.remove(state.stack)
        if not popped then
            return cursor_pos + 1
        end

        if max_col > 0 and should_paint_region_delim(popped, event.spec) then
            local group_id = popped.group_id
            local mgref = resolved_matchgroup_ref(plan, event.spec)
            if mgref then group_id = mgref end
            local hs = clamp(event.hi_start, 1, max_col)
            local he = clamp(event.hi_end, 0, max_col)
            spans[#spans + 1] = {
                s = hs, e = he, group_id = group_id,
                conceal = popped.conceal,
                concealends = popped.concealends,
                cchar = popped.cchar,
                fold = popped.fold,
                display = popped.display,
            }
        end

        if popped.item and popped.item.options and popped.item.options.nextgroup_bits then
            state.pending_next = make_pending_next(
                popped.item.options.nextgroup_bits,
                popped.item.options.flags.skipwhite or false,
                popped.item.options.flags.skipnl or false,
                popped.item.options.flags.skipempty or false
            )
        end

        -- Continue from the logical end of the item (offset-adjusted match end),
        -- not the raw regex end. This is required for me=/re= offsets and
        -- nextgroup hand-off at adjusted boundaries (e.g. Lua "if ... then").
        local next_from = (event.match_end or cursor_pos) + 1
        if next_from < cursor_pos then
            next_from = cursor_pos
        end
        return next_from
    end

    while pos <= max_col do
        local pending = state.pending_next
        if pending then
            local ch = line:sub(pos, pos)
            if pending.skipwhite and is_whitespace_char(ch) then
                local gid = active_visible_group(state)
                if gid then
                    spans[#spans + 1] = { s = pos, e = pos, group_id = gid }
                end
                pos = pos + 1
                goto continue
            end

            local anchored = find_best_start_event(plan, state, line, lower_line, pos, true, max_col)
            if anchored then
                local item = anchored.item
                if item.kind == "keyword" or item.kind == "match" then
                    if not item.options.flags.transparent then
                        local hs = clamp(anchored.hi_start, 1, max_col)
                        local he = clamp(anchored.hi_end, 0, max_col)
                        spans[#spans + 1] = {
                            s = hs, e = he, group_id = item.group_id,
                            conceal = item.options.flags.conceal or false,
                            concealends = item.options.flags.concealends or false,
                            cchar = item.options.cchar,
                            fold = item.options.flags.fold or false,
                            display = item.options.flags.display or false,
                        }
                    end
                    if item.kind == "match" then
                        local rs = clamp(anchored.match_start, 1, max_col)
                        local re = clamp(anchored.match_end, 0, max_col)
                        if re >= rs then
                            paint_match_contained_items(plan, item, line, lower_line, rs, re, max_col, spans)
                        end
                    end
                    state.pending_next = nil
                    if item.options.nextgroup_bits then
                        state.pending_next = make_pending_next(
                            item.options.nextgroup_bits,
                            item.options.flags.skipwhite or false,
                            item.options.flags.skipnl or false,
                            item.options.flags.skipempty or false
                        )
                    end
                    local nxt = math.max(anchored.raw_end + 1, anchored.match_end + 1, pos + 1)
                    pos = nxt
                    goto continue
                else
                    local entry = {
                        item_id = item.id,
                        item = item,
                        group_id = item.group_id,
                        transparent = item.options.flags.transparent or false,
                        contains_bits = item.options.contains_bits,
                        keepend = item.options.flags.keepend or false,
                        extend = item.options.flags.extend or false,
                        oneline = item.options.flags.oneline or false,
                        conceal = item.options.flags.conceal or false,
                        concealends = item.options.flags.concealends or false,
                        cchar = item.options.cchar,
                        fold = item.options.flags.fold or false,
                        display = item.options.flags.display or false,
                        end_specs = item.end_specs or {},
                        skip_specs = item.skip_specs or {},
                        ext_captures = anchored.ext_captures,
                        ext_key = ext_captures_key(anchored.ext_captures),
                    }
                    entry.hash_token = region_entry_hash_token(entry)
                    state.stack[#state.stack + 1] = entry
                    state.pending_next = nil

                    if should_paint_region_delim(entry, anchored.spec) then
                        local group_id = entry.group_id
                        local mgref = resolved_matchgroup_ref(plan, anchored.spec)
                        if mgref then group_id = mgref end
                        local hs = clamp(anchored.hi_start, 1, max_col)
                        local he = clamp(anchored.hi_end, 0, max_col)
                        spans[#spans + 1] = {
                            s = hs, e = he, group_id = group_id,
                            conceal = entry.conceal,
                            concealends = entry.concealends,
                            cchar = entry.cchar,
                            fold = entry.fold,
                            display = entry.display,
                        }
                    end

                    local anchored_pos = nil
                    if region_start_has_span_marker(anchored) then
                        anchored_pos = paint_anchored_contained_start(
                            plan,
                            state,
                            line,
                            lower_line,
                            anchored.match_start,
                            max_col,
                            spans
                        )
                    end
                    if anchored_pos then
                        pos = anchored_pos
                    else
                        pos = region_start_advance(anchored, pos)
                    end
                    goto continue
                end
            else
                state.pending_next = nil
            end
        end

        local top = state.stack[#state.stack]
        local end_ev = top and find_region_end_event(top, line, lower_line, pos, max_col)
        local start_ev = find_best_start_event(plan, state, line, lower_line, pos, false, max_col)

        local event
        if end_ev and start_ev then
            if end_ev.match_start < start_ev.match_start then
                event = end_ev
            elseif end_ev.match_start > start_ev.match_start then
                event = start_ev
            else
                -- At the same position, region end wins over contained starts/matches.
                -- This prevents false error tokens on valid delimiters.
                event = end_ev
            end
        else
            event = end_ev or start_ev
        end

        if not event then
            local gid = active_visible_group(state)
            if gid then
                spans[#spans + 1] = { s = pos, e = max_col, group_id = gid }
            end
            break
        end

        if event.match_start > pos then
            local gid = active_visible_group(state)
            if gid then
                local se = event.match_start - 1
                spans[#spans + 1] = { s = pos, e = se, group_id = gid }
            end
            pos = event.match_start
        end

        if event.kind == "end" then
            pos = apply_end_event(event, pos)
        else
            local item = event.item
            if item.kind == "region" then
                local entry = {
                    item_id = item.id,
                    item = item,
                    group_id = item.group_id,
                    transparent = item.options.flags.transparent or false,
                    contains_bits = item.options.contains_bits,
                    keepend = item.options.flags.keepend or false,
                    extend = item.options.flags.extend or false,
                    oneline = item.options.flags.oneline or false,
                    conceal = item.options.flags.conceal or false,
                    concealends = item.options.flags.concealends or false,
                    cchar = item.options.cchar,
                    fold = item.options.flags.fold or false,
                    display = item.options.flags.display or false,
                    end_specs = item.end_specs or {},
                    skip_specs = item.skip_specs or {},
                    ext_captures = event.ext_captures,
                    ext_key = ext_captures_key(event.ext_captures),
                }
                entry.hash_token = region_entry_hash_token(entry)
                state.stack[#state.stack + 1] = entry
                state.pending_next = nil

                if should_paint_region_delim(entry, event.spec) then
                    local group_id = entry.group_id
                    local mgref = resolved_matchgroup_ref(plan, event.spec)
                    if mgref then group_id = mgref end
                    local hs = clamp(event.hi_start, 1, max_col)
                    local he = clamp(event.hi_end, 0, max_col)
                    spans[#spans + 1] = {
                        s = hs, e = he, group_id = group_id,
                        conceal = entry.conceal,
                        concealends = entry.concealends,
                        cchar = entry.cchar,
                        fold = entry.fold,
                        display = entry.display,
                    }
                end
                local anchored_pos = nil
                if region_start_has_span_marker(event) then
                    anchored_pos = paint_anchored_contained_start(
                        plan,
                        state,
                        line,
                        lower_line,
                        event.match_start,
                        max_col,
                        spans
                    )
                end
                if anchored_pos then
                    pos = anchored_pos
                else
                    pos = region_start_advance(event, pos)
                end
            else
                if not item.options.flags.transparent then
                    local group_id = item.group_id
                    local mgref = resolved_matchgroup_ref(plan, event.spec)
                    if mgref then group_id = mgref end
                    local hs = clamp(event.hi_start, 1, max_col)
                    local he = clamp(event.hi_end, 0, max_col)
                    spans[#spans + 1] = {
                        s = hs, e = he, group_id = group_id,
                        conceal = item.options.flags.conceal or false,
                        concealends = item.options.flags.concealends or false,
                        cchar = item.options.cchar,
                        fold = item.options.flags.fold or false,
                        display = item.options.flags.display or false,
                    }
                end
                if item.kind == "match" then
                    local rs = clamp(event.match_start, 1, max_col)
                    local re = clamp(event.match_end, 0, max_col)
                    if re >= rs then
                        paint_match_contained_items(plan, item, line, lower_line, rs, re, max_col, spans)
                    end
                end

                state.pending_next = nil
                if item.options.nextgroup_bits then
                    state.pending_next = make_pending_next(
                        item.options.nextgroup_bits,
                        item.options.flags.skipwhite or false,
                        item.options.flags.skipnl or false,
                        item.options.flags.skipempty or false
                    )
                end
                pos = math.max(event.raw_end + 1, event.match_end + 1, pos + 1)
            end
        end

        ::continue::
    end

    -- Handle regions that can end at EOL when no more scanning happened
    -- (for example empty lines, or start patterns that consumed to EOL).
    local eol_limit = max_col + 1
    while true do
        local top = state.stack[#state.stack]
        if not top then
            break
        end
        local end_ev = find_region_end_event(top, line, lower_line, eol_limit, eol_limit)
        if not end_ev then
            break
        end
        apply_end_event(end_ev, eol_limit)
    end

    while #state.stack > 0 and state.stack[#state.stack].oneline do
        local popped = table.remove(state.stack)
        if popped and popped.item and popped.item.options and popped.item.options.nextgroup_bits then
            state.pending_next = make_pending_next(
                popped.item.options.nextgroup_bits,
                popped.item.options.flags.skipwhite or false,
                popped.item.options.flags.skipnl or false,
                popped.item.options.flags.skipempty or false
            )
        end
    end

    if state.pending_next then
        if not state.pending_next.skipnl then
            state.pending_next = nil
        elseif is_blank_line(line) and not state.pending_next.skipempty then
            state.pending_next = nil
        end
    end

    return state, spans
end

local function recompute_to_line(ctx, plan, buffer, target_line, force_from_start)
    local prev_profile_ctx = PROFILE_CTX
    PROFILE_CTX = ctx

    local line_count = buffer_line_count(buffer)
    if line_count < 1 then
        PROFILE_CTX = prev_profile_ctx
        return
    end

    ensure_line_count_consistency(ctx, line_count)
    trim_caches_to_buffer(ctx, line_count)

    local dirty_from = ctx.dirty_from or 1
    if dirty_from < 1 then dirty_from = 1 end
    if dirty_from > line_count then dirty_from = line_count end

    local recompute_end = math.min(line_count, math.max(target_line, dirty_from + RECOMPUTE_BATCH - 1))
    local nearest_cp = nearest_checkpoint_line(ctx, dirty_from)
    local start = nearest_cp

    if force_from_start then
        start = 1
    elseif plan.sync and plan.sync.fromstart then
        start = 1
    elseif dirty_from == 1 then
        start = resolve_resync_start(plan, buffer, target_line)
    end

    local base_cp = ctx.checkpoints[start]
    local state = base_cp and base_cp.state or new_state()

    local can_converge = not ctx._structure_changed and target_line > dirty_from

    local converged_to = nil

    for ln = start, recompute_end do
        local old_next_hash = nil
        local old_text = nil
        if can_converge and ln >= dirty_from then
            local cp_next = ctx.checkpoints[ln + 1]
            old_next_hash = checkpoint_hash(cp_next)
            local sp = ctx.span_cache[ln]
            old_text = sp and sp.line_text
        end

        local before = state
        ctx.checkpoints[ln] = { state = before }

        local text = buffer_get_line(buffer, ln)
        local next_state, spans = highlight_line(plan, state, text, ctx.synmaxcol or 0)
        local after = next_state
        local after_hash = nil
        if old_next_hash then
            after_hash = state_hash(after)
        end

        ctx.span_cache[ln] = {
            line_text = text,
            spans = spans,
        }
        ctx.checkpoints[ln + 1] = {
            state = after,
            hash = after_hash,
        }

        state = after

        if can_converge and ln >= dirty_from then
            if old_next_hash and old_next_hash == after_hash and old_text == text then
                converged_to = ln + 1
                if ln >= target_line then
                    break
                end
                local target_cache = ctx.span_cache[target_line]
                if target_cache and target_cache.line_text == buffer_get_line(buffer, target_line) then
                    break
                end
            end
        end
    end

    if converged_to then
        if converged_to > ctx.dirty_from then
            ctx.dirty_from = converged_to
        end
    else
        local next_dirty = recompute_end + 1
        if next_dirty > ctx.dirty_from then
            ctx.dirty_from = next_dirty
        end
    end

    if ctx.dirty_from < 1 then ctx.dirty_from = 1 end
    if ctx.dirty_from > line_count + 1 then ctx.dirty_from = line_count + 1 end
    ctx._structure_changed = false
    PROFILE_CTX = prev_profile_ctx
end

local function line_blit_cached(ctx, plan, buffer, line)
    local current_text = buffer_get_line(buffer, line)
    local cache = ctx.span_cache[line]
    if not cache or cache.line_text ~= current_text then
        return nil
    end
    if cache.blit_hl_version == ctx._hl_version and cache.blit_fg and cache.blit_bg then
        return { fg = cache.blit_fg, bg = cache.blit_bg }
    end
    local fg, bg = line_blit_from_spans(plan, current_text, cache.spans)
    cache.blit_fg = fg
    cache.blit_bg = bg
    cache.blit_hl_version = ctx._hl_version
    return { fg = fg, bg = bg }
end

function Runtime.line_to_blit(ctx, buffer, line)
    local plan = ensure_plan(ctx)
    if not plan or not plan.has_items then
        return nil
    end
    ensure_highlight_version(ctx, plan)

    local line_count = buffer_line_count(buffer)
    if line_count == 0 then
        return nil
    end
    if line < 1 or line > line_count then
        return nil
    end

    if not ctx.checkpoints[1] then
        local st = new_state()
        ctx.checkpoints[1] = { state = st }
    end

    local cache = ctx.span_cache[line]
    if cache and line < (ctx.dirty_from or 1) then
        local out = line_blit_cached(ctx, plan, buffer, line)
        if out then
            return out
        end
    end

    recompute_to_line(ctx, plan, buffer, line)

    return line_blit_cached(ctx, plan, buffer, line)
end

function Runtime.lines_to_blit(ctx, buffer, first_line, last_line)
    local plan = ensure_plan(ctx)
    if not plan or not plan.has_items then
        return {}
    end
    ensure_highlight_version(ctx, plan)

    local line_count = buffer_line_count(buffer)
    if line_count == 0 then
        return {}
    end

    local first = first_line or 1
    local last = last_line or line_count
    if first < 1 then first = 1 end
    if last > line_count then last = line_count end
    if first > last then
        return {}
    end

    if not ctx.checkpoints[1] then
        local st = new_state()
        ctx.checkpoints[1] = { state = st }
    end

    if (ctx.dirty_from or 1) <= last then
        local full_buffer_request = (first == 1 and last == line_count)
        recompute_to_line(ctx, plan, buffer, last, full_buffer_request)
    end

    local out = {}
    for ln = first, last do
        out[ln] = line_blit_cached(ctx, plan, buffer, ln)
    end
    return out
end

return Runtime
