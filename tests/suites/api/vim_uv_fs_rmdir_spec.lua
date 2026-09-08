return {
    id = "api.vim_uv_fs_rmdir",
    description = "Directory removal preserves contents and supports recursive plugin cleanup and callbacks.",
    run = function(ctx)
        local A, b = ctx.assert, ctx.backend
        local root = A.temp_path(b, "rmdir", "")
        A.ensure_dir(b, root .. "/plugin/nested")
        A.ensure_dir(b, root .. "/async")
        A.write_file(b, root .. "/plugin/nested/file", "keep")
        local r = A.eval_block(b, "rmdir", string.format([=[
            local root = %q
            local ok, _, code = vim.uv.fs_rmdir(root .. "/plugin")
            assert(ok == nil and code == "ENOTEMPTY")
            assert(vim.uv.fs_stat(root .. "/plugin/nested/file"))
            local _, _, file_code = vim.uv.fs_rmdir(root .. "/plugin/nested/file")
            assert(file_code == "ENOTDIR")
            local function clean(dir)
                local scan = assert(vim.uv.fs_scandir(dir))
                while true do
                    local name, kind = vim.uv.fs_scandir_next(scan)
                    if not name then break end
                    local path = dir .. "/" .. name
                    if kind == "directory" then clean(path) else assert(vim.uv.fs_unlink(path)) end
                end
                assert(vim.uv.fs_rmdir(dir))
            end
            clean(root .. "/plugin")
            local called
            local req = vim.uv.fs_rmdir(root .. "/async", function(err, success)
                called = {err = err, success = success, fast = vim.in_fast_event()}
            end)
            assert(called == nil, "callback must run asynchronously")
            assert(vim.wait(500, function() return called ~= nil end))
            assert(called.err == nil and called.success == true)
            assert(called.fast == true, "uv callbacks run in a fast event")
            local missing
            vim.uv.fs_rmdir(root .. "/async", function(err, success)
                missing = {err = err, success = success}
            end)
            assert(vim.wait(500, function() return missing ~= nil end))
            assert(missing.err:find("ENOENT") and missing.success == nil)
            local _, _, missing_code = vim.uv.fs_rmdir(root .. "/plugin")
            assert(vim.uv.fs_rmdir(root))
            return {removed = vim.uv.fs_stat(root) == nil, request = type(req), code = missing_code}
        ]=], root))
        A.eq("removed", r.removed, true)
        A.eq("request", r.request, "userdata")
        A.eq("missing", r.code, "ENOENT")
    end,
}
