--[[
    Tables which may alias elements to one another using the metatable.
]]

local AliasTable = {}
AliasTable.__index = AliasTable

function AliasTable:new()
    local store = {} -- concrete key -> value
    local link = {}

    local function resolve(k)
        local seen = {}
        while link[k] ~= nil do
            if seen[k] then
                error(("alias cycle detected at key %s"):format(tostring(k)))
            end
            seen[k] = true
            k = link[k]
        end
        return k
    end

    local methods = {}

    function methods:hasKey(key)
        return (store[key] or link[key]) and true or false
    end

    function methods:hasConcreteKey(key)
        return store[key] and true or false
    end

    function methods:hasLinkKey(key)
        return link[key] and true or false
    end

    function methods:getLink(key)
        return link[key]
    end

    function methods:clear(key)
        store[key] = nil
        link[key] = nil
    end

    function methods:link(alias, target)
        store[alias] = nil
        link[alias] = target
    end

    function methods:unlink(alias)
        link[alias] = nil
    end

    function methods:iter()
        local phase, k = "store", nil
        return function()
            if phase == "store" then
                k = next(store, k)
                if k ~= nil then
                    return k, store[k]
                end
                phase, k = "alias", nil
            end
            k = next(link, k)
            if k ~= nil then
                return k, link[k]
            end
        end
    end

    local mt = {}

    function mt.__index(_, k)
        if k == "_" then
            return methods
        end
        return rawget(store, resolve(k))
    end

    function mt.__pairs(self)
        local iter = methods.iter(self)
        return iter, nil, nil
    end

    function mt.__newindex(_, k, v)
        if k == "_" then
            error("`_` is reserved within an AliasTable!")
        end

        if v == nil then
            store[k] = nil
            if link[k] ~= nil then link[k] = nil end
            return
        end
        if link[k] ~= nil then
            link[k] = nil
        end
        store[k] = v
    end

    return setmetatable({}, mt)
end

setmetatable(AliasTable, {
    __call = function(self, ...)
        return self:new(...)
    end,
})

return AliasTable