return {
    id = "api.vim_uv_fs_unlink",
    description = "Ports vim.uv.fs_unlink() sync and async result tuples against real filesystem operations.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local sync_path = Assert.temp_path(backend, "vim-uv-unlink-sync", ".txt")
        local async_path = Assert.temp_path(backend, "vim-uv-unlink-async", ".txt")
        local miss_path = Assert.temp_path(backend, "vim-uv-unlink-missing", ".txt")
        local async_miss_path = Assert.temp_path(backend, "vim-uv-unlink-async-missing", ".txt")

        Assert.write_file(backend, sync_path, "sync\n")
        Assert.write_file(backend, async_path, "async\n")

        local result = Assert.eval_block(backend, "vim.uv fs_unlink scenarios", string.format([=[
            local sync_path = %q
            local async_path = %q
            local miss_path = %q
            local async_miss_path = %q

            local sync_ok, sync_err, sync_name = vim.uv.fs_unlink(sync_path)

            local async_called = false
            local async_req = vim.uv.fs_unlink(async_path, function(err, ok)
                async_called = {
                    err = err,
                    ok = ok,
                    path_missing = vim.uv.fs_stat(async_path) == nil,
                }
            end)
            local async_wait_ok, async_wait_reason = vim.wait(500, function()
                return async_called ~= false
            end, 10)

            local miss_ok, miss_err, miss_name = vim.uv.fs_unlink(miss_path)

            local async_miss_called = false
            local async_miss_req = vim.uv.fs_unlink(async_miss_path, function(err, ok)
                async_miss_called = { err = err, ok = ok }
            end)
            local async_miss_wait_ok, async_miss_wait_reason = vim.wait(500, function()
                return async_miss_called ~= false
            end, 10)

            return {
                sync = {
                    ok = sync_ok,
                    err = sync_err,
                    errname = sync_name,
                    path_missing = vim.uv.fs_stat(sync_path) == nil,
                },
                async = {
                    req_type = type(async_req),
                    wait_ok = async_wait_ok,
                    wait_reason_nil = async_wait_reason == nil,
                    callback = async_called,
                },
                missing = {
                    ok = miss_ok,
                    err = miss_err,
                    errname = miss_name,
                },
                async_missing = {
                    req_type = type(async_miss_req),
                    wait_ok = async_miss_wait_ok,
                    wait_reason_nil = async_miss_wait_reason == nil,
                    callback = async_miss_called,
                },
            }
        ]=], sync_path, async_path, miss_path, async_miss_path))

        Assert.eq("sync unlink ok", result.sync.ok, true)
        Assert.eq("sync unlink err nil", result.sync.err, nil)
        Assert.eq("sync unlink errname nil", result.sync.errname, nil)
        Assert.eq("sync unlink removed path", result.sync.path_missing, true)
        Assert.eq("async unlink returns userdata request", result.async.req_type, "userdata")
        Assert.eq("async unlink wait succeeds", result.async.wait_ok, true)
        Assert.eq("async unlink wait reason", result.async.wait_reason_nil, true)
        Assert.eq("async unlink callback err nil", result.async.callback.err, nil)
        Assert.eq("async unlink callback ok true", result.async.callback.ok, true)
        Assert.eq("async unlink removed path", result.async.callback.path_missing, true)
        Assert.eq("missing unlink ok nil", result.missing.ok, nil)
        Assert.truthy(
            "missing unlink err text",
            type(result.missing.err) == "string" and result.missing.err ~= "",
            result.missing.err
        )
        Assert.eq("missing unlink errname", result.missing.errname, "ENOENT")
        Assert.eq("async missing unlink returns userdata request", result.async_missing.req_type, "userdata")
        Assert.eq("async missing unlink wait succeeds", result.async_missing.wait_ok, true)
        Assert.eq("async missing unlink wait reason", result.async_missing.wait_reason_nil, true)
        Assert.truthy(
            "async missing unlink err text",
            type(result.async_missing.callback.err) == "string" and result.async_missing.callback.err ~= "",
            result.async_missing.callback.err
        )
        Assert.eq("async missing unlink ok nil", result.async_missing.callback.ok, nil)
    end,
}
