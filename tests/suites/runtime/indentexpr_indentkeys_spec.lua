return {
    id = "runtime.indentexpr_indentkeys",
    description = "Ports insert-mode indentexpr and indentkeys behavior against real editor input.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "indentexpr and indentkeys scenarios", [[
            local cr = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
            local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

            vim.cmd("enew!")
            vim.bo.autoindent = false
            vim.bo.indentexpr = "2"
            vim.bo.indentkeys = "o,0=end"
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "if true then" })
            vim.api.nvim_win_set_cursor(0, { 1, #"if true then" })
            vim.api.nvim_feedkeys("A" .. cr .. esc, "xt", false)
            vim.cmd("redraw")
            local newline_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            vim.cmd("enew!")
            vim.bo.autoindent = false
            vim.bo.indentexpr = "0"
            vim.bo.indentkeys = "0=end"
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "    en" })
            vim.api.nvim_win_set_cursor(0, { 1, #"    en" })
            vim.api.nvim_feedkeys("A" .. "d" .. esc, "xt", false)
            vim.cmd("redraw")
            local typed_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            return {
                newline_lines,
                typed_lines,
            }
        ]])

        Assert.table_eq("newline keeps blank second line", result[1], {
            "if true then",
            "",
        })
        Assert.eq("old newline indent expectation is false", result[1][2] == "  ", false)
        Assert.table_eq("typed trigger reindents end", result[2], { "end" })
    end,
}
