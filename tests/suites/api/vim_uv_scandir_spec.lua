return {
    id = "api.vim_uv_scandir",
    description = "Validates libuv-compatible scandir handles, entry types, EOF, and missing-path errors.",

    run = function(ctx)
        local Assert = ctx.assert
        local root = Assert.temp_path(ctx.backend, "vim-uv-scandir", "")
        local subdir = root .. "/sub"
        local file = root .. "/file.txt"
        Assert.ensure_dir(ctx.backend, subdir)
        Assert.write_file(ctx.backend, file, "data")

        local result = Assert.eval_block(ctx.backend, "vim.uv scandir scenarios", string.format([=[
            local root = %q
            local handle, open_err = vim.uv.fs_scandir(root)
            local entries = {}
            while true do
                local name, entry_type = vim.uv.fs_scandir_next(handle)
                if not name then break end
                entries[name] = entry_type
            end
            local eof_name = vim.uv.fs_scandir_next(handle)
            local missing, missing_err = vim.uv.fs_scandir(root .. "/missing")
            local file_handle, file_err = vim.uv.fs_scandir(root .. "/file.txt")

            local callback = {}
            local request = vim.uv.fs_scandir(root, function(err, async_handle)
                callback.err = err
                callback.name, callback.entry_type = vim.uv.fs_scandir_next(async_handle)
            end)

            return {
                open_err = open_err,
                handle_type = type(handle),
                entries = entries,
                eof_is_nil = eof_name == nil,
                missing_is_nil = missing == nil,
                missing_err = missing_err,
                file_is_nil = file_handle == nil,
                file_err = file_err,
                callback = callback,
                request_type = type(request),
            }
        ]=], root))

        Assert.eq("sync scandir has no error", result.open_err, nil)
        Assert.eq("scandir returns userdata handle", result.handle_type, "userdata")
        Assert.eq("directory entry type", result.entries.sub, "directory")
        Assert.eq("file entry type", result.entries["file.txt"], "file")
        Assert.eq("repeated EOF is nil", result.eof_is_nil, true)
        Assert.eq("missing scandir returns nil", result.missing_is_nil, true)
        Assert.truthy("missing scandir reports ENOENT", result.missing_err:find("ENOENT", 1, true) ~= nil)
        Assert.eq("file scandir returns nil", result.file_is_nil, true)
        Assert.truthy("file scandir reports ENOTDIR", result.file_err:find("ENOTDIR", 1, true) ~= nil)
        Assert.eq("async scandir has no error", result.callback.err, nil)
        Assert.truthy("async scandir yields an entry", result.callback.name ~= nil)
        Assert.truthy(
            "async entry has a libuv type",
            result.callback.entry_type == "file" or result.callback.entry_type == "directory"
        )
        Assert.eq("async scandir returns request", result.request_type, "userdata")
    end,
}
