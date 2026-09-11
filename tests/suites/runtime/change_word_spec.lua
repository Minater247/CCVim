return {
    id = "runtime.change_word",
    description = "Checks the vimtutor ce change workflow and undo against Neovim.",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "change to word end", [[
            local line = "This lubw has a few wptfd that mrrf changing usf the change operator."
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
            vim.bo.undolevels = -1
            vim.bo.undolevels = 1000
            vim.api.nvim_win_set_cursor(0, { 1, 6 })

            local keys = vim.api.nvim_replace_termcodes("ceine<Esc>", true, false, true)
            vim.api.nvim_feedkeys(keys, "xt", false)
            local changed = { vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0) }
            vim.api.nvim_feedkeys("u", "xt", false)

            local restored = vim.api.nvim_get_current_line()
            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one ", "two three" })
            vim.api.nvim_win_set_cursor(0, { 1, 3 })
            vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes("ce<Esc>", true, false, true),
                "xt",
                false
            )
            local across_lines = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.api.nvim_win_get_cursor(0),
                vim.fn.getreg(),
                vim.fn.getregtype(),
            }

            return { changed, restored, across_lines }
        ]])

        ctx.assert.deep_eq("ce replaces through word end", result[1], {
            "This line has a few wptfd that mrrf changing usf the change operator.",
            { 1, 8 },
        })
        ctx.assert.eq("ce and inserted text undo together", result[2],
            "This lubw has a few wptfd that mrrf changing usf the change operator.")
        ctx.assert.deep_eq("ce preserves a newline in its characterwise register", result[3], {
            { "one three" },
            { 1, 2 },
            " \ntwo",
            "v",
        })
    end,
}
