local LuaLoader = {}

local vimapi = loadModule("lib.luaapi.apibuild").Build()
setmetatable(vimapi, { __index = _G })
local Error = loadModule("lib.error")
local VimFs = loadModule("lib.luaapi.fs")
local ScriptSource

local loaded = {}

local function compile_with_env(code, chunkname, env)
    return load(code, chunkname or "=(chunk)", "t", env)
end

function LuaLoader.LoadFile(path)
    path = VimFs.abspath(path)

    local plugin
    if loaded[path] then
        plugin = loaded[path]
    else
        if not fs.exists(path) then
            error("LoadFile(): " .. path .. ": not found")
        end
        local chunk, err = loadfile(path, "t", vimapi)
        if not chunk then
            LOG_ERROR("CHUNK ERROR: " .. err)
            return error(err, 0)
        end
        ScriptSource = ScriptSource or loadModule("lib.scriptsource")
        ScriptSource.PushContext(path)
        plugin = chunk()
        ScriptSource.PopContext()
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
        if Error.IsError(rv) then
            rv = rv:toString()
        end
        return false, Error(5108, rv)
    end
    return true, rv
end

LuaLoader._vimapi_debug = vimapi

return LuaLoader
