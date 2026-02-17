local loop = {}

local VimRegex = loadModule("vim.lib.excmd.vim_regex")
local Event = loadModule("vim.lib.event")
local VimFs = loadModule("vim.lib.luaapi.fs")
local EnvVars = loadModule("vim.lib.envvars")

-- Convert a time in ms to the format a stat expects.
local function modtimeconv(msec)
    return {
        sec = math.floor(msec / 1000),
        nsec = msec * 1000000
    }
end

-- todo: mode
function loop.fs_stat(path)
    path = VimFs.abspath(path)

    local attribs = fs.attributes(path)

    return {
        path = path,
        size = attribs.size,
        type = attribs.isDir and "directory" or "file",
        ctime = modtimeconv(attribs.created),
        mtime = modtimeconv(attribs.modified),
    }
end

-- CC has no links, but if we ever port, this needs changing
loop.fs_lstat = loop.fs_stat

function loop.cwd()
    return "/" .. shell.dir()
end

function loop.fs_open(path, mode, permission)
    -- permission currently ignored as ComputerCraft doesn't handle that

    return fs.open(path, mode)
end

function loop.fs_read(fd, size, offset, callback)
    local initseek = fd.seek()

    local rv = fd.read(size)

    if offset and offset >= 0 then
        fd.seek("set", initseek)
    end

    return rv or ""
end

function loop.fs_close(fd, callback)
    fd.close()
end

-- =========
-- timers
-- =========
local function mk_timer()
    return {
        id      = nil, -- backend id from Event.StartTimer
        _active = false,
        _closed = false,
        _repeat = 0,
    }
end

function loop.new_timer()
    return mk_timer()
end

function loop.timer_stop(timer)
    if timer and timer._active and timer.id then
        Event.CancelTimer(timer.id)
    end
    timer._active = false
end

function loop.close(timer)
    -- libuv requires closing; here we just stop and mark closed
    loop.timer_stop(timer)
    timer._closed = true
end

function loop.timer_set_repeat(timer, repeat_ms)
    timer._repeat = math.max(0, repeat_ms or 0)
end

function loop.timer_get_repeat(timer)
    return timer._repeat or 0
end

-- libuv-compatible signature:
--   timer, timeout_ms, repeat_ms, callback
function loop.timer_start(timer, timeout_ms, repeat_ms, callback)
    if timer._closed then return error("close on a closed timer") end
    timer._repeat = math.max(0, repeat_ms or 0)

    -- one tick function that reschedules itself for repeating timers
    local function tick()
        if timer._closed then return end
        -- Pass the handle like libuv C does; Lua callbacks that don't take args will just ignore it
        callback(timer)
        if timer._repeat == 0 then
            loop.timer_stop(timer)
        else
            -- schedule the next tick after repeat_ms
            timer.id = Event.StartTimer(timer._repeat / 1000, tick)
        end
    end

    loop.timer_stop(timer) -- if already running
    timer._active = true
    timer.id = Event.StartTimer(math.max(0, (timeout_ms or 0)) / 1000, tick)
    return 0
end

function loop.fs_realpath(path)
    path = VimFs.abspath(path)

    if fs.exists(path) then
        return path
    else
        error("File does not exist for fs_realpath: " .. path)
    end
end

function loop.hrtime()
    return os.epoch("utc") * 1000000
end

function loop.fs_scandir(path)
    local i = 1
    local items = fs.list(path)
    return function()
        local rv = items[i]
        i = i + 1
        return rv
    end
end

function loop.fs_scandir_next(handle)
    return handle()
end

function loop.fs_access(path, mode, callback)
    path = VimFs.abspath(path)

    if not fs.exists(path) then
        return false
    end

    if mode == "R" then
        return true -- already did the existence check
    end

    if mode == "W" then
        return not fs.isReadOnly(path) -- TODO: are dirs writable if entry list modifiable?
    end

    if mode == "X" then
        return (not fs.isDir(path)) and (path:sub(-4) == ".lua")
    end

    error("INVALID MODE")
end

-- TODO: actually schedule this on a timer
function loop.fs_event_start(fs_event, path, flags, callback)
    fs_event.path = path
    fs_event.recursive = flags.recursive
    fs_event.callback = callback
    return 0
end

-- TODO: stop the scheduled timer per above
function loop.fs_event_stop(fs_event)
    return 0
end

function loop.new_fs_event()
    return {
        start = loop.fs_event_start,
        stop = loop.fs_event_stop,
    }
end

function loop.os_uname()
    return {
        sysname = "linux",
        release = "0.0.0",
        version = "null",
    }
end

function loop.os_homedir()
    return EnvVars.get("HOME")
end

return loop
