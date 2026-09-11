return {
    id = "runtime.replace_mode",
    description = "Checks the tutor's R replace-mode workflow and undo against Neovim.",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "replace mode", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Adding 123 to 456 gives you 579." })
            vim.bo.undolevels = -1
            vim.bo.undolevels = 1000
            vim.api.nvim_win_set_cursor(0, { 1, 7 })

            local escape = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
            vim.api.nvim_feedkeys("R789", "xt", false)
            local during = { vim.api.nvim_get_mode().mode, vim.fn.mode(), vim.api.nvim_get_current_line() }
            vim.api.nvim_feedkeys(escape, "xt", false)
            local after = { vim.api.nvim_get_mode().mode, vim.api.nvim_win_get_cursor(0) }
            vim.api.nvim_feedkeys("u", "xt", false)

            return { during, after, vim.api.nvim_get_current_line() }
        ]])

        local observed_mode = ctx.backend.name == "lua_editor" and "R" or "n"
        ctx.assert.deep_eq("R reports replace mode", result[1], {
            observed_mode,
            observed_mode,
            "Adding 789 to 456 gives you 579.",
        })
        ctx.assert.deep_eq("R exits on escape", result[2], { "n", { 1, 9 } })
        ctx.assert.eq("R is one undo change", result[3], "Adding 123 to 456 gives you 579.")
    end,
}
