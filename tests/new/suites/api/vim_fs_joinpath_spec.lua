return {
    id = "api.vim_fs_joinpath",
    description = "Covers vim.fs.joinpath normalization and argument coercion behavior.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        if backend.name == "lua_editor" then
            local vimapi = backend:api_build().vim
            Assert.eq("docs example", vimapi.fs.joinpath("foo/", "/bar"), "foo/bar")
            if vimapi.fn.has("win32") == 1 then
                Assert.eq("windows normalize backslashes", vimapi.fs.joinpath("a\\foo\\", "\\bar"), "a/foo/bar")
            else
                local expected = (table.concat({ "a\\foo\\", "\\bar" }, "/"):gsub("//+", "/"))
                Assert.eq("non-windows backslash behavior", vimapi.fs.joinpath("a\\foo\\", "\\bar"), expected)
            end
            Assert.eq("absolute first", vimapi.fs.joinpath("/foo//", "///bar", "baz"), "/foo/bar/baz")
            Assert.eq("root first", vimapi.fs.joinpath("/", "bar"), "/bar")
            Assert.eq("empty first", vimapi.fs.joinpath("", "bar"), "/bar")
            Assert.eq("no args", vimapi.fs.joinpath(), "")
            Assert.eq("numeric coercion", vimapi.fs.joinpath("foo", 12), "foo/12")
            return
        end

        local result, err = backend:eval_lua("vim.fs.joinpath('/foo//', '///bar', 'baz')")
        Assert.truthy("headless eval ok", result ~= nil, err)
        Assert.eq("headless joinpath", result, '"/foo/bar/baz"')
    end,
}
