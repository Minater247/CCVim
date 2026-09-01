return {
    id = "api.vim_uv_fs_write",
    description = "Validates libuv file writes, positional offsets, descriptor stats, callbacks, and closed-fd errors.",

    run = function(ctx)
        local Assert = ctx.assert
        local file = Assert.temp_path(ctx.backend, "vim-uv-fs-write", ".txt")

        local result = Assert.eval_block(ctx.backend, "vim.uv fs write scenarios", string.format([=[
            local file = %q
            local fd = assert(vim.uv.fs_open(file, "w", 438))
            local first, first_err = vim.uv.fs_write(fd, "hello")
            local stat1, stat1_err = vim.uv.fs_fstat(fd)
            local positional, positional_err = vim.uv.fs_write(fd, "A", 1)
            local appended, appended_err = vim.uv.fs_write(fd, "!", -1)

            local async = {}
            local write_req = vim.uv.fs_write(fd, "?", -1, function(err, written)
                async.write_err = err
                async.written = written
            end)
            local stat_req = vim.uv.fs_fstat(fd, function(err, stat)
                async.stat_err = err
                async.size = stat and stat.size
            end)

            assert(vim.uv.fs_close(fd))
            local closed_stat, closed_err = vim.uv.fs_fstat(fd)
            local read_fd = assert(vim.uv.fs_open(file, "r", 438))
            local contents = vim.uv.fs_read(read_fd, 100, 0)
            assert(vim.uv.fs_close(read_fd))
            return {
                first = first,
                first_err = first_err,
                stat1_size = stat1 and stat1.size,
                stat1_err = stat1_err,
                positional = positional,
                positional_err = positional_err,
                appended = appended,
                appended_err = appended_err,
                async = async,
                write_req_type = type(write_req),
                stat_req_type = type(stat_req),
                closed_stat_nil = closed_stat == nil,
                closed_err = closed_err,
                contents = contents,
            }
        ]=], file))

        Assert.eq("initial byte count", result.first, 5)
        Assert.eq("initial write error", result.first_err, nil)
        Assert.eq("descriptor size after write", result.stat1_size, 5)
        Assert.eq("descriptor stat error", result.stat1_err, nil)
        Assert.eq("positional byte count", result.positional, 1)
        Assert.eq("positional write error", result.positional_err, nil)
        Assert.eq("append byte count", result.appended, 1)
        Assert.eq("append write error", result.appended_err, nil)
        Assert.eq("async byte count", result.async.written, 1)
        Assert.eq("async write error", result.async.write_err, nil)
        Assert.eq("async descriptor size", result.async.size, 7)
        Assert.eq("async stat error", result.async.stat_err, nil)
        Assert.eq("write callback request", result.write_req_type, "userdata")
        Assert.eq("stat callback request", result.stat_req_type, "userdata")
        Assert.eq("closed descriptor stat is nil", result.closed_stat_nil, true)
        Assert.truthy("closed descriptor reports EBADF", result.closed_err:find("EBADF", 1, true) ~= nil)

        Assert.eq("positional and sequential content", result.contents, "hAllo!?")
    end,
}
