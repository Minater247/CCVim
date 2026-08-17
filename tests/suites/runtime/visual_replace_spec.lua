return {
    id = "runtime.visual_replace",
    description = "Checks Visual r{char} replacement against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual replacement parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset()
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef", "uvwxyz", "q" })
                vim.api.nvim_win_set_cursor(0, { 1, 1 })
            end

            reset()
            feed("vlrX")
            local charwise = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("VjrX")
            local linewise = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("<C-v>jlrX")
            local blockwise = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            return { charwise, linewise, blockwise }
        ]])

        Assert.deep_eq("characterwise Visual r", result[1], {
            mode = "n",
            cursor = { 1, 1 },
            lines = { "aXXdef", "uvwxyz", "q" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.deep_eq("linewise Visual r", result[2], {
            mode = "n",
            cursor = { 1, 0 },
            lines = { "XXXXXX", "XXXXXX", "q" },
            start = { 0, 1, 1, 0 },
            finish = { 0, 2, 2147483647, 0 },
        })
        Assert.deep_eq("blockwise Visual r", result[3], {
            mode = "n",
            cursor = { 1, 1 },
            lines = { "aXXdef", "uXXxyz", "q" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 2, 3, 0 },
        })
    end,
}
