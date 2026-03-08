return {
    id = "api.nvim_get_current_line",
    description = "Validates nvim_get_current_line for populated and empty buffers.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "current-line scenarios", [[
            local bufnr = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_set_current_buf(bufnr)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "alpha", "beta", "gamma" })

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            local line1 = vim.api.nvim_get_current_line()

            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            local line3 = vim.api.nvim_get_current_line()

            local empty_buf = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_set_current_buf(empty_buf)
            vim.api.nvim_buf_set_lines(empty_buf, 0, -1, false, {})
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            local empty_line = vim.api.nvim_get_current_line()

            return { line1, line3, empty_line }
        ]])

        Assert.table_eq("nvim_get_current_line results", result, { "alpha", "gamma", "" })
    end,
}
