local tbl = {}

function tbl.sorted_keys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

function tbl.deepcopy(orig, noref)
    local function copy(obj, cache, stack)
        local t = type(obj)
        if t == "table" then
            if noref then
                if stack[obj] then
                    error("Cannot deepcopy object of type table (cyclic reference)")
                end
                stack[obj] = true
                local out = {}
                for k, v in next, obj do
                    out[copy(k, cache, stack)] = copy(v, cache, stack)
                end
                stack[obj] = nil
                return setmetatable(out, getmetatable(obj))
            end

            local cached = cache[obj]
            if cached ~= nil then
                return cached
            end
            local out = {}
            cache[obj] = out
            for k, v in next, obj do
                out[copy(k, cache, stack)] = copy(v, cache, stack)
            end
            return setmetatable(out, getmetatable(obj))
        end

        if t == "userdata" or t == "thread" then
            error("Cannot deepcopy object of type " .. t)
        end
        return obj
    end

    return copy(orig, {}, {})
end

return tbl
