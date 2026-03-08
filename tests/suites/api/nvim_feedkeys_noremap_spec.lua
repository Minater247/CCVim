return {
    id = "api.nvim_feedkeys_noremap",
    description = "Ports public nvim_feedkeys remap versus noremap behavior for user and builtin normal-mode mappings.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nvim_feedkeys noremap scenarios", [[
            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
            vim.cmd("normal! gg0")
            vim.cmd("nnoremap h iX<Esc>")
            vim.api.nvim_feedkeys("h", "mx", true)
            pcall(vim.cmd, "redraw")
            local remap = vim.api.nvim_get_current_line()

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
            vim.cmd("normal! gg0")
            vim.cmd("nnoremap h iX<Esc>")
            vim.api.nvim_feedkeys("h", "nx", true)
            pcall(vim.cmd, "redraw")
            local noremap = vim.api.nvim_get_current_line()

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc def" })
            vim.cmd("normal! gg0")
            vim.cmd("nnoremap d iX<Esc>")
            vim.api.nvim_feedkeys("dw", "mx", true)
            pcall(vim.cmd, "redraw")
            local operator_remap = vim.api.nvim_get_current_line()

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc def" })
            vim.cmd("normal! gg0")
            vim.cmd("nnoremap d iX<Esc>")
            vim.api.nvim_feedkeys("dw", "nx", true)
            pcall(vim.cmd, "redraw")
            local operator_noremap = vim.api.nvim_get_current_line()

            return { remap, noremap, operator_remap, operator_noremap }
        ]])

        Assert.eq("remap mode applies mapping", result[1], "Xabc")
        Assert.eq("noremap mode bypasses user mapping", result[2], "abc")
        Assert.eq("operator remap applies user mapping", result[3], "Xabc def")
        Assert.eq("operator noremap preserves builtin operator motion", result[4], "def")
    end,
}
