return {
    id = "runtime.normal_percent",
    description = "Checks percent motions across lines, special pairs, counts, options, and the jump list",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "normal percent motions", [[
            local function feed(keys)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
            end

            local function reset(lines, cursor)
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, cursor)
            end

            local default_matchpairs = vim.bo.matchpairs

            reset({ "prefix ( outer", "middle { inner }", "suffix )" }, { 1, 0 })
            feed("%")
            local multiline = vim.api.nvim_win_get_cursor(0)
            feed("<C-o>")
            local jump_back = vim.api.nvim_win_get_cursor(0)

            reset({ "x /* one", "two */ y" }, { 1, 2 })
            feed("%")
            local comment = vim.api.nvim_win_get_cursor(0)

            reset({ "#if A", "x", "#else", "y", "#endif" }, { 1, 0 })
            feed("%")
            local preprocessor_middle = vim.api.nvim_win_get_cursor(0)
            feed("%")
            local preprocessor_end = vim.api.nvim_win_get_cursor(0)
            feed("%")
            local preprocessor_start = vim.api.nvim_win_get_cursor(0)

            reset({ "one", "two", "three", "four", "five" }, { 1, 0 })
            feed("40%")
            local percentage = vim.api.nvim_win_get_cursor(0)

            reset({ 'x "(" ( y', "z )" }, { 1, 0 })
            feed("%")
            local quoted = vim.api.nvim_win_get_cursor(0)

            reset({ "( \\) )" }, { 1, 0 })
            feed("%")
            local escaped = vim.api.nvim_win_get_cursor(0)

            reset({ '"("', ")" }, { 1, 1 })
            feed("%")
            local uneven_quotes = vim.api.nvim_win_get_cursor(0)

            vim.bo.matchpairs = "<:>"
            reset({ "before <", "inside", "> after" }, { 1, 0 })
            feed("%")
            local custom = vim.api.nvim_win_get_cursor(0)

            vim.bo.matchpairs = default_matchpairs
            reset({ "prefix ( outer", "suffix )" }, { 1, 0 })
            local Event = loadModule("lib.event")
            local Decoration = loadModule("lib.decoration")
            local capture_extmark_positions = Decoration.capture_extmark_positions
            local extmark_capture_count = 0
            Decoration.capture_extmark_positions = function(...)
                extmark_capture_count = extmark_capture_count + 1
                return capture_extmark_positions(...)
            end
            local function press_physical_percent()
                Event.ProcessEvent({ "key", keys.leftShift, false })
                Event.ProcessEvent({ "key", keys.five, false })
                Event.ProcessEvent({ "char", "%" })
                Event.ProcessEvent({ "key_up", keys.leftShift })
                Event.ProcessEvent({ "key_up", keys.five })
            end
            press_physical_percent()
            local physical_percent_forward = vim.api.nvim_win_get_cursor(0)
            press_physical_percent()
            Decoration.capture_extmark_positions = capture_extmark_positions
            local physical_percent_backward = vim.api.nvim_win_get_cursor(0)

            return {
                default_matchpairs,
                multiline,
                jump_back,
                comment,
                preprocessor_middle,
                preprocessor_end,
                preprocessor_start,
                percentage,
                quoted,
                escaped,
                uneven_quotes,
                custom,
                physical_percent_forward,
                physical_percent_backward,
                extmark_capture_count,
            }
        ]])

        ctx.assert.deep_eq("normal percent motions", result, {
            "(:),{:},[:]",
            { 3, 7 },
            { 1, 0 },
            { 2, 5 },
            { 3, 0 },
            { 5, 0 },
            { 1, 0 },
            { 2, 0 },
            { 2, 2 },
            { 1, 5 },
            { 2, 0 },
            { 3, 0 },
            { 2, 7 },
            { 1, 7 },
            0,
        })
    end,
}
