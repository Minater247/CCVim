return {
    id = "api.vim_scope_indexing",
    description = "Ports vim.b, vim.w, and vim.t indexing behavior for current and explicit ids.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim scope indexing scenarios", [[
            vim.cmd("enew!")
            local buf1 = vim.api.nvim_get_current_buf()
            local buf2 = vim.api.nvim_create_buf(true, false)
            local win1 = vim.api.nvim_get_current_win()
            local tab1 = vim.api.nvim_get_current_tabpage()

            vim.b.current_flag = "one"
            vim.b[buf2].other_flag = "two"
            vim.b[0].zero_alias = "cur"

            vim.w.win_flag = "w1"
            vim.w[0].win_zero = "w1z"

            vim.t.tab_flag = "t1"
            vim.t[0].tab_zero = "t1z"

            local ok_b = pcall(function()
                return vim.b[999999].x
            end)
            local ok_w = pcall(function()
                return vim.w[999999].x
            end)
            local ok_t = pcall(function()
                return vim.t[999999].x
            end)

            return {
                buf1,
                buf2,
                win1,
                tab1,
                vim.b.current_flag,
                vim.b[buf2].other_flag,
                vim.b.zero_alias,
                vim.w.win_flag,
                vim.w.win_zero,
                vim.t.tab_flag,
                vim.t.tab_zero,
                ok_b,
                ok_w,
                ok_t,
            }
        ]])

        Assert.truthy("current buffer id is valid", result[1] > 0, result[1])
        Assert.truthy("second buffer id is valid", result[2] > 0, result[2])
        Assert.truthy("current window id is valid", result[3] > 0, result[3])
        Assert.truthy("current tab id is valid", result[4] > 0, result[4])
        Assert.eq("vim.b current buffer write/read", result[5], "one")
        Assert.eq("vim.b[bufnr] write/read", result[6], "two")
        Assert.eq("vim.b[0] aliases current buffer", result[7], "cur")
        Assert.eq("vim.w current window write/read", result[8], "w1")
        Assert.eq("vim.w[0] aliases current window", result[9], "w1z")
        Assert.eq("vim.t current tab write/read", result[10], "t1")
        Assert.eq("vim.t[0] aliases current tab", result[11], "t1z")
        Assert.eq("invalid vim.b[bufnr] errors", result[12], false)
        Assert.eq("invalid vim.w[winid] errors", result[13], false)
        Assert.eq("invalid vim.t[tabnr] errors", result[14], false)
    end,
}
