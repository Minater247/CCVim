return {
    id = "runtime.searchpair",
    description = "Checks searchpair() and searchpairpos() parity for nested pairs.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "searchpair nested pairs", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "{", "{", "}", "}" })

            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            local fwd = vim.fn.searchpair("{", "", "}", "W")
            local fwd_cursor = vim.api.nvim_win_get_cursor(0)

            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            local back = vim.fn.searchpair("{", "", "}", "bW")
            local back_cursor = vim.api.nvim_win_get_cursor(0)

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            local outer = vim.fn.searchpair("{", "", "}", "Wr")
            local outer_cursor = vim.api.nvim_win_get_cursor(0)

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            local count = vim.fn.searchpair("{", "", "}", "Wrm")
            local count_cursor = vim.api.nvim_win_get_cursor(0)

            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            local pos = vim.fn.searchpairpos("{", "", "}", "nW")
            local pos_cursor = vim.api.nvim_win_get_cursor(0)

            return {
                fwd,
                fwd_cursor,
                back,
                back_cursor,
                outer,
                outer_cursor,
                count,
                count_cursor,
                pos,
                pos_cursor,
            }
        ]])

        Assert.eq("forward nested pair line", result[1], 3)
        Assert.table_eq("forward nested pair cursor", result[2], { 3, 0 })
        Assert.eq("backward nested pair line", result[3], 2)
        Assert.table_eq("backward nested pair cursor", result[4], { 2, 0 })
        Assert.eq("repeat finds outer pair line", result[5], 4)
        Assert.table_eq("repeat finds outer pair cursor", result[6], { 4, 0 })
        Assert.eq("match count result", result[7], 1)
        Assert.table_eq("match count cursor", result[8], { 4, 0 })
        Assert.table_eq("searchpairpos result", result[9], { 3, 1 })
        Assert.table_eq("searchpairpos n flag leaves cursor", result[10], { 2, 0 })

        local middle = Assert.eval_block(backend, "searchpair middle match", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "if foo", "else", "endif" })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            local rv = vim.fn.searchpair("\\<if\\>", "\\<else\\>", "\\<endif\\>", "W")
            return { rv, vim.api.nvim_win_get_cursor(0) }
        ]])

        Assert.eq("middle match line", middle[1], 2)
        Assert.table_eq("middle match cursor", middle[2], { 2, 0 })
    end,
}
