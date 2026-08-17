local loop = {}
local FsUtil = loadModule("lib.fsutil")

local Backend = loadModule("lib.backend")
local Event = loadModule("lib.event")
local FakeUserdata = loadModule("lib.luaapi.fakeuserdata")
local VimFs = loadModule("lib.luaapi.fs")
local EnvVars = loadModule("lib.envvars")

local function has_uri_scheme(path)
    return type(path) == "string" and path:match("^[%w][%w%+%-%.]*://") ~= nil
end

local function log_fs_stat_miss(path, reason)
    local trace = debug.traceback("fs_stat miss trace:", 3)
    LOG_DEBUG("error maybe? loop.fs_stat miss path=%s reason=%s\n%s", tostring(path), tostring(reason), tostring(trace))
end

local function log_loop_fs(format, ...)
    LOG_DEBUG("loop.fs " .. tostring(format), ...)
end

-- Convert a time in ms to the format a stat expects.
local function modtimeconv(msec)
    return {
        sec = math.floor(msec / 1000),
        nsec = msec * 1000000
    }
end

local next_fs_fd = 2
local open_fds = {}

local function new_fs_req(op, fields)
    fields = fields or {}
    fields._op = op
    fields._done = true
    return FakeUserdata.new("uv_fs_t", fields)
end

local function alloc_fd(handle)
    next_fs_fd = next_fs_fd + 1
    open_fds[next_fs_fd] = handle
    return next_fs_fd
end

local function resolve_fd(fd)
    if type(fd) == "number" then
        local handle = open_fds[fd]
        if not handle then
            return nil, "EBADF: bad file descriptor"
        end
        return handle, fd
    end
    if type(fd) == "table" and (fd.read or fd.close or fd.seek) then
        return fd, nil
    end
    return nil, "EBADF: bad file descriptor"
end

local function _fs_stat_impl(path)
    if has_uri_scheme(path) then
        log_fs_stat_miss(path, "uri-scheme")
        return nil, "ENOENT: unsupported uri scheme"
    end

    path = VimFs.abspath(path)

    local ok, attribs = pcall(fs.attributes, path)
    if not ok or type(attribs) ~= "table" then
        log_fs_stat_miss(path, ok and "invalid-attribs" or tostring(attribs))
        return nil, ok and "ENOENT: invalid attribs" or tostring(attribs)
    end

    return {
        path = path,
        size = attribs.size,
        type = attribs.isDir and "directory" or "file",
        ctime = modtimeconv(attribs.created),
        mtime = modtimeconv(attribs.modified),
    }, nil
end

-- todo: mode
function loop.fs_stat(path, callback)
    local stat, err = _fs_stat_impl(path)
    if type(callback) == "function" then
        log_loop_fs(
            "fs_stat(path=%s, cb=true) -> err=%s type=%s",
            tostring(path),
            tostring(err),
            tostring(stat and stat.type)
        )
        callback(err, stat)
        return
    end
    return stat
end

function loop.fs_lstat(path, callback)
    -- CC/OC have no links
    return loop.fs_stat(path, callback)
end

function loop.fs_opendir(path, a2, a3)
    local callback
    local max_entries
    if type(a2) == "function" then
        callback = a2
        max_entries = tonumber(a3)
    elseif type(a3) == "function" then
        max_entries = tonumber(a2)
        callback = a3
    end
    max_entries = math.max(1, math.floor(max_entries or 256))

    if has_uri_scheme(path) then
        local err = "ENOENT: unsupported uri scheme"
        log_loop_fs("fs_opendir(path=%s) -> %s", tostring(path), err)
        if callback then
            callback(err, nil)
            return
        end
        return nil, err
    end

    local dir = VimFs.abspath(path)
    if not fs.exists(dir) then
        local err = "ENOENT: no such file or directory"
        log_loop_fs("fs_opendir(path=%s) -> %s", tostring(dir), err)
        if callback then
            callback(err, nil)
            return
        end
        return nil, err
    end
    if not fs.isDir(dir) then
        local err = "ENOTDIR: not a directory"
        log_loop_fs("fs_opendir(path=%s) -> %s", tostring(dir), err)
        if callback then
            callback(err, nil)
            return
        end
        return nil, err
    end

    local handle = FakeUserdata.new("uv_dir_t", {
        _path = dir,
        _items = fs.list(dir) or {},
        _idx = 1,
        _max_entries = max_entries,
        _closed = false,
    })
    local state = FakeUserdata.state(handle)
    log_loop_fs(
        "fs_opendir(path=%s) -> ok items=%d max=%d",
        tostring(dir),
        #(state and state._items or {}),
        max_entries
    )
    if callback then
        callback(nil, handle)
        return
    end
    return handle
end

function loop.fs_readdir(handle, callback)
    local state = FakeUserdata.state(handle)
    if state == nil or not state._path then
        local err = "EBADF: bad directory handle"
        log_loop_fs("fs_readdir(handle=%s) -> %s", tostring(handle), err)
        if type(callback) == "function" then
            callback(err, nil)
            return
        end
        return nil, err
    end
    if state._closed then
        local err = "EBADF: directory handle closed"
        log_loop_fs("fs_readdir(path=%s) -> %s", tostring(state._path), err)
        if type(callback) == "function" then
            callback(err, nil)
            return
        end
        return nil, err
    end

    if state._idx > #state._items then
        log_loop_fs("fs_readdir(path=%s) -> eof", tostring(state._path))
        if type(callback) == "function" then
            callback(nil, nil)
            return
        end
        return nil
    end

    local out = {}
    local max_entries = state._max_entries or #state._items
    for _ = 1, max_entries do
        local name = state._items[state._idx]
        if not name then
            break
        end
        state._idx = state._idx + 1
        local abs = FsUtil.join(state._path, name)
        out[#out + 1] = {
            name = name,
            type = fs.isDir(abs) and "directory" or "file",
        }
    end
    log_loop_fs("fs_readdir(path=%s) -> %d entries", tostring(state._path), #out)
    if type(callback) == "function" then
        callback(nil, out)
        return
    end
    return out
end

function loop.fs_closedir(handle, callback)
    local state = FakeUserdata.state(handle)
    if state == nil or not state._path then
        local err = "EBADF: bad directory handle"
        log_loop_fs("fs_closedir(handle=%s) -> %s", tostring(handle), err)
        if type(callback) == "function" then
            callback(err)
            return
        end
        return nil, err
    end
    state._closed = true
    log_loop_fs("fs_closedir(path=%s) -> ok", tostring(state._path))
    if type(callback) == "function" then
        callback(nil)
        return
    end
    return true
end

function loop.cwd()
    return Backend.cwd()
end

function loop.fs_open(path, mode, permission, callback)
    -- permission currently ignored as ComputerCraft doesn't handle that
    if type(permission) == "function" and callback == nil then
        callback = permission
    end

    local handle = fs.open(path, mode)
    local err
    if not handle then
        err = "ENOENT: no such file or directory"
    end

    local fd
    if err == nil and handle ~= nil then
        fd = alloc_fd(handle)
    end

    if type(callback) == "function" then
        callback(err, fd)
        return new_fs_req("open", {
            _path = path,
            _fd = fd,
        })
    end
    return fd, err
end

function loop.fs_read(fd, size, offset, callback)
    if type(offset) == "function" and callback == nil then
        callback = offset
        offset = nil
    end

    local ok, rv_or_err = pcall(function()
        local handle, resolve_err = resolve_fd(fd)
        if not handle then
            error(resolve_err)
        end

        local initseek = handle.seek and handle.seek()
        if offset and offset >= 0 then
            handle.seek("set", offset)
        end

        local data = handle.read and handle.read(size)

        if offset and offset >= 0 and initseek ~= nil then
            handle.seek("set", initseek)
        end
        return data or ""
    end)
    local err
    local data
    if ok then
        data = rv_or_err
    else
        err = tostring(rv_or_err)
    end

    if type(callback) == "function" then
        callback(err, data)
        return new_fs_req("read")
    end
    return data, err
end

function loop.fs_close(fd, callback)
    local ok, close_err = pcall(function()
        local handle, fd_num_or_nil = resolve_fd(fd)
        if not handle then
            error(fd_num_or_nil)
        end
        if handle.close then
            handle.close()
        end
        if fd_num_or_nil ~= nil then
            open_fds[fd_num_or_nil] = nil
        end
    end)
    local err
    if not ok then
        err = tostring(close_err)
    end
    if type(callback) == "function" then
        callback(err)
        return new_fs_req("close")
    end
    return err == nil, err
end

local function _fs_unlink_impl(path)
    if has_uri_scheme(path) then
        return nil, "ENOENT: unsupported uri scheme", "ENOENT"
    end

    path = VimFs.abspath(path)
    if not fs.exists(path) then
        return nil, "ENOENT: no such file or directory", "ENOENT"
    end
    if fs.isDir(path) then
        return nil, "EISDIR: illegal operation on a directory", "EISDIR"
    end
    if fs.isReadOnly and fs.isReadOnly(path) then
        return nil, "EACCES: permission denied", "EACCES"
    end

    local ok, err = pcall(fs.delete, path)
    if not ok then
        return nil, "EPERM: operation not permitted (" .. tostring(err) .. ")", "EPERM"
    end
    return true, nil, nil
end

function loop.fs_unlink(path, callback)
    local ok, err, errname = _fs_unlink_impl(path)
    if type(callback) == "function" then
        log_loop_fs("fs_unlink(path=%s, cb=true) -> err=%s ok=%s", tostring(path), tostring(err), tostring(ok))
        callback(err, ok and true)
        return new_fs_req("unlink", {
            _path = path,
        })
    end
    return ok, err, errname
end

local function _fs_rename_impl(path, new_path)
    if has_uri_scheme(path) or has_uri_scheme(new_path) then
        return nil, "ENOENT: unsupported uri scheme", "ENOENT"
    end

    path = VimFs.abspath(path)
    new_path = VimFs.abspath(new_path)

    if not fs.exists(path) then
        return nil, "ENOENT: no such file or directory", "ENOENT"
    end
    if fs.isReadOnly and fs.isReadOnly(path) then
        return nil, "EACCES: permission denied", "EACCES"
    end
    if path == new_path then
        return true, nil, nil
    end

    local ok, moved_or_err, move_err = pcall(fs.move, path, new_path)
    if not ok then
        return nil, "EPERM: operation not permitted (" .. tostring(moved_or_err) .. ")", "EPERM"
    end
    if moved_or_err == false then
        return nil, "EPERM: operation not permitted (" .. tostring(move_err) .. ")", "EPERM"
    end
    return true, nil, nil
end

function loop.fs_rename(path, new_path, callback)
    local ok, err, errname = _fs_rename_impl(path, new_path)
    if type(callback) == "function" then
        log_loop_fs(
            "fs_rename(path=%s, new_path=%s, cb=true) -> err=%s ok=%s",
            tostring(path),
            tostring(new_path),
            tostring(err),
            tostring(ok)
        )
        callback(err, ok and true)
        return new_fs_req("rename", {
            _path = path,
            _new_path = new_path,
        })
    end
    return ok, err, errname
end

-- =========
-- timers
-- =========
local timer_mt = {
    __index = {
        start = function(self, timeout_ms, repeat_ms, callback)
            return loop.timer_start(self, timeout_ms, repeat_ms, callback)
        end,
        again = function(self)
            return loop.timer_again(self)
        end,
        stop = function(self)
            return loop.timer_stop(self)
        end,
        close = function(self)
            return loop.close(self)
        end,
        set_repeat = function(self, repeat_ms)
            return loop.timer_set_repeat(self, repeat_ms)
        end,
        get_repeat = function(self)
            return loop.timer_get_repeat(self)
        end,
        is_active = function(self)
            return loop.is_active(self)
        end,
        is_closing = function(self)
            return loop.is_closing(self)
        end,
    },
}

local function mk_timer()
    return setmetatable({
        _handle_type = "timer",
        id      = nil, -- backend id from Event.StartTimer
        _active = false,
        _closed = false,
        _repeat = 0,
        _cb     = nil,
    }, timer_mt)
end

function loop.new_timer()
    return mk_timer()
end

function loop.timer_stop(timer)
    if timer and timer._active and timer.id then
        Event.CancelTimer(timer.id)
    end
    timer._active = false
    timer.id = nil
end

function loop.close(handle)
    -- libuv requires closing; here we just stop and mark closed
    if handle._handle_type == "check" then
        loop.check_stop(handle)
    else
        loop.timer_stop(handle)
    end
    handle._closed = true
    handle._cb = nil
end

function loop.timer_set_repeat(timer, repeat_ms)
    timer._repeat = math.max(0, repeat_ms or 0)
end

function loop.timer_get_repeat(timer)
    return timer._repeat or 0
end

-- libuv-compatible signature:
--   timer, timeout_ms, repeat_ms, callback
local function _timer_schedule(timer, timeout_ms)
    timer.id = Event.StartTimer(math.max(0, timeout_ms or 0) / 1000, function()
        if timer._closed then
            return
        end
        local cb = timer._cb
        if type(cb) == "function" then
            cb(timer)
        end
        if timer._closed then
            return
        end
        if timer._active and (timer._repeat or 0) > 0 then
            _timer_schedule(timer, timer._repeat)
        else
            timer._active = false
            timer.id = nil
        end
    end)
end

function loop.timer_start(timer, timeout_ms, repeat_ms, callback)
    if timer._closed then return error("close on a closed timer") end
    if type(callback) ~= "function" then
        return error("timer callback must be a function")
    end
    timer._repeat = math.max(0, repeat_ms or 0)
    timer._cb = callback

    loop.timer_stop(timer) -- if already running
    timer._active = true
    _timer_schedule(timer, timeout_ms or 0)
    return 0
end

function loop.timer_again(timer)
    if timer._closed then return error("close on a closed timer") end
    if type(timer._cb) ~= "function" then
        return 0
    end
    if (timer._repeat or 0) <= 0 then
        return 0
    end
    loop.timer_stop(timer)
    timer._active = true
    _timer_schedule(timer, timer._repeat)
    return 0
end

local check_mt = {
    __index = {
        start = function(self, callback)
            return loop.check_start(self, callback)
        end,
        stop = function(self)
            return loop.check_stop(self)
        end,
        close = function(self)
            return loop.close(self)
        end,
        is_active = function(self)
            return loop.is_active(self)
        end,
        is_closing = function(self)
            return loop.is_closing(self)
        end,
    },
}

local function mk_check()
    return setmetatable({
        _handle_type = "check",
        id = nil,
        _active = false,
        _closed = false,
        _cb = nil,
    }, check_mt)
end

local function _check_schedule(check)
    check.id = Event.StartTimer(0, function()
        if check._closed or not check._active then
            return
        end
        check.id = nil

        local cb = check._cb
        if type(cb) == "function" then
            cb(check)
        end

        if check._closed or not check._active then
            return
        end
        _check_schedule(check)
    end)
end

function loop.new_check()
    return mk_check()
end

function loop.check_start(check, callback)
    if check._closed then return error("close on a closed check") end
    if type(callback) ~= "function" then
        return error("check callback must be a function")
    end

    check._cb = callback
    check._active = true
    if not check.id then
        _check_schedule(check)
    end
    return 0
end

function loop.check_stop(check)
    if check and check.id then
        Event.CancelTimer(check.id)
    end
    check.id = nil
    check._active = false
    return 0
end

function loop.is_active(handle)
    return handle._active or false
end

function loop.is_closing(handle)
    return handle._closed or false
end

local function _fs_realpath_impl(path)
    if has_uri_scheme(path) then
        return nil, "ENOENT: unsupported uri scheme"
    end

    local abs = VimFs.abspath(path)
    if fs.exists(abs) then
        return abs, nil
    end
    return nil, "ENOENT: no such file or directory"
end

function loop.fs_realpath(path, callback)
    local real, err = _fs_realpath_impl(path)
    if type(callback) == "function" then
        log_loop_fs("fs_realpath(path=%s, cb=true) -> err=%s real=%s", tostring(path), tostring(err), tostring(real))
        callback(err, real)
        return
    end
    return real
end

function loop.hrtime()
    return os.epoch("utc") * 1000000
end

function loop.update_time()
    -- no-op: now() reads current time directly
end

function loop.now()
    return os.epoch("utc")
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

    local ok
    if not fs.exists(path) then
        ok = false
    elseif mode == "R" then
        ok = true -- already did the existence check
    elseif mode == "W" then
        ok = not fs.isReadOnly(path) -- TODO: are dirs writable if entry list modifiable?
    elseif mode == "X" then
        ok = (not fs.isDir(path)) and (path:sub(-4) == ".lua")
    else
        error("INVALID MODE")
    end

    if type(callback) == "function" then
        callback(ok and nil or "EACCES: access denied", ok)
        return
    end
    return ok
end

-- TODO: actually schedule this on a timer
function loop.fs_event_start(fs_event, path, flags, callback)
    fs_event.path = path
    fs_event.recursive = flags.recursive
    fs_event.callback = callback
    LOG_DEBUG("FS_EVENT_START NOT ACTUALLY SCHEDULED")
    return 0
end

-- TODO: stop the scheduled timer per above
function loop.fs_event_stop(_)
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

function loop.os_getenv(name, size)
    local value = EnvVars.get(name)
    if not value then
        return nil, "ENOENT: no such environment variable"
    end
    
    if size and #value > size then
        return nil, "ENOBUFS: buffer too small for environment variable"
    end
    
    return value
end

return loop
