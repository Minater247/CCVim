return {
    id = "runtime.cursor_function",
    description = "Checks cursor() line and column zero semantics.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "cursor zero arguments", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def" })
            vim.api.nvim_win_set_cursor(0, { 2, 1 })
            vim.fn.cursor(0, 3)
            local same_line = vim.api.nvim_win_get_cursor(0)
            vim.fn.cursor(1, 0)
            local zero_col = vim.api.nvim_win_get_cursor(0)
            return { same_line, zero_col }
        ]])

        Assert.table_eq("cursor(0, col) keeps current line", result[1], { 2, 2 })
        Assert.table_eq("cursor(line, 0) moves to first column", result[2], { 1, 0 })
    end,
}
