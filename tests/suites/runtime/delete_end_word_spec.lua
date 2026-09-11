return {
    id = "runtime.delete_end_word",
    description = "Checks the documented de word-end delete command against Neovim.",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "delete through word end", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one two three" })
            vim.api.nvim_win_set_cursor(0, { 1, 4 })
            vim.api.nvim_feedkeys("de", "xt", false)
            local single = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0),
                vim.fn.getreg(),
                vim.fn.getregtype(),
            }

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one ", "two three" })
            vim.api.nvim_win_set_cursor(0, { 1, 3 })
            vim.api.nvim_feedkeys("de", "xt", false)
            local across_lines = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.api.nvim_win_get_cursor(0),
                vim.fn.getreg(),
                vim.fn.getregtype(),
            }

            return { single, across_lines }
        ]])

        ctx.assert.deep_eq("de deletes inclusively through the word end", result[1], {
            "one  three",
            { 1, 4 },
            "two",
            "v",
        })
        ctx.assert.deep_eq("de preserves a newline in its characterwise register", result[2], {
            { "one three" },
            { 1, 3 },
            " \ntwo",
            "v",
        })
    end,
}
