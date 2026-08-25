return {
    id = "api.vim_uv_fs_async",
    description = "Ports vim.uv async filesystem callbacks for stat, realpath, directory iteration, file open/read/close, and missing-path errors.", -- luacheck: ignore 631
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local root = Assert.temp_path(backend, "vim-uv-fs-async", "")
        local file_path = root .. "/a.txt"
        local subdir = root .. "/sub"
        local missing_stat = root .. "/missing-stat"
        local missing_realpath = root .. "/missing-realpath"

        Assert.ensure_dir(backend, subdir)
        Assert.write_file(backend, file_path, "abc")

        local result = Assert.eval_block(backend, "vim.uv fs async scenarios", string.format([=[
            local root = %q
            local file_path = %q
            local missing_stat = %q
            local missing_realpath = %q

            local out = {}

            vim.uv.fs_stat(root, function(err, stat)
                out.stat = {
                    err = err,
                    type = stat and stat.type,
                }
            end)

            vim.uv.fs_stat(missing_stat, function(err, stat)
                out.missing_stat = {
                    err = err,
                    stat_is_nil = stat == nil,
                }
            end)

            vim.uv.fs_realpath(root, function(err, path)
                out.realpath = {
                    err = err,
                    path = path,
                }
            end)

            vim.uv.fs_realpath(missing_realpath, function(err, path)
                out.missing_realpath = {
                    err = err,
                    path = path,
                }
            end)

            local dir_handle = nil
            vim.uv.fs_opendir(root, function(err, handle)
                out.opendir = {
                    err = err,
                    handle_type = type(handle),
                }
                dir_handle = handle
            end, 1)

            local waits_ok, waits_reason = vim.wait(500, function()
                return out.stat ~= nil
                    and out.missing_stat ~= nil
                    and out.realpath ~= nil
                    and out.missing_realpath ~= nil
                    and out.opendir ~= nil
            end, 10)

            out.initial_wait = {
                ok = waits_ok,
                reason_nil = waits_reason == nil,
            }

            local dir_entries = {}
            vim.uv.fs_readdir(dir_handle, function(err, entries)
                dir_entries[1] = {
                    err = err,
                    count = entries and #entries or 0,
                    name = entries and entries[1] and entries[1].name,
                    type = entries and entries[1] and entries[1].type,
                    entries_nil = entries == nil,
                }
            end)
            vim.wait(500, function()
                return dir_entries[1] ~= nil
            end, 10)

            vim.uv.fs_readdir(dir_handle, function(err, entries)
                dir_entries[2] = {
                    err = err,
                    count = entries and #entries or 0,
                    name = entries and entries[1] and entries[1].name,
                    type = entries and entries[1] and entries[1].type,
                    entries_nil = entries == nil,
                }
            end)
            vim.wait(500, function()
                return dir_entries[2] ~= nil
            end, 10)

            vim.uv.fs_readdir(dir_handle, function(err, entries)
                dir_entries[3] = {
                    err = err,
                    count = entries and #entries or 0,
                    name = entries and entries[1] and entries[1].name,
                    type = entries and entries[1] and entries[1].type,
                    entries_nil = entries == nil,
                }
            end)

            local readdir_wait_ok, readdir_wait_reason = vim.wait(500, function()
                return dir_entries[1] ~= nil and dir_entries[2] ~= nil and dir_entries[3] ~= nil
            end, 10)

            out.readdir_wait = {
                ok = readdir_wait_ok,
                reason_nil = readdir_wait_reason == nil,
            }
            out.dir_entries = dir_entries

            vim.uv.fs_closedir(dir_handle, function(err)
                out.closedir = {
                    err = err,
                }
            end)

            local fd = nil
            vim.uv.fs_open(file_path, "r", 420, function(err, opened)
                out.open = {
                    err = err,
                    fd_type = type(opened),
                }
                fd = opened
            end)

            local open_wait_ok, open_wait_reason = vim.wait(500, function()
                return out.closedir ~= nil and out.open ~= nil
            end, 10)

            out.open_wait = {
                ok = open_wait_ok,
                reason_nil = open_wait_reason == nil,
            }

            vim.uv.fs_read(fd, 2, -1, function(err, data)
                out.read = {
                    err = err,
                    data = data,
                }
            end)

            local read_wait_ok, read_wait_reason = vim.wait(500, function()
                return out.read ~= nil
            end, 10)

            out.read_wait = {
                ok = read_wait_ok,
                reason_nil = read_wait_reason == nil,
            }

            vim.uv.fs_close(fd, function(err)
                out.close = {
                    err = err,
                }
            end)

            local close_wait_ok, close_wait_reason = vim.wait(500, function()
                return out.close ~= nil
            end, 10)

            out.close_wait = {
                ok = close_wait_ok,
                reason_nil = close_wait_reason == nil,
            }

            return out
        ]=], root, file_path, missing_stat, missing_realpath))

        Assert.eq("initial async callbacks wait succeeds", result.initial_wait.ok, true)
        Assert.eq("initial async callbacks wait reason", result.initial_wait.reason_nil, true)
        Assert.eq("fs_stat err nil", result.stat.err, nil)
        Assert.eq("fs_stat type directory", result.stat.type, "directory")
        Assert.truthy(
            "fs_stat missing err text",
            type(result.missing_stat.err) == "string" and result.missing_stat.err ~= "",
            result.missing_stat.err
        )
        Assert.eq("fs_stat missing stat nil", result.missing_stat.stat_is_nil, true)
        Assert.eq("fs_realpath err nil", result.realpath.err, nil)
        local realpath_matches = result.realpath.path == root
            or (root:sub(1, 4) == "/tmp" and result.realpath.path == "/private" .. root)
        Assert.truthy("fs_realpath path", realpath_matches, result.realpath.path)
        Assert.truthy(
            "fs_realpath missing err text",
            type(result.missing_realpath.err) == "string" and result.missing_realpath.err ~= "",
            result.missing_realpath.err
        )
        Assert.eq("fs_realpath missing path nil", result.missing_realpath.path, nil)
        Assert.eq("fs_opendir err nil", result.opendir.err, nil)
        Assert.eq("fs_opendir returns userdata handle", result.opendir.handle_type, "userdata")
        Assert.eq("fs_readdir wait succeeds", result.readdir_wait.ok, true)
        Assert.eq("fs_readdir wait reason", result.readdir_wait.reason_nil, true)
        Assert.eq("fs_readdir first err nil", result.dir_entries[1].err, nil)
        Assert.eq("fs_readdir second err nil", result.dir_entries[2].err, nil)
        Assert.eq("fs_readdir eof err nil", result.dir_entries[3].err, nil)
        Assert.eq("fs_readdir first count", result.dir_entries[1].count, 1)
        Assert.eq("fs_readdir second count", result.dir_entries[2].count, 1)
        Assert.eq("fs_readdir eof entries nil", result.dir_entries[3].entries_nil, true)

        local seen = {}
        seen[result.dir_entries[1].name] = result.dir_entries[1].type
        seen[result.dir_entries[2].name] = result.dir_entries[2].type
        Assert.eq("fs_readdir saw subdir", seen.sub, "directory")
        Assert.eq("fs_readdir saw file", seen["a.txt"], "file")

        Assert.eq("fs_closedir/open wait succeeds", result.open_wait.ok, true)
        Assert.eq("fs_closedir/open wait reason", result.open_wait.reason_nil, true)
        Assert.eq("fs_closedir err nil", result.closedir.err, nil)
        Assert.eq("fs_open err nil", result.open.err, nil)
        Assert.eq("fs_open returns numeric fd", result.open.fd_type, "number")
        Assert.eq("fs_read wait succeeds", result.read_wait.ok, true)
        Assert.eq("fs_read wait reason", result.read_wait.reason_nil, true)
        Assert.eq("fs_read err nil", result.read.err, nil)
        Assert.eq("fs_read returned expected data", result.read.data, "ab")
        Assert.eq("fs_close wait succeeds", result.close_wait.ok, true)
        Assert.eq("fs_close wait reason", result.close_wait.reason_nil, true)
        Assert.eq("fs_close err nil", result.close.err, nil)
    end,
}
