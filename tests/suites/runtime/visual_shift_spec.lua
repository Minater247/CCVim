return {
    id = "runtime.visual_shift",
    description = "Checks Visual line shifting against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual shift parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset()
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "  one", "    two", "three" })
                vim.api.nvim_win_set_cursor(0, { 1, 1 })
                vim.o.shiftwidth = 2
            end

            reset()
            feed("vj2>")
            local shift_right = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("vj<")
            local shift_left = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            return { shift_right, shift_left }
        ]])

        Assert.deep_eq("Visual count > shifts selected lines", result[1], {
            cursor = { 1, 1 },
            lines = { "      one", "\ttwo", "three" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 2, 2, 0 },
        })
        Assert.deep_eq("Visual < shifts selected lines", result[2], {
            cursor = { 1, 1 },
            lines = { "one", "  two", "three" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 2, 2, 0 },
        })
    end,
}
