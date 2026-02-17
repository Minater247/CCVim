local tbl = {}

local function _resolve(behavior, k, a, b)
    if type(behavior) == "function" then
        return behavior(k, a, b)
    elseif behavior == "error" then
        error("key found in more than one map: " .. tostring(k))
    elseif behavior == "keep" then
        return a
    elseif behavior == "force" then
        return b
    end
end

local function _check_behavior(behavior)
    if behavior ~= "error" and behavior ~= "keep" and behavior ~= "force" and type(behavior) ~= "function" then
        error("invalid \"behavior\": " .. tostring(behavior))
    end
end

function tbl.extend(behavior, ...)
    _check_behavior(behavior)
    local n = select("#", ...)
    if n < 2 then error("wrong number of arguments (given " .. (n + 1) .. ", expected at least 3)") end

    local merged = {}
    for i = 1, n do
        local t = select(i, ...)
        for k, v in pairs(t) do
            if merged[k] ~= nil then
                merged[k] = _resolve(behavior, k, merged[k], v)
            else
                merged[k] = v
            end
        end
    end
    return merged
end

local function _isempty(t) return next(t) == nil end

function tbl.isempty(t)
    return _isempty(t)
end

-- Lua-list per :help lua-table-ambiguous (1..N consecutive integer keys).
local function _is_list(t)
    if type(t) ~= "table" then return false end
    -- Empty table is a list in general (:help lua-table-ambiguous), but
    -- tbl_deep_extend treats empty tables as recursively mergeable.
    local maxk = 0
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false
        end
        if k > maxk then maxk = k end
        count = count + 1
    end
    -- list iff no holes: exactly 1..maxk
    return count == maxk
end

local function _shallow_copy(t)
    local r = {}
    for k, v in pairs(t) do r[k] = v end
    return r
end

local function _deep_merge_two(behavior, a, b)
    -- start from a copy of 'a'
    local out = _shallow_copy(a)
    for k, v in pairs(b) do
        local prev = out[k]
        if type(prev) == "table" and type(v) == "table" then
            local prev_is_list = _is_list(prev)
            local v_is_list    = _is_list(v)
            -- Recurse if not both lists, or if either table is empty (special-case)
            if _isempty(prev) or _isempty(v) or not (prev_is_list and v_is_list) then
                out[k] = _deep_merge_two(behavior, prev, v)
            else
                -- both are lists: resolve by behavior (overwrite/keep/error/custom)
                out[k] = _resolve(behavior, k, prev, v)
            end
        elseif prev ~= nil then
            out[k] = _resolve(behavior, k, prev, v)
        else
            out[k] = v
        end
    end
    return out
end

function tbl.deep_extend(behavior, ...)
    _check_behavior(behavior)
    local n = select("#", ...)
    if n < 2 then error("wrong number of arguments (given " .. (n + 1) .. ", expected at least 3)") end

    local acc = {}
    for i = 1, n do
        local t = select(i, ...)
        if type(t) ~= "table" then error("after the second argument: expected table, got " .. type(t)) end
        acc = _deep_merge_two(behavior, acc, t)
    end
    return acc
end

function tbl.contains(t, value, opts)
    opts = opts or {}

    if opts.predicate then
        for k, v in pairs(t) do
            if value(v, k) then
                return true
            end
        end
        return false
    else
        for _, v in pairs(t) do
            if v == value then
                return true
            end
        end
        return false
    end
end

function tbl.filter(func, t)
    local out = {}
    for k, v in pairs(t) do
        if func(v, k) then
            out[#out + 1] = v
        end
    end
    return out
end

function tbl.deepcopy(orig, noref)
    local function copy(obj, cache, stack)
        local t = type(obj)
        if t == 'table' then
            if noref then
                if stack[obj] then error('Cannot deepcopy object of type table (cyclic reference)') end
                stack[obj] = true
                local out = {}
                for k, v in next, obj do
                    out[copy(k, cache, stack)] = copy(v, cache, stack)
                end
                stack[obj] = nil
                return setmetatable(out, getmetatable(obj))
            else
                local c = cache[obj]
                if c ~= nil then return c end
                local out = {}
                cache[obj] = out
                for k, v in next, obj do
                    out[copy(k, cache, stack)] = copy(v, cache, stack)
                end
                return setmetatable(out, getmetatable(obj))
            end
        elseif t == 'userdata' or t == 'thread' then
            error('Cannot deepcopy object of type ' .. t)
        else
            return obj
        end
    end
    return copy(orig, {}, {})
end

function tbl.map(func, t)
    for k, v in pairs(t) do
        t[k] = func(v)
    end
    return t
end

return tbl
