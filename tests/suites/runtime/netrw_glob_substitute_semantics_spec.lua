return {
    id = "runtime.netrw_glob_substitute_semantics",
    description = "Ports netrw-related glob and substitute semantics against real backend files and Vimscript evaluation.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local function assert_list_eq(label, got, want)
            Assert.eq(label .. " length", #got, #want)
            for i = 1, #got do
                Assert.eq(label .. "[" .. tostring(i) .. "]", got[i], want[i])
            end
        end

        local root = Assert.temp_path(backend, "netrw-glob-subst", "")
        local lua_dir = root .. "/lua"
        Assert.ensure_dir(backend, lua_dir)
        Assert.write_file(backend, root .. "/.gitignore", "")
        Assert.write_file(backend, root .. "/README.md", "")
        Assert.write_file(backend, lua_dir .. "/init.lua", "")

        local result = Assert.eval_block(backend, "netrw glob/substitute semantics", string.format([=[
            local old_cwd = vim.fn.getcwd()
            vim.fn.chdir(%q)

            local ok, rv = pcall(function()
                return {
                    g1 = vim.fn.eval([[glob('./*', 0, 1, 1)]]),
                    g2 = vim.fn.eval([[glob('./.*', 0, 1, 1)]]),
                    g3 = vim.fn.eval([[glob('*', 0, 1, 1)]]),
                    g4 = vim.fn.eval([[glob('.*', 0, 1, 1)]]),
                    simp = vim.fn.eval([[simplify('./*')]]),
                    s1 = vim.fn.eval([[substitute('vim/.gitignore*', "\*$", "", "")]]),
                    s2 = vim.fn.eval([[substitute('vim/.gitignore*', '\*$', "", "")]]),
                    s3 = vim.fn.eval([[substitute('/tmp/codex-netrw/a/b/', '^\(.*\)/\([^/]\+\)/$', '\1', '')]]),
                    s4 = vim.fn.eval([[substitute('/tmp/codex-netrw/a/b/', '^\(.*\)/\([^/]\+\)/$', '\2', '')]]),
                    s5 = vim.fn.eval([[substitute('ab', '\(a\)\(b\)', '\2\1', '')]]),
                    s6 = vim.fn.eval([[substitute('AB', '\(ab\)', '\1', 'i')]]),
                    s7 = vim.fn.eval([[substitute('foo', 'foo', '[\0:&:\&]', '')]]),
                    m1 = vim.fn.eval([[match('vim/.gitignore*', "\*$")]]),
                    m2 = vim.fn.eval([[match('vim/.gitignore*', '\*$')]]),
                }
            end)

            vim.fn.chdir(old_cwd)
            if not ok then
                error(rv)
            end
            return rv
        ]=], root))

        assert_list_eq("glob('./*') stays relative", result.g1, { "./lua", "./README.md" })
        assert_list_eq("glob('./.*') stays relative", result.g2, { "./.", "./..", "./.gitignore" })
        assert_list_eq("glob('*') stays cwd-relative", result.g3, { "lua", "README.md" })
        assert_list_eq("glob('.*') stays cwd-relative", result.g4, { ".", "..", ".gitignore" })
        Assert.eq("simplify('./*') keeps dot prefix", result.simp, "./*")
        Assert.eq("double-quoted pattern keeps backslash", result.s1, "vim/.gitignore")
        Assert.eq("single-quoted pattern works", result.s2, "vim/.gitignore")
        Assert.eq("substitute backref \\1 works", result.s3, "/tmp/codex-netrw/a")
        Assert.eq("substitute backref \\2 works", result.s4, "b")
        Assert.eq("substitute swaps backrefs", result.s5, "ba")
        Assert.eq("substitute backref with ignorecase keeps original case", result.s6, "AB")
        Assert.eq("substitute supports \\0, &, and literal \\&", result.s7, "[foo:foo:&]")
        Assert.eq("double-quoted match works", result.m1, 14)
        Assert.eq("single-quoted match works", result.m2, 14)
    end,
}
