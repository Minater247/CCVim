local on_key = {}

local callbacks = {} --- @type table<integer, [function, table]>
local dispatching = false
local ns_fallback_next = 1000000000
local namespace_allocator = nil

local function is_callable(v)
    if type(v) == "function" then
        return true
    end
    local mt = getmetatable(v)
    return mt ~= nil and type(mt.__call) == "function"
end

local function validate(name, value, expected, optional)
    if value == nil and optional then
        return
    end
    local ok
    if expected == "callable" then
        ok = is_callable(value)
    else
        ok = type(value) == expected
    end
    if not ok then
        error(("%s: expected %s, got %s"):format(name, expected, type(value)), 3)
    end
end

local function count_callbacks()
    local n = 0
    for _ in pairs(callbacks) do
        n = n + 1
    end
    return n
end

--- Allows host modules to share namespace allocation with nvim_create_namespace().
--- @param fn nil|fun(name: string): integer
function on_key.set_namespace_allocator(fn)
    validate("fn", fn, "callable", true)
    namespace_allocator = fn
end

--- Registers or removes vim.on_key callbacks.
--- @param fn nil|function
--- @param ns_id nil|integer
--- @param opts nil|table
--- @return integer
function on_key.on_key(fn, ns_id, opts)
    if fn == nil and ns_id == nil then
        return count_callbacks()
    end

    validate("fn", fn, "callable", true)
    validate("ns_id", ns_id, "number", true)
    validate("opts", opts, "table", true)

    opts = opts or {}
    if ns_id == nil or ns_id == 0 then
        if namespace_allocator then
            ns_id = namespace_allocator("")
        else
            ns_id = ns_fallback_next
            ns_fallback_next = ns_fallback_next + 1
        end
    end

    callbacks[ns_id] = fn and { fn, opts }
    return ns_id
end

local function dispatch_impl(key, typed, raise_errors)
    if dispatching then
        return false
    end

    dispatching = true

    local failed = {} --- @type [integer, string][]
    local discard = false
    for k, v in pairs(callbacks) do
        local fn = v[1]
        local ok, rv = xpcall(function()
            return fn(key, typed)
        end, debug.traceback)

        if ok and rv ~= nil then
            if type(rv) == "string" and #rv == 0 then
                discard = true
            else
                ok = false
                rv = "return string must be empty"
            end
        end

        if not ok then
            callbacks[k] = nil
            failed[#failed + 1] = { k, rv }
        end
    end

    dispatching = false

    if #failed > 0 then
        local errmsg = ""
        for i = 1, #failed do
            local item = failed[i]
            errmsg = errmsg .. string.format("\nWith ns_id %d: %s", item[1], item[2])
        end
        if raise_errors ~= false then
            error(errmsg, 3)
        end
        return discard, errmsg
    end

    return discard
end

--- Executes vim.on_key callbacks.
--- Returns true when a callback consumed the key by returning an empty string.
--- @param key string
--- @param typed string
--- @return boolean
function on_key.dispatch(key, typed)
    return dispatch_impl(key, typed, true)
end

--- Executes vim.on_key callbacks without raising callback failures.
--- Still removes invalid/erroring callbacks and reports whether the key was consumed.
--- @param key string
--- @param typed string
--- @return boolean
--- @return string|nil
function on_key.dispatch_safely(key, typed)
    return dispatch_impl(key, typed, false)
end

return on_key
