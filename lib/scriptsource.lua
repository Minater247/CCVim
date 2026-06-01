local ScriptSource = {}

local LuaLoader = loadModule("lib.lualoader")
local Runtime = loadModule("lib.excmd.runtime")
local Compiler = loadModule("lib.excmd.compiler")
local Error = loadModule("lib.error")
local Filesystem = loadModule("lib.filesystem")
local RuntimePath = loadModule("lib.runtimepath")
local VimFs = loadModule("lib.luaapi.fs")

local function ensure_abs(path)
    return VimFs.abspath(path)
end

local function resolve_runtime_path(path)
    local rtp = RuntimePath.get_search_list()
    for _, base in ipairs(rtp) do
        local candidate = base .. "/" .. path
        if fs.exists(candidate) then
            return candidate
        end
    end
    return rtp[1] .. "/" .. path
end

-- Execution stack for the current sourced script running.
ScriptSource.context_stack = {}

-- Push a script context (absolute path or context table) onto the stack
function ScriptSource.PushContext(ctx)
    ScriptSource.context_stack[#ScriptSource.context_stack + 1] = ctx
end

-- Pop the current script context
function ScriptSource.PopContext()
    if #ScriptSource.context_stack > 0 then
        ScriptSource.context_stack[#ScriptSource.context_stack] = nil
    end
end

-- Get the current script context (top of stack)
function ScriptSource.CurrentContext()
    return ScriptSource.context_stack[#ScriptSource.context_stack]
end

-- Wrap a callback so it runs under a specific script context.
-- scriptabsolutepath may be nil to capture the current context at wrap-time.
-- Returns a wrapper that restores the previous context even if the callback errors.
function ScriptSource.wrap(scriptabsolutepath, cb)
    if type(cb) ~= "function" then error("ScriptSource.wrap: cb must be a function", 2) end
    local captured = scriptabsolutepath
    if captured == nil then
        captured = ScriptSource.CurrentContext()
    end
    return function(...)
        ScriptSource.PushContext(captured)
        local results = { pcall(cb, ...) }
        ScriptSource.PopContext()
        if not results[1] then error(results[2], 0) end
        return table.unpack(results, 2)
    end
end

local function read_file(path)
    local f = fs.open(path, "r")
    if not f then
        return nil, Error(484, path)
    end
    local data = f.readAll()
    f.close()
    return data
end

local function write_file(path, data)
    local f = fs.open(path, "w")
    if not f then
        return false, Error(484, path)
    end
    f.write(data)
    f.close()
    return true
end

local function file_modified(path)
    local attrs = fs.attributes(path)
    if type(attrs) ~= "table" then
        return nil
    end
    local modified = attrs.modified
    if type(modified) ~= "number" then
        modified = attrs.modification
    end
    return modified
end

local function compiled_cache_path(path)
    if path:sub(-4) ~= ".vim" then
        return nil
    end
    return path:sub(1, -5) .. ".ccvim"
end

local function compiled_cache_is_fresh(source_path, cache_path)
    if not fs.exists(cache_path) then
        return false
    end
    local source_mtime = file_modified(source_path)
    local cache_mtime = file_modified(cache_path)
    if type(source_mtime) ~= "number" or type(cache_mtime) ~= "number" then
        return false
    end
    return cache_mtime >= source_mtime
end

local function run_vimscript_compiled(source_path, compiled_code, chunkname)
    local ok, rv, phase = Runtime.run_compiled(compiled_code, {
        script_ctx = source_path,
        origin = {
            kind = "sourced-file",
            source = source_path,
        },
        chunkname = chunkname,
    })
    if not ok then
        local msg = Error.IsError(rv) and rv:toString() or tostring(rv)
        LOG_DEBUG("Error executing '%s': %s", source_path, msg)
        return false, rv, phase
    end
    return true, nil, phase
end

local function run_vimscript_path(path)
    local cache_path = compiled_cache_path(path)
    local compiled_code
    if cache_path and not no_cache and compiled_cache_is_fresh(path, cache_path) then
        compiled_code = read_file(cache_path)
    end

    if compiled_code then
        local ok, err, phase = run_vimscript_compiled(path, compiled_code, "@" .. cache_path)
        if ok then
            return true
        end
        if phase ~= "load" then
            return false, err
        end
    end

    local script, read_err = read_file(path)
    if not script then
        LOG_DEBUG("Error executing '%s': %s", path, read_err:toString())
        return false, read_err
    end

    compiled_code, read_err = Compiler.compile_script(script)
    if not compiled_code then
        LOG_DEBUG("Error compiling '%s': %s", path, tostring(read_err))
        return false, read_err
    end

    if cache_path then
        local write_ok, write_err = write_file(cache_path, compiled_code)
        if not write_ok then
            LOG_DEBUG("Error writing cache '%s': %s", cache_path, tostring(write_err))
        end
    end

    return run_vimscript_compiled(path, compiled_code, "@" .. cache_path)
end

local function run_resolved_path(resolvedpath)
    if resolvedpath:sub(-4) == ".lua" then
        local ok, err = pcall(LuaLoader.LoadFile, resolvedpath)
        if not ok then
            local e = Error.IsError(err) and err or Error(5107, tostring(err))
            local msg = e:toString()
            LOG_DEBUG("Error executing '%s': %s", resolvedpath, msg)
            return false, e
        end
        return true
    end

    if resolvedpath:sub(-4) ~= ".vim" then
        return true
    end

    ScriptSource.PushContext(resolvedpath)
    local ok, rv = run_vimscript_path(resolvedpath)
    ScriptSource.PopContext()
    return ok, rv
end

function ScriptSource.source_runtime(path)
    -- Also accept a table of strings
    if type(path) == "table" then
        for _, v in ipairs(path) do
            local ok, err = ScriptSource.source_runtime(v)
            if ok == false then
                return false, err
            end
        end
        return true
    end

    local pre = os.epoch("utc")
    local resolvedpath
    if type(path) == "string" and path:sub(1, 1) == "/" then
        resolvedpath = path
    else
        resolvedpath = resolve_runtime_path(path)
    end
    resolvedpath = ensure_abs(resolvedpath)

    if not fs.exists(resolvedpath) then
        local err = Error(484, resolvedpath)
        LOG_DEBUG("Error executing '%s': %s", resolvedpath, err:toString())
        return false, err
    end

    local ok, err = run_resolved_path(resolvedpath)
    if not ok then
        return false, err
    end

    if startuptime then
        writestartup("sourcing " .. resolvedpath, pre)
    end
    return true
end

function ScriptSource.source(path)
    local pre = os.epoch("utc")

    local internalpath = Filesystem.Expand(path)
    if Error.IsError(internalpath) then
        return false, internalpath
    end

    -- Also accept a table of strings
    if type(internalpath) == "table" then
        for _, v in ipairs(internalpath) do
            local ok, err = ScriptSource.source(v)
            if ok == false then
                return false, err
            end
        end
        return true
    end

    local resolvedpath = VimFs.abspath(internalpath)

    if not fs.exists(resolvedpath) then
        return false, Error(484, resolvedpath)
    end

    local ok, err = run_resolved_path(resolvedpath)
    if not ok then
        return false, err
    end

    if startuptime then
        writestartup("sourcing " .. resolvedpath, pre)
    end

    return true
end


return ScriptSource
