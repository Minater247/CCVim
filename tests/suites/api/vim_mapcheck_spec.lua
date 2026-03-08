return {
    id = "api.vim_mapcheck",
    description = "Ports mapcheck() builtin coverage through real mappings instead of command stubs.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "mapcheck scenarios", [[
            vim.cmd("enew!")
            vim.cmd("nnoremap abc rhsabc")
            vim.cmd("inoremap ii insrhs")
            vim.cmd("snoremap ss selrhs")
            vim.cmd("map mm emptymap")
            vim.cmd("nnoremap xx globalrhs")
            vim.cmd("nnoremap <buffer> xx localrhs")
            vim.cmd("nnoremap <S-Up> shiftup")

            return {
                vim.fn.mapcheck("a", "n"),
                vim.fn.mapcheck("abcd", "n"),
                vim.fn.mapcheck("zzz", "n"),
                vim.fn.mapcheck("ii"),
                vim.fn.mapcheck("ii", "i"),
                vim.fn.mapcheck("ss", "v"),
                vim.fn.mapcheck("ss", "x"),
                vim.fn.mapcheck("mm", "n"),
                vim.fn.mapcheck("mm", "x"),
                vim.fn.mapcheck("mm", "s"),
                vim.fn.mapcheck("mm", "o"),
                vim.fn.mapcheck("mm", "i"),
                vim.fn.mapcheck("xx", "n"),
                vim.fn.mapcheck("<S-Up>", "n"),
                vim.fn.mapcheck("xx", "n", 1),
            }
        ]])

        Assert.eq("mapcheck prefix match", result[1], "rhsabc")
        Assert.eq("mapcheck longer prefix match", result[2], "rhsabc")
        Assert.eq("mapcheck miss returns empty", result[3], "")
        Assert.eq("mapcheck default mode excludes insert", result[4], "")
        Assert.eq("mapcheck explicit insert mode", result[5], "insrhs")
        Assert.eq("mapcheck visual includes select", result[6], "selrhs")
        Assert.eq("mapcheck x excludes select-only", result[7], "")
        Assert.eq("mapcheck empty mode normal", result[8], "emptymap")
        Assert.eq("mapcheck empty mode visual", result[9], "emptymap")
        Assert.eq("mapcheck empty mode select", result[10], "emptymap")
        Assert.eq("mapcheck empty mode operator", result[11], "emptymap")
        Assert.eq("mapcheck empty mode excludes insert", result[12], "")
        Assert.eq("mapcheck buffer-local wins", result[13], "localrhs")
        Assert.eq("mapcheck special key names", result[14], "shiftup")
        Assert.eq("mapcheck abbr unsupported returns empty", result[15], "")

        Assert.expect_error_code_block(backend, "mapcheck too many args emits E118", [[
            vim.fn.mapcheck("xx", "n", 0, 1)
        ]], "E118")
    end,
}
