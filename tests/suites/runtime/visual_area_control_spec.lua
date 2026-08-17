return {
    id = "runtime.visual_area_control",
    description = "Checks documented Visual area reselect, endpoint, and count behavior against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual area control parity", [[
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
            feed("vll<Esc>hgv")
            local normal_gv = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
            }
            feed("<Esc>")
            normal_gv.start = vim.fn.getpos("'<")
            normal_gv.finish = vim.fn.getpos("'>")
            normal_gv.visualmode = vim.fn.visualmode()

            reset({ "abcdef" }, 1, 1)
            feed("vll<Esc>hvhgv")
            local visual_gv = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
            }
            feed("<Esc>")
            visual_gv.start = vim.fn.getpos("'<")
            visual_gv.finish = vim.fn.getpos("'>")
            visual_gv.visualmode = vim.fn.visualmode()

            reset({ "abcdef", "uvwxyz" }, 1, 1)
            feed("<C-v>jlO<Esc>")
            local block_other_corner = {
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                visualmode = vim.fn.visualmode(),
            }

            reset({ "01234567890123456789" }, 1, 0)
            feed("vlly")
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            feed("3v")
            local counted_charwise = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
            }
            feed("<Esc>")
            counted_charwise.start = vim.fn.getpos("'<")
            counted_charwise.finish = vim.fn.getpos("'>")

            return {
                normal_gv,
                visual_gv,
                block_other_corner,
                counted_charwise,
            }
        ]])

        Assert.deep_eq("normal gv restores the previous area", result[1], {
            mode = "v",
            cursor = { 1, 3 },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 4, 0 },
            visualmode = "v",
        })
        Assert.deep_eq("Visual gv exchanges areas", result[2], {
            mode = "v",
            cursor = { 1, 3 },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 4, 0 },
            visualmode = "v",
        })
        Assert.deep_eq("block O cursor", result[3].cursor, { 2, 1 })
        Assert.deep_eq("block O moves to the other same-line corner", result[3], {
            cursor = { 2, 1 },
            start = { 0, 1, 3, 0 },
            finish = { 0, 2, 2, 0 },
            visualmode = string.char(22),
        })
        Assert.deep_eq("counted v repeats the completed characterwise area", result[4], {
            mode = "v",
            cursor = { 1, 8 },
            start = { 0, 1, 1, 0 },
            finish = { 0, 1, 9, 0 },
        })
    end,
}
