return {
    id = "runtime.visual_put",
    description = "Checks Visual put replacement and register behavior against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual put parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset(lines, row, col)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
            end

            reset({ "abcdef" }, 1, 1)
            vim.fn.setreg('"', "XX", "c")
            feed("vllp")
            local charwise_p = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset({ "abcdef" }, 1, 1)
            vim.fn.setreg('"', "XX", "c")
            feed("vllP")
            local charwise_P = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset({ "one", "two", "three" }, 1, 0)
            vim.fn.setreg('"', { "X", "Y" }, "l")
            feed("Vjp")
            local linewise_p = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset({ "abcdef", "uvwxyz", "q" }, 1, 1)
            vim.fn.setreg('"', "XX", "c")
            feed("<C-v>jlp")
            local blockwise_charwise_p = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            return { charwise_p, charwise_P, linewise_p, blockwise_charwise_p }
        ]])

        Assert.deep_eq("characterwise Visual p replaces and saves the selection", result[1], {
            mode = "n",
            cursor = { 1, 2 },
            lines = { "aXXef" },
            register = "bcd",
            register_type = "v",
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.deep_eq("characterwise Visual P preserves the register", result[2], {
            mode = "n",
            cursor = { 1, 2 },
            lines = { "aXXef" },
            register = "XX",
            register_type = "v",
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.deep_eq("linewise Visual p replaces complete selected lines", result[3], {
            mode = "n",
            cursor = { 1, 0 },
            lines = { "X", "Y", "three" },
            register = "one\ntwo\n",
            register_type = "V",
            start = { 0, 1, 1, 0 },
            finish = { 0, 2, 2147483647, 0 },
        })
        Assert.deep_eq("blockwise Visual p applies a characterwise register per row", result[4], {
            mode = "n",
            cursor = { 1, 2 },
            lines = { "aXXdef", "uXXxyz", "q" },
            register = "bc\nvw",
            register_type = string.char(22) .. "2",
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
    end,
}
