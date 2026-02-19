local MockEnv = require("vim.tests.test_mocks")

local paths = {
    ["/dir"] = { is_dir = true, entries = { "a.txt", "sub" } },
    ["/dir/a.txt"] = { is_dir = false, content = "abc" },
    ["/dir/sub"] = { is_dir = true, entries = {} },
}

local mock = MockEnv.setup({
    fs = {
        exists = function(path)
            return paths[path] ~= nil
        end,
        isDir = function(path)
            return paths[path] and paths[path].is_dir or false
        end,
        list = function(path)
            return (paths[path] and paths[path].entries) or {}
        end,
        attributes = function(path)
            local p = paths[path]
            if not p then
                error(path .. ": No such file")
            end
            return {
                size = #(p.content or ""),
                isDir = p.is_dir,
                created = 0,
                modified = 0,
            }
        end,
        open = function(path, mode)
            local p = paths[path]
            if mode == "w" then
                if p and p.is_dir then
                    return nil
                end
                p = { is_dir = false, content = "" }
                paths[path] = p
            elseif mode == "a" then
                if p and p.is_dir then
                    return nil
                end
                if not p then
                    p = { is_dir = false, content = "" }
                    paths[path] = p
                end
            elseif not p or p.is_dir then
                return nil
            end

            local cursor = 0
            if mode == "a" then
                cursor = #(p.content or "")
            end

            local handle = {}
            handle.read = function(count)
                local content = p.content or ""
                if cursor >= #content then
                    return nil
                end
                local n = tonumber(count) or (#content - cursor)
                local start_idx = cursor + 1
                local end_idx = math.min(#content, cursor + n)
                local chunk = content:sub(start_idx, end_idx)
                cursor = end_idx
                return chunk
            end
            handle.write = function(chunk)
                local content = p.content or ""
                local prefix = content:sub(1, cursor)
                p.content = prefix .. tostring(chunk)
                cursor = #p.content
            end
            handle.seek = function(whence, offset)
                whence = whence or "cur"
                offset = offset or 0
                if whence == "set" then
                    cursor = math.max(0, offset)
                elseif whence == "cur" then
                    cursor = math.max(0, cursor + offset)
                elseif whence == "end" then
                    cursor = math.max(0, #(p.content or "") + offset)
                else
                    error("bad whence: " .. tostring(whence))
                end
                return cursor
            end
            handle.close = function() end
            return handle
        end,
        isReadOnly = function()
            return false
        end,
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local Loop = mock.loadModule("vim.lib.luaapi.loop")

local stat_called, stat_err, stat_val = false, nil, nil
Loop.fs_stat("/dir", function(err, stat)
    stat_called = true
    stat_err = err
    stat_val = stat
end)
assert_true("fs_stat async callback called", stat_called, stat_called)
assert_eq("fs_stat async err nil", stat_err, nil)
assert_eq("fs_stat async type", stat_val.type, "directory")

local miss_called, miss_err = false, nil
Loop.fs_stat("/missing", function(err, stat)
    miss_called = true
    miss_err = err
    assert_eq("fs_stat missing stat nil", stat, nil)
end)
assert_true("fs_stat missing callback called", miss_called, miss_called)
assert_true("fs_stat missing has err", type(miss_err) == "string" and miss_err ~= "", miss_err)

local realpath_called, realpath_err, realpath_val = false, nil, nil
Loop.fs_realpath("/dir", function(err, path)
    realpath_called = true
    realpath_err = err
    realpath_val = path
end)
assert_true("fs_realpath callback called", realpath_called, realpath_called)
assert_eq("fs_realpath err nil", realpath_err, nil)
assert_eq("fs_realpath path", realpath_val, "/dir")

local realpath_miss_called, realpath_miss_err, realpath_miss_val = false, nil, "unset"
Loop.fs_realpath("/missing", function(err, path)
    realpath_miss_called = true
    realpath_miss_err = err
    realpath_miss_val = path
end)
assert_true("fs_realpath missing callback called", realpath_miss_called, realpath_miss_called)
assert_true(
    "fs_realpath missing has err",
    type(realpath_miss_err) == "string" and realpath_miss_err ~= "",
    realpath_miss_err
)
assert_eq("fs_realpath missing path nil", realpath_miss_val, nil)

local opened = nil
Loop.fs_opendir("/dir", function(err, fd)
    assert_eq("fs_opendir err nil", err, nil)
    opened = fd
end, 1)
assert_true("fs_opendir returned handle via callback", type(opened) == "table", type(opened))

local chunk1 = nil
Loop.fs_readdir(opened, function(err, entries)
    assert_eq("fs_readdir chunk1 err nil", err, nil)
    chunk1 = entries
end)
assert_eq("fs_readdir chunk1 size", #chunk1, 1)
assert_eq("fs_readdir chunk1 name", chunk1[1].name, "a.txt")
assert_eq("fs_readdir chunk1 type", chunk1[1].type, "file")

local chunk2 = nil
Loop.fs_readdir(opened, function(err, entries)
    assert_eq("fs_readdir chunk2 err nil", err, nil)
    chunk2 = entries
end)
assert_eq("fs_readdir chunk2 size", #chunk2, 1)
assert_eq("fs_readdir chunk2 name", chunk2[1].name, "sub")
assert_eq("fs_readdir chunk2 type", chunk2[1].type, "directory")

local eof = "unset"
Loop.fs_readdir(opened, function(err, entries)
    assert_eq("fs_readdir eof err nil", err, nil)
    eof = entries
end)
assert_eq("fs_readdir eof nil entries", eof, nil)

local close_called, close_err = false, nil
Loop.fs_closedir(opened, function(err)
    close_called = true
    close_err = err
end)
assert_true("fs_closedir callback called", close_called, close_called)
assert_eq("fs_closedir err nil", close_err, nil)

local open_called, open_err, fd = false, nil, nil
Loop.fs_open("/dir/a.txt", "r", 420, function(err, opened_fd)
    open_called = true
    open_err = err
    fd = opened_fd
end)
assert_true("fs_open callback called", open_called, open_called)
assert_eq("fs_open err nil", open_err, nil)
assert_true("fs_open returned fd", fd ~= nil, fd)

local read_called, read_err, read_data = false, nil, nil
Loop.fs_read(fd, 2, nil, function(err, data)
    read_called = true
    read_err = err
    read_data = data
end)
assert_true("fs_read callback called", read_called, read_called)
assert_eq("fs_read err nil", read_err, nil)
assert_eq("fs_read returned expected data", read_data, "ab")

local close_fd_called, close_fd_err = false, nil
Loop.fs_close(fd, function(err)
    close_fd_called = true
    close_fd_err = err
end)
assert_true("fs_close callback called", close_fd_called, close_fd_called)
assert_eq("fs_close err nil", close_fd_err, nil)

print("loop fs async tests: OK")
