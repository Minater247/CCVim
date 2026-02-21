local ScriptSource = {}

local LuaLoader = loadModule("lib.lualoader")
local Runtime = loadModule("lib.excmd.runtime")
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

    if resolvedpath:sub(-4) == ".lua" then
        local ok, err = pcall(LuaLoader.LoadFile, resolvedpath)
        if not ok then
            local e = Error.IsError(err) and err or Error(5107, tostring(err))
            local msg = e:toString()
            LOG_DEBUG("Error executing '%s': %s", resolvedpath, msg)
            return false, e
        end
    elseif resolvedpath:sub(-4) == ".vim" then
        local f = fs.open(resolvedpath, "r")

        if not f then
            local err = Error(484, resolvedpath)
            LOG_DEBUG("Error executing '%s': %s", resolvedpath, err:toString())
            return false, err
        end

        ScriptSource.PushContext(resolvedpath)
        local ok, rv = Runtime.run(f.readAll(), {
            script_ctx = resolvedpath,
            origin = {
                kind = "sourced-file",
                source = resolvedpath,
            },
        })
        ScriptSource.PopContext()
        if not ok then
            local msg = Error.IsError(rv) and rv:toString() or tostring(rv)
            LOG_DEBUG("Error executing '%s': %s", resolvedpath, msg)
            return false, rv
        end

        f.close()
    end

    if startuptime then
        writestartup("sourcing " .. resolvedpath, pre)
    end
    return true
end

function ScriptSource.source(path)
    local pre = os.epoch("utc")

    local internalpath = Filesystem.Expand(path)

    -- ALso accept a table of strings
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

    if resolvedpath:sub(-4) == ".lua" then
        local ok, err = pcall(LuaLoader.LoadFile, resolvedpath)
        if not ok then
            local e = Error.IsError(err) and err or Error(5107, tostring(err))
            local msg = e:toString()
            LOG_DEBUG("Error executing '%s': %s", resolvedpath, msg)
            return false, e
        end
    elseif resolvedpath:sub(-4) == ".vim" then
        local f = fs.open(resolvedpath, "r")

        if f then
            ScriptSource.PushContext(resolvedpath)
            local ok, rv = Runtime.run(f.readAll(), {
                script_ctx = resolvedpath,
                origin = {
                    kind = "sourced-file",
                    source = resolvedpath,
                },
            })
            ScriptSource.PopContext()
            if not ok then
                local msg = Error.IsError(rv) and rv:toString() or tostring(rv)
                LOG_DEBUG("Error executing '%s': %s", resolvedpath, msg)
                return false, rv
            end

            f.close()
        end
    end

    if startuptime then
        writestartup("sourcing " .. resolvedpath, pre)
    end

    return true
end


return ScriptSource
