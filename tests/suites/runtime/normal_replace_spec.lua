return {
    id = "runtime.normal_replace",
    description = "Checks normal-mode r character replacement, counts, special characters, and undo against Neovim.",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "normal r replacement", [[
            local function feed(keys)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
            end

            local function reset(lines, cursor)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.bo.undolevels = -1
                vim.bo.undolevels = 1000
                vim.api.nvim_win_set_cursor(0, cursor)
            end

            reset({ "abcdef" }, { 1, 1 })
            feed("3rX")
            local counted = { vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0) }
            feed("u")
            local undone = vim.api.nvim_get_current_line()

            reset({ "abc" }, { 1, 1 })
            feed("3rX")
            local past_end = { vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0) }

            reset({ "abcdef" }, { 1, 1 })
            feed("3r<CR>")
            local newline = { vim.api.nvim_buf_get_lines(0, 0, -1, false), vim.api.nvim_win_get_cursor(0) }

            reset({ "abc", "XYZ" }, { 1, 0 })
            feed("2r<C-e>")
            local from_below = { vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(0) }

            reset({ "  abcdef" }, { 1, 3 })
            vim.bo.autoindent = true
            feed("2r<CR>")
            local autoindented = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.api.nvim_win_get_cursor(0),
            }

            return { counted, undone, past_end, newline, from_below, autoindented }
        ]])

        ctx.assert.deep_eq("counted r", result[1], { "aXXXef", { 1, 3 } })
        ctx.assert.eq("r is one undo change", result[2], "abcdef")
        ctx.assert.deep_eq("r count past end", result[3], { "abc", { 1, 1 } })
        ctx.assert.deep_eq("r newline", result[4], { { "a", "ef" }, { 2, 0 } })
        ctx.assert.deep_eq("r control-e", result[5], { "XYc", { 1, 1 } })
        ctx.assert.deep_eq("r newline autoindent", result[6], { { "  a", "  def" }, { 2, 1 } })
    end,
}
