return {
    id = "api.vim_hasmapto",
    description = "Ports hasmapto() builtin coverage through real mappings instead of command stubs.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "hasmapto scenarios", [[
            vim.cmd("enew!")
            vim.cmd("nnoremap g <Plug>GlobalTarget")
            vim.cmd("inoremap i InsertOnly")
            vim.cmd("snoremap s SelectOnly")
            vim.cmd("map m MapEmptyMode")
            vim.cmd("nnoremap <buffer> b BufLocalOnly")

            return {
                vim.fn.hasmapto("<Plug>GlobalTarget"),
                vim.fn.hasmapto("InsertOnly"),
                vim.fn.hasmapto("InsertOnly", "i"),
                vim.fn.hasmapto("SelectOnly", "v"),
                vim.fn.hasmapto("SelectOnly", "x"),
                vim.fn.hasmapto("MapEmptyMode", "n"),
                vim.fn.hasmapto("MapEmptyMode", "x"),
                vim.fn.hasmapto("MapEmptyMode", "s"),
                vim.fn.hasmapto("MapEmptyMode", "o"),
                vim.fn.hasmapto("MapEmptyMode", "i"),
                vim.fn.hasmapto("BufLocalOnly", "n"),
                vim.fn.hasmapto("<Plug>GlobalTarget", "n", 1),
            }
        ]])

        Assert.eq("hasmapto default nvo finds normal mapping", result[1], 1)
        Assert.eq("hasmapto default excludes insert", result[2], 0)
        Assert.eq("hasmapto explicit insert mode", result[3], 1)
        Assert.eq("hasmapto visual includes select", result[4], 1)
        Assert.eq("hasmapto x excludes select-only", result[5], 0)
        Assert.eq("hasmapto empty mode normal", result[6], 1)
        Assert.eq("hasmapto empty mode visual", result[7], 1)
        Assert.eq("hasmapto empty mode select", result[8], 1)
        Assert.eq("hasmapto empty mode operator", result[9], 1)
        Assert.eq("hasmapto empty mode excludes insert", result[10], 0)
        Assert.eq("hasmapto buffer-local mapping is searched", result[11], 1)
        Assert.eq("hasmapto abbr mode returns no mapping", result[12], 0)

        Assert.expect_error_code_block(backend, "hasmapto too many args emits E118", [[
            vim.fn.hasmapto("x", "n", 0, 1)
        ]], "E118")
    end,
}
