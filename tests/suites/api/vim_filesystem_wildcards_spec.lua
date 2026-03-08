return {
    id = "api.vim_filesystem_wildcards",
    description = "Ports wildcard expansion behavior for brace and character-class patterns through real glob() calls.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local root = Assert.temp_path(backend, "filesystem-wildcards", "")
        local syntax_dir = root .. "/runtime/syntax"
        local syntax_lua_dir = syntax_dir .. "/lua"
        local ftdetect_dir = root .. "/runtime/ftdetect"

        Assert.ensure_dir(backend, syntax_lua_dir)
        Assert.ensure_dir(backend, ftdetect_dir)
        Assert.write_file(backend, syntax_dir .. "/lua.vim", "\n")
        Assert.write_file(backend, syntax_dir .. "/lua.lua", "\n")
        Assert.write_file(backend, syntax_dir .. "/python.vim", "\n")
        Assert.write_file(backend, syntax_lua_dir .. "/extra.vim", "\n")
        Assert.write_file(backend, syntax_lua_dir .. "/more.lua", "\n")
        Assert.write_file(backend, ftdetect_dir .. "/a.vim", "\n")
        Assert.write_file(backend, ftdetect_dir .. "/b.lua", "\n")

        local result = Assert.eval_block(backend, "filesystem wildcard scenarios", string.format([=[
            local function sorted_glob(pattern)
                local out = vim.fn.glob(pattern, false, true)
                table.sort(out)
                return out
            end

            return {
                sorted_glob(%q),
                sorted_glob(%q),
                sorted_glob(%q),
                sorted_glob(%q),
            }
        ]=],
            root .. "/runtime/syntax/lua[.]{vim,lua}",
            root .. "/runtime/syntax/lua/*.{vim,lua}",
            root .. "/runtime/ftdetect/*.{vim,lua}",
            root .. "/runtime/syntax/[lp]*[.]vim"
        ))

        Assert.table_eq("synload file pattern", result[1], {
            root .. "/runtime/syntax/lua.lua",
            root .. "/runtime/syntax/lua.vim",
        })
        Assert.table_eq("synload dir pattern", result[2], {
            root .. "/runtime/syntax/lua/extra.vim",
            root .. "/runtime/syntax/lua/more.lua",
        })
        Assert.table_eq("ftdetect brace pattern", result[3], {
            root .. "/runtime/ftdetect/a.vim",
            root .. "/runtime/ftdetect/b.lua",
        })
        Assert.table_eq("character class pattern", result[4], {
            root .. "/runtime/syntax/lua.vim",
            root .. "/runtime/syntax/python.vim",
        })
    end,
}
