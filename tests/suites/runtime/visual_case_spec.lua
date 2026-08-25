return {
    id = "runtime.visual_case",
    description = "Checks Visual case operators against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual case parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset(row, col)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "AbCdEf", "GhIjKl", "MN" })
                vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
            end

            reset(1, 1)
            feed("vlU")
            local charwise_upper = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset(1, 1)
            feed("vlu")
            local charwise_lower = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset(1, 1)
            feed("vl~")
            local charwise_toggle = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset(1, 2)
            feed("VjU")
            local linewise_upper = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset(1, 1)
            feed("<C-v>jlU")
            local blockwise_upper = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            return {
                charwise_upper,
                charwise_lower,
                charwise_toggle,
                linewise_upper,
                blockwise_upper,
            }
        ]])

        Assert.deep_eq("characterwise Visual U", result[1], {
            cursor = { 1, 1 },
            lines = { "ABCdEf", "GhIjKl", "MN" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.deep_eq("characterwise Visual u", result[2], {
            cursor = { 1, 1 },
            lines = { "AbcdEf", "GhIjKl", "MN" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.deep_eq("characterwise Visual ~", result[3], {
            cursor = { 1, 1 },
            lines = { "ABcdEf", "GhIjKl", "MN" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.deep_eq("linewise Visual U", result[4], {
            cursor = { 1, 0 },
            lines = { "ABCDEF", "GHIJKL", "MN" },
            start = { 0, 1, 1, 0 },
            finish = { 0, 2, 2147483647, 0 },
        })
        Assert.deep_eq("blockwise Visual U", result[5], {
            cursor = { 1, 1 },
            lines = { "ABCdEf", "GHIjKl", "MN" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 2, 3, 0 },
        })
    end,
}
