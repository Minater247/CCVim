return {
    id = "runtime.visual_line_operator",
    description = "Checks whole-line Visual operator variants against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual line operator parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset()
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "bravo", "charlie" })
                vim.api.nvim_win_set_cursor(0, { 1, 1 })
            end

            reset()
            feed("vlD")
            local delete_line = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("vlY")
            local yank_line = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("vlCX<Esc>")
            local change_line = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            return { delete_line, yank_line, change_line }
        ]])

        Assert.deep_eq("Visual D deletes complete selected lines", result[1], {
            mode = "n",
            cursor = { 1, 2 },
            lines = { "bravo", "charlie" },
            register = "alpha\n",
            register_type = "V",
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.deep_eq("Visual Y yanks complete selected lines", result[2], {
            mode = "n",
            cursor = { 1, 0 },
            lines = { "alpha", "bravo", "charlie" },
            register = "alpha\n",
            register_type = "V",
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.deep_eq("Visual C changes complete selected lines", result[3], {
            mode = "n",
            cursor = { 1, 0 },
            lines = { "X", "bravo", "charlie" },
            register = "alpha\n",
            register_type = "V",
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
    end,
}
