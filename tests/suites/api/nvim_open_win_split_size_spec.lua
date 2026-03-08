return {
    id = "api.nvim_open_win_split_size",
    description = "Checks that split windows created through nvim_open_win honor requested width and height.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nvim_open_win split size scenarios", [[
            vim.cmd("enew!")
            local base = vim.api.nvim_get_current_win()

            local left = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "left",
                width = 12,
            })

            local below = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "below",
                height = 5,
            })

            local right = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "right",
                width = 9,
            })

            local above = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "above",
                height = 4,
            })

            return {
                #vim.api.nvim_tabpage_list_wins(0),
                vim.api.nvim_win_get_width(left),
                vim.api.nvim_win_get_height(below),
                vim.api.nvim_win_get_width(right),
                vim.api.nvim_win_get_height(above),
                vim.api.nvim_win_get_width(base) > 0,
                vim.api.nvim_win_get_height(base) > 0,
            }
        ]])

        Assert.eq("split windows created", result[1], 5)
        Assert.eq("left split honors requested width", result[2], 12)
        Assert.eq("below split honors requested height", result[3], 5)
        Assert.eq("right split honors requested width", result[4], 9)
        Assert.eq("above split honors requested height", result[5], 4)
        Assert.eq("base window width stays positive", result[6], true)
        Assert.eq("base window height stays positive", result[7], true)
    end,
}
