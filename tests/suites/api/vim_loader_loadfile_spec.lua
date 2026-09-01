return {
    id = "api.vim_loader_loadfile",
    description = "Validates safe vim.loader semantics for files created after an enable request.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local cache_file = Assert.temp_path(ctx.backend, "vim-loader-created", ".lua")

        local result = Assert.eval_block(ctx.backend, "vim.loader dynamic loadfile", string.format([=[
            local cache_file = %q
            vim.loader.enable()
            local loader_source = debug.getinfo(loadfile, "S").source

            local before = vim.uv.fs_stat(cache_file)
            local fd = assert(vim.uv.fs_open(cache_file, "w", 438))
            assert(vim.uv.fs_write(fd, "return { version = 12, pkgs = {} }", 0))
            assert(vim.uv.fs_close(fd))

            local after = vim.uv.fs_stat(cache_file)
            local chunk1, err1 = loadfile(cache_file)
            local value1 = chunk1 and chunk1()
            local chunk2, err2 = loadfile(cache_file)
            local value2 = chunk2 and chunk2()
            vim.loader.enable(false)

            return {
                before_nil = before == nil,
                loader_source = loader_source,
                after_type = after and after.type,
                err1 = err1,
                version1 = value1 and value1.version,
                pkgs1 = value1 and #value1.pkgs,
                err2 = err2,
                version2 = value2 and value2.version,
                pkgs2 = value2 and #value2.pkgs,
            }
        ]=], cache_file))

        Assert.eq("file initially missing", result.before_nil, true)
        Assert.truthy(
            "standard-Lua compatibility keeps uncached loadfile",
            result.loader_source:find("lib/luaapi/fileload.lua", 1, true) ~= nil,
            result.loader_source
        )
        Assert.eq("new file stat type", result.after_type, "file")
        Assert.eq("first load has no error", result.err1, nil)
        Assert.eq("first load version", result.version1, 12)
        Assert.eq("first load empty package list", result.pkgs1, 0)
        Assert.eq("cached load has no error", result.err2, nil)
        Assert.eq("cached load version", result.version2, 12)
        Assert.eq("cached load empty package list", result.pkgs2, 0)
    end,
}
