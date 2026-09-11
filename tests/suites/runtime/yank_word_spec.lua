return {
    id = "runtime.yank_word",
    description = "Checks the vimtutor's documented yw operator and counts against Neovim.",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "yank word", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one two", "three four" })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            vim.cmd("normal! yw")
            local one = { vim.fn.getreg('"'), vim.fn.getregtype('"'), vim.api.nvim_win_get_cursor(0) }

            vim.api.nvim_win_set_cursor(0, { 1, 4 })
            vim.cmd("normal! 2yw")
            local counted = { vim.fn.getreg('"'), vim.fn.getregtype('"'), vim.api.nvim_win_get_cursor(0) }
            return { one, counted }
        ]])

        ctx.assert.deep_eq("yw", result[1], { "one ", "v", { 1, 0 } })
        ctx.assert.deep_eq("counted yw across line", result[2], { "two\nthree ", "v", { 1, 4 } })
    end,
}
