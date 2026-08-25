local LuaLoader = {}

local ApiBuild = loadModule("lib.luaapi.apibuild")
local vimapi = ApiBuild.Build()
setmetatable(vimapi, { __index = _G })
vimapi._G = vimapi
local Error = loadModule("lib.error")
local ScriptSource = loadModule("lib.scriptsource")

local loaded = {}

local function compile_with_env(code, chunkname, env)
    return load(code, chunkname or "=(chunk)", "t", env)
end

function LuaLoader.LoadFile(path, ...)
    local plugin
    if loaded[path] then
        plugin = loaded[path]
    else
        if not fs.exists(path) then
            error(Error(5112, "cannot open " .. path .. ": No such file or directory"), 0)
        end
        local chunk, err = loadfile(path, "t", vimapi)
        if not chunk then
            LOG_ERROR("CHUNK ERROR: " .. err)
            error(Error(5112, err), 0)
        end
        ScriptSource.PushContext(path)
        local ok
        ok, plugin = pcall(chunk, ...)
        ScriptSource.PopContext()
        if not ok then
            error(Error(5113, tostring(plugin)), 0)
        end
        loaded[path] = plugin
    end

    return plugin
end

function LuaLoader.Eval(src)
    local chunk, err = compile_with_env(src, "=[string \":lua\"]", vimapi)
    if not chunk then
        LOG_ERROR("Error in Lua: " .. err)
        return false, Error(5107, err)
    end
    local ok, rv = pcall(chunk)
    if not ok then
        return false, Error(5108, tostring(rv))
    end
    return true, rv
end

LuaLoader._vimapi_debug = vimapi

return LuaLoader
