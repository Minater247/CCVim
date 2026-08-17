return {
    id = "runtime.visual_text_object",
    description = "Checks Visual word text objects against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual text object parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset()
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one two-three  four" })
                vim.api.nvim_win_set_cursor(0, { 1, 5 })
            end

            reset()
            feed("viwy")
            local inner_word = {
                cursor = vim.api.nvim_win_get_cursor(0),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("vawy")
            local around_word = {
                cursor = vim.api.nvim_win_get_cursor(0),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("viWy")
            local inner_WORD = {
                cursor = vim.api.nvim_win_get_cursor(0),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("vaWy")
            local around_WORD = {
                cursor = vim.api.nvim_win_get_cursor(0),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a (one (two) three) z [left [right] end]" })
            vim.api.nvim_win_set_cursor(0, { 1, 10 })
            feed("viby")
            local inner_parens = {
                cursor = vim.api.nvim_win_get_cursor(0),
                register = vim.fn.getreg('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a (one (two) three) z [left [right] end]" })
            vim.api.nvim_win_set_cursor(0, { 1, 10 })
            feed("vaby")
            local around_parens = {
                cursor = vim.api.nvim_win_get_cursor(0),
                register = vim.fn.getreg('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a (one (two) three) z [left [right] end]" })
            vim.api.nvim_win_set_cursor(0, { 1, 32 })
            feed("vi[y")
            local inner_brackets = {
                cursor = vim.api.nvim_win_get_cursor(0),
                register = vim.fn.getreg('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a (one (two) three) z [left [right] end]" })
            vim.api.nvim_win_set_cursor(0, { 1, 32 })
            feed("va[y")
            local around_brackets = {
                cursor = vim.api.nvim_win_get_cursor(0),
                register = vim.fn.getreg('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            return {
                inner_word,
                around_word,
                inner_WORD,
                around_WORD,
                inner_parens,
                around_parens,
                inner_brackets,
                around_brackets,
            }
        ]])

        Assert.deep_eq("Visual iw", result[1], {
            cursor = { 1, 4 },
            register = "two",
            register_type = "v",
            start = { 0, 1, 5, 0 },
            finish = { 0, 1, 7, 0 },
        })
        Assert.deep_eq("Visual aw", result[2], {
            cursor = { 1, 3 },
            register = " two",
            register_type = "v",
            start = { 0, 1, 4, 0 },
            finish = { 0, 1, 7, 0 },
        })
        Assert.deep_eq("Visual iW", result[3], {
            cursor = { 1, 4 },
            register = "two-three",
            register_type = "v",
            start = { 0, 1, 5, 0 },
            finish = { 0, 1, 13, 0 },
        })
        Assert.deep_eq("Visual aW", result[4], {
            cursor = { 1, 4 },
            register = "two-three  ",
            register_type = "v",
            start = { 0, 1, 5, 0 },
            finish = { 0, 1, 15, 0 },
        })
        Assert.deep_eq("Visual ib", result[5], {
            cursor = { 1, 8 },
            register = "two",
            start = { 0, 1, 9, 0 },
            finish = { 0, 1, 11, 0 },
        })
        Assert.deep_eq("Visual ab", result[6], {
            cursor = { 1, 7 },
            register = "(two)",
            start = { 0, 1, 8, 0 },
            finish = { 0, 1, 12, 0 },
        })
        Assert.deep_eq("Visual i[", result[7], {
            cursor = { 1, 29 },
            register = "right",
            start = { 0, 1, 30, 0 },
            finish = { 0, 1, 34, 0 },
        })
        Assert.deep_eq("Visual a[", result[8], {
            cursor = { 1, 28 },
            register = "[right]",
            start = { 0, 1, 29, 0 },
            finish = { 0, 1, 35, 0 },
        })
    end,
}
