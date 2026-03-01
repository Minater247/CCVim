-- vim.lib.envvars - unified environment variable backend.
-- Default behavior is a simulated in-process environment with sensible defaults.
-- Callers can install a provider to bridge to a host/OS environment.

local M = {}

local defaults = {}
local overrides = {}
local deleted = {}
local provider = nil

local function has_key(tbl, key)
    return rawget(tbl, key) ~= nil
end

local function normalize_name(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name
end

local function normalize_value(value)
    if value == nil then return nil end
    if type(value) == "boolean" then
        return value and "1" or ""
    end
    return tostring(value)
end

local function infer_home()
    local d = tostring(shell.dir() or "")
    if d == "" then
        return "/"
    end
    if d:sub(1, 1) ~= "/" then
        d = "/" .. d
    end
    return d
end

local function init_defaults()
    defaults.HOME = infer_home()
    defaults.PWD = defaults.HOME
    defaults.VIM = ccvim_path
    defaults.VIMRUNTIME = ccvim_path .. "/runtime"
    defaults.MYVIMRC = ccvim_path .. "/config/init.lua"
end

local function provider_getter()
    if type(provider) == "function" then
        return provider
    end
    if type(provider) == "table" then
        if type(provider.get) == "function" then
            return provider.get
        end
        if type(provider.getenv) == "function" then
            return provider.getenv
        end
    end
    return nil
end

local function provider_exists_fn()
    if type(provider) == "table" and type(provider.exists) == "function" then
        return provider.exists
    end
    return nil
end

local function provider_setter()
    if type(provider) == "table" and type(provider.set) == "function" then
        return provider.set
    end
    return nil
end

local function provider_unsetter()
    if type(provider) == "table" and type(provider.unset) == "function" then
        return provider.unset
    end
    return nil
end

local function provider_get(name)
    local getter = provider_getter()
    if type(getter) ~= "function" then
        return nil, false
    end
    return getter(name), true
end

-- Install provider callbacks for host integration.
-- Provider forms:
--   function(name) -> value|nil
--   { get=fn, exists=fn, set=fn, unset=fn }
function M.set_provider(p)
    provider = p
end

function M.get_provider()
    return provider
end

function M.use_os_provider()
    M.set_provider({
        get = function(name)
            return os.getenv(name)
        end,
        exists = function(name)
            return os.getenv(name) ~= nil
        end
    })
end

function M.get(name)
    local key = normalize_name(name)
    if not key then return end

    if has_key(overrides, key) then
        return normalize_value(overrides[key])
    end
    if deleted[key] then
        return
    end

    local pval, got = provider_get(key)
    if got and pval ~= nil then
        return normalize_value(pval)
    end

    local dval = defaults[key]
    if dval == nil then
        return
    end
    return normalize_value(dval)
end

function M.exists(name)
    local key = normalize_name(name)
    if not key then return false end

    if has_key(overrides, key) then
        return true
    end
    if deleted[key] then
        return false
    end

    local exists_fn = provider_exists_fn()
    if type(exists_fn) == "function" then
        return not not exists_fn(key)
    else
        local pval, got = provider_get(key)
        if got then
            return pval ~= nil
        end
    end

    return has_key(defaults, key)
end

function M.set(name, value)
    local key = normalize_name(name)
    if not key then return false end
    if value == nil then
        return M.unset(key)
    end

    deleted[key] = nil
    overrides[key] = normalize_value(value) or ""

    local setter = provider_setter()
    if type(setter) == "function" then
        setter(key, overrides[key])
    end
    return true
end

function M.unset(name)
    local key = normalize_name(name)
    if not key then return false end

    overrides[key] = nil
    deleted[key] = true

    local unsetter = provider_unsetter()
    if type(unsetter) == "function" then
        unsetter(key)
    end
    return true
end

function M.set_default(name, value)
    local key = normalize_name(name)
    if not key then return false end
    if value == nil then
        defaults[key] = nil
        return true
    end
    defaults[key] = normalize_value(value) or ""
    return true
end

function M.get_default(name)
    local key = normalize_name(name)
    if not key then return nil end
    return defaults[key]
end

function M.snapshot()
    local out = {}

    for k, v in pairs(defaults) do
        if not deleted[k] then
            out[k] = normalize_value(v) or ""
        end
    end

    for k, v in pairs(overrides) do
        out[k] = normalize_value(v) or ""
    end

    return out
end

init_defaults()

return M
