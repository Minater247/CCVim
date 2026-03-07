return {
    id = "api.vim_fs_joinpath",
    description = "Covers vim.fs.joinpath normalization and argument coercion behavior.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result, err = backend:eval_lua("vim.fs.joinpath('foo/', '/bar')")
        Assert.truthy("eval docs example", result ~= nil, err)
        Assert.eq("docs example", result, "foo/bar")

        local is_win, win_err = backend:eval_lua("vim.fn.has('win32') == 1")
        Assert.truthy("eval win32 flag", is_win ~= nil, win_err)
        result, err = backend:eval_lua("vim.fs.joinpath('a\\\\foo\\\\', '\\\\bar')")
        Assert.truthy("eval backslash case", result ~= nil, err)
        if is_win == true then
            Assert.eq("windows normalize backslashes", result, "a/foo/bar")
        else
            Assert.eq("non-windows backslash behavior", result, "a\\foo\\/\\bar")
        end

        result, err = backend:eval_lua("vim.fs.joinpath('/foo//', '///bar', 'baz')")
        Assert.truthy("eval absolute first", result ~= nil, err)
        Assert.eq("absolute first", result, "/foo/bar/baz")

        result, err = backend:eval_lua("vim.fs.joinpath('/', 'bar')")
        Assert.truthy("eval root first", result ~= nil, err)
        Assert.eq("root first", result, "/bar")

        result, err = backend:eval_lua("vim.fs.joinpath('', 'bar')")
        Assert.truthy("eval empty first", result ~= nil, err)
        Assert.eq("empty first", result, "/bar")

        result, err = backend:eval_lua("vim.fs.joinpath()")
        Assert.truthy("eval no args", result ~= nil, err)
        Assert.eq("no args", result, "")

        result, err = backend:eval_lua("vim.fs.joinpath('foo', 12)")
        Assert.truthy("eval numeric coercion", result ~= nil, err)
        Assert.eq("numeric coercion", result, "foo/12")
    end,
}
