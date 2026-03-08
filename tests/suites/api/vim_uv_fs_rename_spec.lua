return {
    id = "api.vim_uv_fs_rename",
    description = "Ports vim.uv.fs_rename() sync and async result tuples against real filesystem operations.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local sync_src = Assert.temp_path(backend, "vim-uv-rename-sync-src", ".txt")
        local sync_dst = Assert.temp_path(backend, "vim-uv-rename-sync-dst", ".txt")
        local async_src = Assert.temp_path(backend, "vim-uv-rename-async-src", ".txt")
        local async_dst = Assert.temp_path(backend, "vim-uv-rename-async-dst", ".txt")
        local miss_src = Assert.temp_path(backend, "vim-uv-rename-missing-src", ".txt")
        local miss_dst = Assert.temp_path(backend, "vim-uv-rename-missing-dst", ".txt")
        local async_miss_src = Assert.temp_path(backend, "vim-uv-rename-async-missing-src", ".txt")
        local async_miss_dst = Assert.temp_path(backend, "vim-uv-rename-async-missing-dst", ".txt")

        Assert.write_file(backend, sync_src, "sync\n")
        Assert.write_file(backend, async_src, "async\n")

        local result = Assert.eval_block(backend, "vim.uv fs_rename scenarios", string.format([=[
            local sync_src = %q
            local sync_dst = %q
            local async_src = %q
            local async_dst = %q
            local miss_src = %q
            local miss_dst = %q
            local async_miss_src = %q
            local async_miss_dst = %q

            local sync_ok, sync_err, sync_name = vim.uv.fs_rename(sync_src, sync_dst)

            local async_called = false
            local async_req = vim.uv.fs_rename(async_src, async_dst, function(err, ok)
                async_called = {
                    err = err,
                    ok = ok,
                    source_missing = vim.uv.fs_stat(async_src) == nil,
                    dest_present = vim.uv.fs_stat(async_dst) ~= nil,
                }
            end)
            local async_wait_ok, async_wait_reason = vim.wait(500, function()
                return async_called ~= false
            end, 10)

            local miss_ok, miss_err, miss_name = vim.uv.fs_rename(miss_src, miss_dst)

            local async_miss_called = false
            local async_miss_req = vim.uv.fs_rename(async_miss_src, async_miss_dst, function(err, ok)
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
                    source_missing = vim.uv.fs_stat(sync_src) == nil,
                    dest_present = vim.uv.fs_stat(sync_dst) ~= nil,
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
        ]=], sync_src, sync_dst, async_src, async_dst, miss_src, miss_dst, async_miss_src, async_miss_dst))

        Assert.eq("sync rename ok", result.sync.ok, true)
        Assert.eq("sync rename err nil", result.sync.err, nil)
        Assert.eq("sync rename errname nil", result.sync.errname, nil)
        Assert.eq("sync rename removed source", result.sync.source_missing, true)
        Assert.eq("sync rename created destination", result.sync.dest_present, true)
        Assert.eq("async rename returns userdata request", result.async.req_type, "userdata")
        Assert.eq("async rename wait succeeds", result.async.wait_ok, true)
        Assert.eq("async rename wait reason", result.async.wait_reason_nil, true)
        Assert.eq("async rename callback err nil", result.async.callback.err, nil)
        Assert.eq("async rename callback ok true", result.async.callback.ok, true)
        Assert.eq("async rename removed source", result.async.callback.source_missing, true)
        Assert.eq("async rename created destination", result.async.callback.dest_present, true)
        Assert.eq("missing rename ok nil", result.missing.ok, nil)
        Assert.truthy(
            "missing rename err text",
            type(result.missing.err) == "string" and result.missing.err ~= "",
            result.missing.err
        )
        Assert.eq("missing rename errname", result.missing.errname, "ENOENT")
        Assert.eq("async missing rename returns userdata request", result.async_missing.req_type, "userdata")
        Assert.eq("async missing rename wait succeeds", result.async_missing.wait_ok, true)
        Assert.eq("async missing rename wait reason", result.async_missing.wait_reason_nil, true)
        Assert.truthy(
            "async missing rename err text",
            type(result.async_missing.callback.err) == "string" and result.async_missing.callback.err ~= "",
            result.async_missing.callback.err
        )
        Assert.eq("async missing rename ok nil", result.async_missing.callback.ok, nil)
    end,
}
