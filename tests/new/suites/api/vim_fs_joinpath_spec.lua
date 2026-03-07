return {
    id = "api.vim_fs_joinpath",
    description = "Covers vim.fs.joinpath normalization and argument coercion behavior.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.eval_eq(backend, "docs example", "vim.fs.joinpath('foo/', '/bar')", "foo/bar")

        local is_win = Assert.eval(backend, "eval win32 flag", "vim.fn.has('win32') == 1")
        local result = Assert.eval(backend, "eval backslash case", "vim.fs.joinpath('a\\\\foo\\\\', '\\\\bar')")
        if is_win == true then
            Assert.eq("windows normalize backslashes", result, "a/foo/bar")
        else
            Assert.eq("non-windows backslash behavior", result, "a\\foo\\/\\bar")
        end

        Assert.eval_eq(backend, "absolute first", "vim.fs.joinpath('/foo//', '///bar', 'baz')", "/foo/bar/baz")
        Assert.eval_eq(backend, "root first", "vim.fs.joinpath('/', 'bar')", "/bar")
        Assert.eval_eq(backend, "empty first", "vim.fs.joinpath('', 'bar')", "/bar")
        Assert.eval_eq(backend, "no args", "vim.fs.joinpath()", "")
        Assert.eval_eq(backend, "numeric coercion", "vim.fs.joinpath('foo', 12)", "foo/12")
    end,
}
