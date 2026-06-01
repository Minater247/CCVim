return {
    id = "runtime.match_functions",
    description = "Checks Vim match-family builtin parity.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "matchend parity", [[
            return {
                vim.fn.matchend("testing", "ing"),
                vim.fn.matchend("testing", "ing", 2),
                vim.fn.matchend("testing", "ing", 5),
                vim.fn.matchend({ "x", "testing" }, "ing"),
            }
        ]])

        Assert.table_eq("matchend results", result, { 7, 7, -1, 1 })
    end,
}
