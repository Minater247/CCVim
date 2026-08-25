local fakeuserdata = {}

local registry = setmetatable({}, { __mode = "k" })
local next_id = 0

local function real_type(value)
    return _G.type(value)
end

local function real_next(tbl, key)
    return _G.next(tbl, key)
end

local function real_pairs(tbl)
    return _G.pairs(tbl)
end

local function real_ipairs(tbl)
    return _G.ipairs(tbl)
end

local function real_rawget(tbl, key)
    return _G.rawget(tbl, key)
end

local function real_rawset(tbl, key, value)
    return _G.rawset(tbl, key, value)
end

local function real_setmetatable(tbl, mt)
    return _G.setmetatable(tbl, mt)
end

local function type_error(name, index)
    error(("bad argument #%d to '%s' (table expected, got userdata)"):format(index, name), 3)
end

function fakeuserdata.is(value)
    return real_type(value) == "table" and registry[value] ~= nil
end

function fakeuserdata.type(value)
    if fakeuserdata.is(value) then
        return "userdata"
    end
    return real_type(value)
end

function fakeuserdata.state(value)
    local entry = registry[value]
    return entry and entry.state or nil
end

function fakeuserdata.new(tag, state, methods)
    next_id = next_id + 1

    local mt = {
        __name = tag,
        __index = methods or {},
        __tostring = function(self)
            local entry = registry[self]
            return string.format("%s: 0x%08x", tag, entry and entry.id or 0)
        end,
    }

    local obj = {}
    registry[obj] = {
        id = next_id,
        tag = tag,
        state = state or {},
        metatable = mt,
    }
    return real_setmetatable(obj, mt)
end

function fakeuserdata.next(tbl, key)
    if fakeuserdata.is(tbl) then
        type_error("next", 1)
    end
    return real_next(tbl, key)
end

function fakeuserdata.pairs(tbl)
    if fakeuserdata.is(tbl) then
        type_error("pairs", 1)
    end
    return real_pairs(tbl)
end

function fakeuserdata.ipairs(tbl)
    if fakeuserdata.is(tbl) then
        type_error("ipairs", 1)
    end
    return real_ipairs(tbl)
end

function fakeuserdata.rawget(tbl, key)
    if fakeuserdata.is(tbl) then
        type_error("rawget", 1)
    end
    return real_rawget(tbl, key)
end

function fakeuserdata.rawset(tbl, key, value)
    if fakeuserdata.is(tbl) then
        type_error("rawset", 1)
    end
    return real_rawset(tbl, key, value)
end

function fakeuserdata.setmetatable(tbl, mt)
    if fakeuserdata.is(tbl) then
        type_error("setmetatable", 1)
    end
    return real_setmetatable(tbl, mt)
end

return fakeuserdata
