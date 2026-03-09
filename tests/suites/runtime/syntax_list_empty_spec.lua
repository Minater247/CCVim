return {
    id = "runtime.syntax_list_empty",
    description = "Matches Neovim behavior for :syntax list on a buffer with no syntax items.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "syntax list on empty buffer", [[
            vim.cmd("enew!")
            return vim.fn.execute("syntax list")
        ]])

        Assert.eq(
            "syntax list without syntax reports empty buffer state",
            result,
            "\nNo Syntax items defined for this buffer"
        )
    end,
}
