return {
    id = "runtime.netrw_glob_list_concat_regression",
    description = "Ports netrw glob list concatenation behavior against real backend files and Vimscript evaluation.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local root = Assert.temp_path(backend, "netrw-glob-concat", "")
        local lua_dir = root .. "/lua"
        Assert.ensure_dir(backend, lua_dir)
        Assert.write_file(backend, root .. "/.gitignore", "")
        Assert.write_file(backend, root .. "/README.md", "")
        Assert.write_file(backend, lua_dir .. "/init.lua", "")

        local result = Assert.eval_block(backend, "netrw glob list concat regression", string.format([=[
            local old_cwd = vim.fn.getcwd()
            vim.fn.chdir(%q)

            local ok, rv = pcall(function()
                return {
                    filelist = vim.fn.eval([[glob('*', 0, 1, 1)]]),
                    nomatch = vim.fn.eval([[glob('ZZZ_NO_MATCH_*', 0, 1, 1)]]),
                    combo1 = vim.fn.eval([[glob('*', 0, 1, 1) + glob('ZZZ_NO_MATCH_*', 0, 1, 1)]]),
                    combo2 = vim.fn.eval([[glob('ZZZ_NO_MATCH_*', 0, 1, 1) + glob('*', 0, 1, 1)]]),
                    combo3 = vim.fn.eval([[glob('ZZZ_NO_MATCH_*', 0, 1, 1) + glob('ZZZ_NO_MATCH_*', 0, 1, 1)]]),
                }
            end)

            vim.fn.chdir(old_cwd)
            if not ok then
                error(rv)
            end
            return rv
        ]=], root))

        Assert.eq("glob no-match is empty list", #result.nomatch, 0)
        Assert.eq("list + empty preserves len", #result.combo1, #result.filelist)
        Assert.eq("empty + list preserves len", #result.combo2, #result.filelist)
        Assert.eq("empty + empty is empty", #result.combo3, 0)

        for i = 1, #result.filelist do
            Assert.eq(("combo1[%d]"):format(i), result.combo1[i], result.filelist[i])
            Assert.eq(("combo2[%d]"):format(i), result.combo2[i], result.filelist[i])
        end
    end,
}
