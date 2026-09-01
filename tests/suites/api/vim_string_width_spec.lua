return {
    id = "api.vim_string_width",
    description = "Ports strwidth display-cell behavior for ordinary, tab, and multibyte text.",

    run = function(ctx)
        local Assert = ctx.assert
        local result = Assert.eval_block(ctx.backend, "strwidth scenarios", [[
            return {
                vim.fn.strwidth("lazy"),
                vim.fn.strwidth("a\tb"),
                vim.fn.strwidth("é"),
            }
        ]])

        Assert.table_eq("strwidth display cells", result, { 4, 3, 1 })
    end,
}
