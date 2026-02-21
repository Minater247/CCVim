local M = {}

local print = loadModule("lib.luaapi.print")
local VimFs = loadModule("lib.luaapi.fs")

local function normalize_abs(path)
    return VimFs.abspath(path or "")
end

-- Return a table of loaders bound to `env`. If the caller passes a different
-- env later, we honor that, but default to the bound one.
function M.Bind(env)
    assert(type(env) == "table", "fileload.Bind: env table required")
    -- Ensure code compiled for this env sees itself as _G.
    if env._G ~= env then env._G = env end

    local function loadfile_bound(path, mode, override_env)
        return loadfile(normalize_abs(path), mode or "t", override_env or env)
    end

    local function load_bound(chunk, chunkname, mode, override_env)
        return load(chunk, chunkname or "=(chunk)", mode or "t", override_env or env)
    end

    local function dofile_bound(path)
        local f, err = loadfile_bound(path)
        if not f then error(err, 2) end
        return f()
    end

    -- Wrapped pcall that logs errors (if LOG_DEBUG) and returns the usual pcall tuple.
    -- We use the bound env's print.inspect (if present) for serialization.
    local function pcall_bound(fn, ...)
        local results = { pcall(fn, ...) } -- { ok, ... }
        local ok = results[1]
        if not ok then
            LOG_INTERNAL("pcall", function() return "error: " .. print.inspect(results[2]) end)
            -- _log_caller("pcall_bound")
        end
        return table.unpack(results, 1, #results)
    end

    return {
        loadfile = loadfile_bound,
        load     = load_bound,
        dofile   = dofile_bound,
    pcall    = pcall_bound,
    }
end

return M
