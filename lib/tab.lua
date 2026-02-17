local Tab = {}

local floor = math.floor

local _cfg_cache = { vts_raw = nil, ts_raw = nil, cfg = nil }

local function parse_vartabstop_list_fast(raw)
    if not raw or raw == "" then return {} end
    local widths, items = {}, options.ParseCSL(raw)
    for i = 1, #items do
        local n = tonumber(items[i])
        if n and n > 0 then widths[#widths + 1] = n end
    end
    return widths
end

function Tab.get_tab_config(buffer)
    local vts_raw = options.get("vartabstop", nil, buffer) or ""
    local ts_raw  = options.get("tabstop", nil, buffer)
    if ts_raw == nil then ts_raw = 8 end
    local ts = tonumber(ts_raw) or 8
    if ts <= 0 then ts = 8 end

    -- Rebuild only if inputs changed
    if _cfg_cache.vts_raw == vts_raw and _cfg_cache.ts_raw == ts_raw and _cfg_cache.cfg then
        return _cfg_cache.cfg
    end

    local vts = parse_vartabstop_list_fast(vts_raw)
    -- prefix sums for binary search
    local prefix = {}
    if #vts > 0 then
        local acc = 0
        for i = 1, #vts do
            acc = acc + vts[i]
            prefix[i] = acc
        end
    end

    local cfg = {
        vts = vts,
        ts = ts,
        prefix = prefix,       -- prefix[i] = sum(vts[1..i])
        last_step = vts[#vts], -- repeat step once beyond last prefix
    }
    _cfg_cache.vts_raw, _cfg_cache.ts_raw, _cfg_cache.cfg = vts_raw, ts_raw, cfg
    return cfg
end

--- Compute the next display tab stop column (> col), using binary search for vartabstop.
---@param col integer  -- current 0-based visual column
---@param cfg table    -- { vts, ts, prefix, last_step }
---@return integer
function Tab.next_display_tabstop(col, cfg)
    local prefix = cfg.prefix
    local plen = #prefix
    if plen > 0 then
        if col < prefix[plen] then
            -- binary search first prefix > col
            local lo, hi = 1, plen
            while lo < hi do
                local mid = floor((lo + hi) / 2)
                if col < prefix[mid] then
                    hi = mid
                else
                    lo = mid + 1
                end
            end
            return prefix[lo]
        else
            -- repeat last width
            local cum  = prefix[plen]
            local step = cfg.last_step
            local k    = floor((col - cum) / step) + 1
            return cum + k * step
        end
    end
    -- simple tabstop
    local ts = cfg.ts
    local rem = ts - (col % ts)
    if rem == 0 then rem = ts end
    return col + rem
end

--- Compute the previous display tab stop column (< col), using binary search for vartabstop.
---@param col integer  -- current 0-based visual column
---@param cfg table    -- { vts, ts, prefix, last_step }
---@return integer
function Tab.prev_display_tabstop(col, cfg)
    if col <= 0 then return 0 end

    local prefix = cfg.prefix
    local plen = #prefix
    if plen > 0 then
        -- before or at the first tab stop, the previous one is the origin (0)
        if col <= prefix[1] then
            return 0
        elseif col <= prefix[plen] then
            -- binary search for the rightmost prefix < col
            local lo, hi = 1, plen
            while lo < hi do
                -- upper mid to avoid infinite loop
                local mid = floor((lo + hi + 1) / 2)
                if prefix[mid] < col then
                    lo = mid
                else
                    hi = mid - 1
                end
            end
            return prefix[lo]
        else
            -- beyond last explicit stop: repeat the final width
            local cum  = prefix[plen]
            local step = cfg.last_step
            -- largest k such that cum + k*step < col
            local k    = floor((col - 1 - cum) / step)
            return cum + k * step
        end
    end

    -- simple fixed tabstop
    local ts = cfg.ts
    local m = col % ts
    if m == 0 then
        local prev = col - ts
        if prev < 0 then prev = 0 end
        return prev
    else
        return col - m
    end
end

local floor = math.floor

-- ---- shiftwidth(): effective value ----
function Tab.shiftwidth_effective(buffer)
    local sw = tonumber(options.get("shiftwidth", nil, buffer)) or 0
    local ts = tonumber(options.get("tabstop", nil, buffer)) or 8
    if ts <= 0 then ts = 8 end
    return (sw > 0) and sw or ts
end

-- ---- varsofttabstop/softtabstop config (cached) ----
local _soft_cache = { vsts_raw = nil, sts_raw = nil, sw_raw = nil, ts_raw = nil, cfg = nil }

local function parse_positive_list(raw)
    if not raw or raw == "" then return {} end
    local widths, items = {}, options.ParseCSL(raw)
    for i = 1, #items do
        local n = tonumber(items[i])
        if n and n > 0 then widths[#widths + 1] = n end
    end
    return widths
end

--- Returns active soft-tab config. varsofttabstop overrides softtabstop.
--- Handles negative 'softtabstop' as shiftwidth().
--- cfg = { vsts, prefix, last_step, numeric_sts }
function Tab.get_soft_config(buffer)
    local vsts_raw = options.get("varsofttabstop", nil, buffer) or ""
    local sts_raw  = options.get("softtabstop", nil, buffer) or 0
    local sw_raw   = options.get("shiftwidth", nil, buffer) or 0
    local ts_raw   = options.get("tabstop", nil, buffer) or 8

    if _soft_cache.vsts_raw == vsts_raw
        and _soft_cache.sts_raw == sts_raw
        and _soft_cache.sw_raw == sw_raw
        and _soft_cache.ts_raw == ts_raw
        and _soft_cache.cfg ~= nil
    then
        return _soft_cache.cfg
    end

    local vsts   = parse_positive_list(vsts_raw)
    local prefix = {}
    local last_step

    if #vsts > 0 then
        local acc = 0
        for i = 1, #vsts do
            acc = acc + vsts[i]
            prefix[i] = acc
        end
        last_step = vsts[#vsts]
    end

    local sts = tonumber(sts_raw) or 0
    if sts < 0 then
        sts = Tab.shiftwidth_effective(buffer)
    end

    local cfg                                 = {
        vsts        = vsts,
        prefix      = prefix,
        last_step   = last_step,
        numeric_sts = sts,
    }
    _soft_cache.vsts_raw, _soft_cache.sts_raw = vsts_raw, sts_raw
    _soft_cache.sw_raw, _soft_cache.ts_raw    = sw_raw, ts_raw
    _soft_cache.cfg                           = cfg
    return cfg
end

--- Next soft boundary (> vcol)
function Tab.next_soft_boundary(v, scfg)
    local prefix = scfg.prefix
    local plen = #prefix
    if plen > 0 then
        if v < prefix[plen] then
            local lo, hi = 1, plen
            while lo < hi do
                local mid = floor((lo + hi) / 2)
                if v < prefix[mid] then hi = mid else lo = mid + 1 end
            end
            return prefix[lo]
        else
            local cum  = prefix[plen]
            local step = scfg.last_step
            local k    = floor((v - cum) / step) + 1
            return cum + k * step
        end
    end
    local s = scfg.numeric_sts
    if s and s > 0 then
        local rem = s - (v % s)
        if rem == 0 then rem = s end
        return v + rem
    end
    return v
end

--- Previous soft boundary (< vcol)
function Tab.prev_soft_boundary(v, scfg)
    if v <= 0 then return 0 end
    local prefix = scfg.prefix
    local plen = #prefix
    if plen > 0 then
        if v <= prefix[1] then return 0 end
        if v <= prefix[plen] then
            local lo, hi = 1, plen
            while lo < hi do
                local mid = floor((lo + hi + 1) / 2)
                if prefix[mid] < v then lo = mid else hi = mid - 1 end
            end
            return prefix[lo]
        else
            local cum  = prefix[plen]
            local step = scfg.last_step
            local k    = floor((v - 1 - cum) / step)
            return cum + k * step
        end
    end
    local s = scfg.numeric_sts
    if s and s > 0 then
        local m = v % s
        if m == 0 then
            local prev = v - s
            if prev < 0 then prev = 0 end
            return prev
        else
            return v - m
        end
    end
    return v
end

function Tab.soft_distance_to_prev(v, scfg)
    local p = Tab.prev_soft_boundary(v, scfg)
    local d = v - p
    if d < 1 then d = 1 end
    return d
end

--- Visual column of s:sub(1, upto_col1-1), respecting vartabstop
function Tab.vcol_of_prefix(s, upto_col1, tcfg)
    local v, upto = 0, math.max(0, (upto_col1 or 1) - 1)
    for i = 1, upto do
        local ch = s:sub(i, i)
        if ch == "\t" then
            v = Tab.next_display_tabstop(v, tcfg)
        else
            v = v + 1
        end
    end
    return v
end

--- Compute a <Tab> insertion string at current vcol, honoring:
---   - expandtab
---   - varsofttabstop/softtabstop (sts<0 -> shiftwidth())
---   - smarttab: in leading whitespace, behave as if sts == shiftwidth()
---   - vartabstop/tabstop for hard tab placement
---@param current_v integer  -- 0-based visual column
---@param in_leading_ws boolean
---@return string
function Tab.compute_tab_insertion(current_v, in_leading_ws, buffer)
    local tcfg      = Tab.get_tab_config(buffer)
    local scfg      = Tab.get_soft_config(buffer)
    local expandtab = options.get("expandtab", nil, buffer)
    local smarttab  = options.get("smarttab", nil, buffer)

    -- Effective soft stops at this position:
    local scfg_eff  = scfg
    if smarttab and in_leading_ws then
        -- emulate sts == shiftwidth() at BOL/indent (ignores varsofttabstop)
        scfg_eff = { vsts = {}, prefix = {}, last_step = nil, numeric_sts = Tab.shiftwidth_effective(buffer) }
    end

    local delta
    if (#scfg_eff.vsts > 0) or (scfg_eff.numeric_sts and scfg_eff.numeric_sts > 0) then
        local nxt = Tab.next_soft_boundary(current_v, scfg_eff)
        delta = nxt - current_v
    else
        local nxt = Tab.next_display_tabstop(current_v, tcfg)
        delta = nxt - current_v
    end
    if delta <= 0 then return "" end

    if expandtab then
        return string.rep(" ", delta)
    end

    -- noexpandtab: pack as many hard tabs as fit, pad with spaces
    local out = {}
    local v = current_v
    local rem = delta
    while rem > 0 do
        local hard_next = Tab.next_display_tabstop(v, tcfg)
        local gap = hard_next - v
        if gap <= rem then
            out[#out + 1] = "\t"
            v = hard_next
            rem = rem - gap
        else
            out[#out + 1] = string.rep(" ", rem)
            v = v + rem
            rem = 0
        end
    end
    return table.concat(out)
end

return Tab
