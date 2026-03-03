local lpeg = {}

local VERSION = "1.1.0"
local DEFAULT_MAX_STACK = 400

local unpack = table.unpack
local maxstack = DEFAULT_MAX_STACK

local Pattern = {}
Pattern.__index = Pattern
Pattern.__name = "pattern"

local function pack(...)
    return {
        n = select("#", ...),
        ...
    }
end

local function new_caps()
    return { n = 0 }
end

local function copy_caps(source, from_idx, to_idx)
    local out = { n = 0 }
    local from = from_idx or 1
    local to = to_idx or source.n
    if to < from then
        return out
    end
    for i = from, to do
        out.n = out.n + 1
        out[out.n] = source[i]
    end
    return out
end

local function append_packed(prefix, values)
    local out = copy_caps(prefix)
    for i = 1, values.n do
        out.n = out.n + 1
        out[out.n] = values[i]
    end
    return out
end

local function append_value(prefix, value)
    local out = copy_caps(prefix)
    out.n = out.n + 1
    out[out.n] = value
    return out
end

local function values_from(captures, start_idx)
    local out = { n = 0 }
    for i = start_idx, captures.n do
        out.n = out.n + 1
        out[out.n] = captures[i]
    end
    return out
end

local function insert_value_after_prefix(captures, prefix_len, value)
    local out = { n = 0 }
    for i = 1, prefix_len do
        out.n = out.n + 1
        out[out.n] = captures[i]
    end
    out.n = out.n + 1
    out[out.n] = value
    for i = prefix_len + 1, captures.n do
        out.n = out.n + 1
        out[out.n] = captures[i]
    end
    return out
end

local function copy_groups(source)
    local out = {}
    for name, entry in pairs(source) do
        out[name] = {
            vals = copy_caps(entry.vals),
            gen = entry.gen,
        }
    end
    return out
end

local function newpattern(kind, ...)
    return setmetatable({
        kind = kind,
        data = {...},
    }, Pattern)
end

local function ispattern(value)
    return getmetatable(value) == Pattern
end

local topattern

local function ensure_pattern(value, level)
    if ispattern(value) then
        return value
    end
    return topattern(value, level or 3)
end

local function grammar_start_rule(grammar)
    local first = grammar[1]
    if first ~= nil and type(first) == "string" then
        return first
    end
    if first ~= nil then
        return 1
    end
    return "1"
end

topattern = function(value, level)
    if ispattern(value) then
        return value
    end

    local value_type = type(value)
    if value_type == "string" then
        return newpattern("string", value)
    end

    if value_type == "number" then
        return newpattern("number", value)
    end

    if value_type == "boolean" then
        if value then
            return newpattern("epsilon")
        end
        return newpattern("fail")
    end

    if value_type == "function" then
        return newpattern("runtimefunc", value)
    end

    if value_type == "table" then
        local rules = {}
        local start = grammar_start_rule(value)

        for key, rule in pairs(value) do
            local is_named_start = key == 1 and type(rule) == "string"
            if not is_named_start then
                rules[key] = topattern(rule, (level or 2) + 1)
            end
        end

        return newpattern("grammar", rules, start)
    end

    error(("bad argument #1 to 'P' (lpeg-pattern expected, got %s)"):format(value_type), level or 2)
end

local function replacement_to_string(value)
    local value_type = type(value)
    if value_type == "string" then
        return value
    end
    if value_type == "number" then
        return tostring(value)
    end
    error(("invalid replacement value (a %s)"):format(value_type), 0)
end

local function subst_string(format, values, whole)
    local out = {}
    local i = 1
    local len = #format

    while i <= len do
        local ch = format:sub(i, i)
        if ch == "%" and i < len then
            local nxt = format:sub(i + 1, i + 1)
            if nxt == "%" then
                out[#out + 1] = "%"
            else
                local n = tonumber(nxt)
                if n then
                    local replacement
                    if n == 0 then
                        replacement = whole
                    else
                        if n < 1 or n > values.n then
                            error(("invalid capture index (%d)"):format(n), 0)
                        end
                        replacement = values[n]
                    end
                    out[#out + 1] = tostring(replacement)
                else
                    out[#out + 1] = nxt
                end
            end
            i = i + 2
        else
            out[#out + 1] = ch
            i = i + 1
        end
    end

    return table.concat(out)
end

local function ok_result(results, pos, captures, groups, gen, subst)
    results[#results + 1] = {
        pos = pos,
        caps = captures,
        groups = groups,
        gen = gen,
        subst = subst,
    }
end

local function stack_check(depth)
    if depth > maxstack then
        error("backtrack stack overflow", 0)
    end
end

local function make_context(args, grammar, subst_active)
    return {
        args = args,
        grammar = grammar,
        subst_active = subst_active,
    }
end

local function match_pattern(pattern, subject, pos, captures, groups, gen, context, depth)
    stack_check(depth)

    local length = #subject
    local kind = pattern.kind
    local data = pattern.data
    local track_subst = context.subst_active

    if pos < 1 or pos > length + 1 then
        return {}
    end

    if kind == "string" then
        local text = data[1]
        if subject:sub(pos, pos + #text - 1) == text then
            local subst = track_subst and text or ""
            return {
                {
                    pos = pos + #text,
                    caps = captures,
                    groups = groups,
                    gen = gen,
                    subst = subst,
                }
            }
        end
        return {}
    end

    if kind == "number" then
        local n = data[1]
        if n >= 0 then
            local target = pos + n
            if target <= length + 1 then
                local subst = track_subst and subject:sub(pos, target - 1) or ""
                return {
                    {
                        pos = target,
                        caps = captures,
                        groups = groups,
                        gen = gen,
                        subst = subst,
                    }
                }
            end
            return {}
        end

        local need = -n
        local left = length - pos + 1
        if left < need then
            return {
                {
                    pos = pos,
                    caps = captures,
                    groups = groups,
                    gen = gen,
                    subst = "",
                }
            }
        end
        return {}
    end

    if kind == "epsilon" then
        return {
            {
                pos = pos,
                caps = captures,
                groups = groups,
                gen = gen,
                subst = "",
            }
        }
    end

    if kind == "fail" then
        return {}
    end

    if kind == "set" then
        if pos > length then
            return {}
        end
        local set = data[1]
        local ch = subject:sub(pos, pos)
        if set:find(ch, 1, true) then
            local subst = track_subst and ch or ""
            return {
                {
                    pos = pos + 1,
                    caps = captures,
                    groups = groups,
                    gen = gen,
                    subst = subst,
                }
            }
        end
        return {}
    end

    if kind == "range" then
        if pos > length then
            return {}
        end
        local ch = subject:sub(pos, pos)
        local ranges = data[1]
        for i = 1, #ranges, 2 do
            local low = ranges[i]
            local high = ranges[i + 1]
            if ch >= low and ch <= high then
                local subst = track_subst and ch or ""
                return {
                    {
                        pos = pos + 1,
                        caps = captures,
                        groups = groups,
                        gen = gen,
                        subst = subst,
                    }
                }
            end
        end
        return {}
    end

    if kind == "seq" then
        local left = data[1]
        local right = data[2]
        local out = {}
        local left_results = match_pattern(left, subject, pos, captures, groups, gen, context, depth + 1)

        for i = 1, #left_results do
            local lres = left_results[i]
            local right_results = match_pattern(
                right,
                subject,
                lres.pos,
                lres.caps,
                lres.groups,
                lres.gen,
                context,
                depth + 1
            )
            for j = 1, #right_results do
                local rres = right_results[j]
                local subst
                if track_subst then
                    subst = lres.subst .. rres.subst
                else
                    subst = ""
                end
                ok_result(out, rres.pos, rres.caps, rres.groups, rres.gen, subst)
            end
        end

        return out
    end

    if kind == "choice" then
        local left = data[1]
        local right = data[2]
        local left_results = match_pattern(left, subject, pos, captures, groups, gen, context, depth + 1)
        if #left_results > 0 then
            return left_results
        end
        return match_pattern(right, subject, pos, captures, groups, gen, context, depth + 1)
    end

    if kind == "rep" then
        local inner = data[1]
        local min_count = data[2]
        local max_count = data[3]
        local count = 0
        local current_pos = pos
        local current_caps = captures
        local current_groups = groups
        local current_gen = gen
        local current_subst = ""

        while max_count == nil or count < max_count do
            local inner_results = match_pattern(
                inner,
                subject,
                current_pos,
                current_caps,
                current_groups,
                current_gen,
                context,
                depth + 1
            )

            local res = inner_results[1]
            if not res or res.pos == current_pos then
                break
            end

            current_pos = res.pos
            current_caps = res.caps
            current_groups = res.groups
            current_gen = res.gen
            if track_subst then
                current_subst = current_subst .. res.subst
            end
            count = count + 1
        end

        if count < min_count then
            return {}
        end

        return {
            {
                pos = current_pos,
                caps = current_caps,
                groups = current_groups,
                gen = current_gen,
                subst = current_subst,
            }
        }
    end

    if kind == "not" then
        local inner = data[1]
        local tried = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        if #tried == 0 then
            return {
                {
                    pos = pos,
                    caps = captures,
                    groups = groups,
                    gen = gen,
                    subst = "",
                }
            }
        end
        return {}
    end

    if kind == "and" then
        local inner = data[1]
        local tried = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        if #tried > 0 then
            return {
                {
                    pos = pos,
                    caps = captures,
                    groups = groups,
                    gen = gen,
                    subst = "",
                }
            }
        end
        return {}
    end

    if kind == "behind" then
        local inner = data[1]
        for start_pos = pos, 1, -1 do
            local tried = match_pattern(inner, subject, start_pos, captures, groups, gen, context, depth + 1)
            for i = 1, #tried do
                if tried[i].pos == pos then
                    return {
                        {
                            pos = pos,
                            caps = captures,
                            groups = groups,
                            gen = gen,
                            subst = "",
                        }
                    }
                end
            end
        end
        return {}
    end

    if kind == "var" then
        local key = data[1]
        local grammar = context.grammar
        local target = grammar and grammar[key]
        if not target then
            return {}
        end
        return match_pattern(target, subject, pos, captures, groups, gen, context, depth + 1)
    end

    if kind == "grammar" then
        local grammar = data[1]
        local start = data[2]
        local entry = grammar[start]
        if not entry then
            error("grammar has no initial rule", 0)
        end
        local grammar_context = make_context(context.args, grammar, context.subst_active)
        return match_pattern(entry, subject, pos, captures, groups, gen, grammar_context, depth + 1)
    end

    if kind == "runtimefunc" then
        local fn = data[1]
        local ret = pack(fn(subject, pos, unpack(context.args, 1, context.args.n)))
        if ret.n == 0 or ret[1] == nil or ret[1] == false then
            return {}
        end

        local next_pos
        if ret[1] == true then
            next_pos = pos
        elseif type(ret[1]) == "number" then
            next_pos = ret[1]
        else
            return {}
        end

        if next_pos < pos or next_pos > length + 1 then
            return {}
        end

        local subst = track_subst and subject:sub(pos, next_pos - 1) or ""
        return {
            {
                pos = next_pos,
                caps = captures,
                groups = groups,
                gen = gen,
                subst = subst,
            }
        }
    end

    if kind == "cap_simple" then
        local inner = data[1]
        local prefix_len = captures.n
        local out = {}

        local inner_results = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        for i = 1, #inner_results do
            local res = inner_results[i]
            local whole = subject:sub(pos, res.pos - 1)
            local next_caps = insert_value_after_prefix(res.caps, prefix_len, whole)
            local subst = track_subst and whole or ""
            ok_result(out, res.pos, next_caps, res.groups, res.gen, subst)
        end

        return out
    end

    if kind == "cap_const" then
        local values = data[1]
        local next_caps = append_packed(captures, values)
        local subst = ""
        if track_subst and values.n > 0 then
            subst = replacement_to_string(values[1])
        end
        return {
            {
                pos = pos,
                caps = next_caps,
                groups = groups,
                gen = gen,
                subst = subst,
            }
        }
    end

    if kind == "cap_group" then
        local inner = data[1]
        local name = data[2]
        local prefix_len = captures.n
        local out = {}

        local inner_results = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        for i = 1, #inner_results do
            local res = inner_results[i]
            local delta = values_from(res.caps, prefix_len + 1)
            local whole = subject:sub(pos, res.pos - 1)
            local grouped = delta
            if grouped.n == 0 then
                grouped = append_value(new_caps(), whole)
            end

            if name == nil then
                local next_caps = append_packed(copy_caps(res.caps, 1, prefix_len), grouped)
                local subst = track_subst and replacement_to_string(grouped[1]) or ""
                ok_result(out, res.pos, next_caps, res.groups, res.gen, subst)
            else
                local next_caps = copy_caps(res.caps, 1, prefix_len)
                local next_groups = copy_groups(res.groups)
                local next_gen = res.gen + 1
                next_groups[name] = {
                    vals = grouped,
                    gen = next_gen,
                }
                local subst = track_subst and whole or ""
                ok_result(out, res.pos, next_caps, next_groups, next_gen, subst)
            end
        end

        return out
    end

    if kind == "cap_position" then
        local next_caps = append_value(captures, pos)
        local subst = ""
        if track_subst then
            subst = replacement_to_string(pos)
        end
        return {
            {
                pos = pos,
                caps = next_caps,
                groups = groups,
                gen = gen,
                subst = subst,
            }
        }
    end

    if kind == "cap_arg" then
        local n = data[1]
        if n < 1 or n > context.args.n then
            error(("reference to absent extra argument #%d"):format(n), 0)
        end

        local value = context.args[n]
        local next_caps = append_value(captures, value)
        local subst = ""
        if track_subst then
            subst = replacement_to_string(value)
        end
        return {
            {
                pos = pos,
                caps = next_caps,
                groups = groups,
                gen = gen,
                subst = subst,
            }
        }
    end

    if kind == "cap_back" then
        local name = data[1]
        local entry = groups[name]
        if not entry then
            error(("back reference '%s' not found"):format(tostring(name)), 0)
        end

        local next_caps = append_packed(captures, entry.vals)
        local subst = ""
        if track_subst and entry.vals.n > 0 then
            subst = replacement_to_string(entry.vals[1])
        end
        return {
            {
                pos = pos,
                caps = next_caps,
                groups = groups,
                gen = gen,
                subst = subst,
            }
        }
    end

    if kind == "cap_fold" then
        local inner = data[1]
        local fn = data[2]
        local prefix_len = captures.n
        local out = {}

        local inner_results = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        for i = 1, #inner_results do
            local res = inner_results[i]
            local delta = values_from(res.caps, prefix_len + 1)
            if delta.n == 0 then
                error("no initial value for fold capture", 0)
            end

            local acc = delta[1]
            for j = 2, delta.n do
                acc = fn(acc, delta[j])
            end

            local next_caps = append_value(copy_caps(res.caps, 1, prefix_len), acc)
            local subst = ""
            if track_subst then
                subst = replacement_to_string(acc)
            end
            ok_result(out, res.pos, next_caps, res.groups, res.gen, subst)
        end

        return out
    end

    if kind == "cap_accum" then
        local inner = data[1]
        local fn = data[2]
        local prefix_len = captures.n
        local out = {}

        if prefix_len == 0 then
            error("no previous value for accumulator capture", 0)
        end

        local inner_results = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        for i = 1, #inner_results do
            local res = inner_results[i]
            local acc = res.caps[prefix_len]
            local delta = values_from(res.caps, prefix_len + 1)
            if delta.n == 0 then
                delta = append_value(new_caps(), subject:sub(pos, res.pos - 1))
            end

            local next_acc = fn(acc, unpack(delta, 1, delta.n))
            local next_caps = append_value(copy_caps(res.caps, 1, prefix_len - 1), next_acc)
            local subst = ""
            if track_subst then
                subst = replacement_to_string(next_acc)
            end
            ok_result(out, res.pos, next_caps, res.groups, res.gen, subst)
        end

        return out
    end

    if kind == "cap_div" then
        local inner = data[1]
        local replacement = data[2]
        local prefix_len = captures.n
        local out = {}

        local inner_results = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        for i = 1, #inner_results do
            local res = inner_results[i]
            local delta = values_from(res.caps, prefix_len + 1)
            local whole = subject:sub(pos, res.pos - 1)
            local replacement_type = type(replacement)
            local produced = new_caps()

            if replacement_type == "function" then
                local source_values = delta
                if source_values.n == 0 then
                    source_values = append_value(new_caps(), whole)
                end
                produced = pack(replacement(unpack(source_values, 1, source_values.n)))
            elseif replacement_type == "table" then
                local source_values = delta
                if source_values.n == 0 then
                    source_values = append_value(new_caps(), whole)
                end
                local found = replacement[source_values[1]]
                if found ~= nil then
                    produced = append_value(produced, found)
                end
            elseif replacement_type == "string" then
                produced = append_value(produced, subst_string(replacement, delta, whole))
            elseif replacement_type == "number" then
                local source_values = delta
                if source_values.n == 0 then
                    source_values = append_value(new_caps(), whole)
                end
                if replacement < 1 or replacement > source_values.n then
                    error(("no capture '%d'"):format(replacement), 0)
                end
                produced = append_value(produced, source_values[replacement])
            else
                error(("bad argument #2 to '/' (invalid replacement type %s)"):format(replacement_type), 0)
            end

            local next_caps = append_packed(copy_caps(res.caps, 1, prefix_len), produced)
            local subst
            if track_subst then
                if produced.n == 0 then
                    subst = whole
                else
                    subst = replacement_to_string(produced[1])
                end
            else
                subst = ""
            end

            ok_result(out, res.pos, next_caps, res.groups, res.gen, subst)
        end

        return out
    end

    if kind == "cap_table" then
        local inner = data[1]
        local prefix_len = captures.n
        local start_gen = gen
        local out = {}

        local inner_results = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        for i = 1, #inner_results do
            local res = inner_results[i]
            local delta = values_from(res.caps, prefix_len + 1)
            local tbl = {}
            for j = 1, delta.n do
                tbl[j] = delta[j]
            end

            for name, entry in pairs(res.groups) do
                if entry.gen > start_gen and entry.vals[1] ~= nil then
                    tbl[name] = entry.vals[1]
                end
            end

            local next_caps = append_value(copy_caps(res.caps, 1, prefix_len), tbl)
            local subst = ""
            if track_subst then
                subst = replacement_to_string(tbl)
            end
            ok_result(out, res.pos, next_caps, res.groups, res.gen, subst)
        end

        return out
    end

    if kind == "cap_subst" then
        local inner = data[1]
        local prefix_len = captures.n
        local out = {}
        local subst_context = make_context(context.args, context.grammar, true)

        local inner_results = match_pattern(inner, subject, pos, captures, groups, gen, subst_context, depth + 1)
        for i = 1, #inner_results do
            local res = inner_results[i]
            local text = res.subst
            local next_caps = append_value(copy_caps(res.caps, 1, prefix_len), text)
            local subst = track_subst and text or ""
            ok_result(out, res.pos, next_caps, res.groups, res.gen, subst)
        end

        return out
    end

    if kind == "cap_matchtime" then
        local inner = data[1]
        local fn = data[2]
        local prefix_len = captures.n
        local out = {}

        local inner_results = match_pattern(inner, subject, pos, captures, groups, gen, context, depth + 1)
        for i = 1, #inner_results do
            local res = inner_results[i]
            local delta = values_from(res.caps, prefix_len + 1)
            local returned = pack(fn(subject, res.pos, unpack(delta, 1, delta.n)))

            if returned.n > 0 and returned[1] ~= nil and returned[1] ~= false then
                local next_pos
                if returned[1] == true then
                    next_pos = res.pos
                elseif type(returned[1]) == "number" then
                    next_pos = returned[1]
                end

                if next_pos and next_pos >= pos and next_pos <= length + 1 then
                    local produced = new_caps()
                    for j = 2, returned.n do
                        produced.n = produced.n + 1
                        produced[produced.n] = returned[j]
                    end

                    local next_caps = append_packed(copy_caps(res.caps, 1, prefix_len), produced)
                    local subst
                    if track_subst then
                        if produced.n == 0 then
                            subst = subject:sub(pos, res.pos - 1)
                        else
                            subst = replacement_to_string(produced[1])
                        end
                    else
                        subst = ""
                    end

                    ok_result(out, next_pos, next_caps, res.groups, res.gen, subst)
                end
            end
        end

        return out
    end

    return {}
end

local function normalize_init(subject, init)
    if init == nil then
        return 1
    end

    local idx = init
    if idx < 0 then
        idx = #subject + 1 + idx
        if idx < 1 then
            idx = 1
        end
    end

    return idx
end

local function run_match(pattern, subject, init, args)
    local start_pos = normalize_init(subject, init)
    local context = make_context(args, nil, false)

    local results = match_pattern(pattern, subject, start_pos, new_caps(), {}, 0, context, 1)
    if #results == 0 then
        return nil
    end

    local best = results[1]
    if best.caps.n > 0 then
        return unpack(best.caps, 1, best.caps.n)
    end

    return best.pos
end

function lpeg.type(value)
    if ispattern(value) then
        return "pattern"
    end
    return nil
end

function lpeg.version()
    return VERSION
end

function lpeg.setmaxstack(max)
    maxstack = max
end

function lpeg.match(pattern, subject, init, ...)
    local compiled = topattern(pattern, 2)
    return run_match(compiled, subject, init, pack(...))
end

function Pattern:match(subject, init, ...)
    return run_match(self, subject, init, pack(...))
end

function lpeg.P(value)
    return topattern(value, 2)
end

function lpeg.R(...)
    local args = {...}
    if #args == 0 then
        return newpattern("fail")
    end

    local ranges = {}
    for i = 1, #args do
        local item = args[i]
        if type(item) ~= "string" or #item ~= 2 then
            error("bad argument to 'R' (range must be a 2-character string)", 2)
        end
        ranges[#ranges + 1] = item:sub(1, 1)
        ranges[#ranges + 1] = item:sub(2, 2)
    end

    return newpattern("range", ranges)
end

function lpeg.S(chars)
    if chars == "" then
        return newpattern("fail")
    end
    return newpattern("set", chars)
end

function lpeg.B(pattern)
    return newpattern("behind", ensure_pattern(pattern, 2))
end

function lpeg.V(value)
    if type(value) == "number" then
        return newpattern("var", value)
    end
    return newpattern("var", tostring(value))
end

function lpeg.C(pattern)
    return newpattern("cap_simple", ensure_pattern(pattern, 2))
end

function lpeg.Cc(...)
    return newpattern("cap_const", pack(...))
end

function lpeg.Cg(pattern, name)
    return newpattern("cap_group", ensure_pattern(pattern, 2), name)
end

function lpeg.Cp()
    return newpattern("cap_position")
end

function lpeg.Carg(n)
    return newpattern("cap_arg", n)
end

function lpeg.Cb(name)
    return newpattern("cap_back", name)
end

function lpeg.Cf(pattern, fn)
    return newpattern("cap_fold", ensure_pattern(pattern, 2), fn)
end

function lpeg.Cs(pattern)
    return newpattern("cap_subst", ensure_pattern(pattern, 2))
end

function lpeg.Ct(pattern)
    return newpattern("cap_table", ensure_pattern(pattern, 2))
end

function lpeg.Cmt(pattern, fn)
    return newpattern("cap_matchtime", ensure_pattern(pattern, 2), fn)
end

local function control_chars()
    local chars = {}
    for i = 0, 31 do
        chars[#chars + 1] = string.char(i)
    end
    chars[#chars + 1] = string.char(127)
    return table.concat(chars)
end

function lpeg.locale(tab)
    local out = tab or {}

    out.lower = out.lower or lpeg.R("az")
    out.upper = out.upper or lpeg.R("AZ")
    out.alpha = out.alpha or (out.lower + out.upper)
    out.digit = out.digit or lpeg.R("09")
    out.alnum = out.alnum or (out.alpha + out.digit)
    out.cntrl = out.cntrl or lpeg.S(control_chars())
    out.graph = out.graph or lpeg.R("!~")
    out.print = out.print or lpeg.R(" ~")
    out.punct = out.punct or lpeg.S("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")
    out.space = out.space or lpeg.S(" \t\n\v\f\r")
    out.xdigit = out.xdigit or lpeg.R("09", "af", "AF")

    out.a = out.alpha
    out.c = out.cntrl
    out.d = out.digit
    out.g = out.graph
    out.l = out.lower
    out.p = out.punct
    out.s = out.space
    out.u = out.upper
    out.w = out.alnum
    out.x = out.xdigit

    return out
end

function Pattern.__add(a, b)
    return newpattern("choice", a, ensure_pattern(b, 2))
end

function Pattern.__sub(a, b)
    return newpattern("seq", newpattern("not", ensure_pattern(b, 2)), a)
end

function Pattern.__mul(a, b)
    return newpattern("seq", a, ensure_pattern(b, 2))
end

function Pattern.__pow(a, n)
    if type(n) ~= "number" or n % 1 ~= 0 then
        error("bad argument #2 to 'pow' (number has no integer representation)", 2)
    end

    if n >= 0 then
        return newpattern("rep", a, n, nil)
    end

    return newpattern("rep", a, 0, -n)
end

function Pattern.__unm(a)
    return newpattern("not", a)
end

function Pattern.__len(a)
    return newpattern("and", a)
end

function Pattern.__div(a, b)
    return newpattern("cap_div", a, b)
end

function Pattern.__mod(a, b)
    if type(b) ~= "function" then
        error("bad argument #2 to '%' (function expected)", 2)
    end
    return newpattern("cap_accum", a, b)
end

return lpeg
