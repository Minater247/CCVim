return {
    id = "runtime.normal_search",
    description = "Checks search navigation, wrap messages, events, counts, register, and jump-list behavior",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "normal search navigation", [[
            local function feed(keys)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
            end

            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "foo",
                "middle foo",
                "tail",
                "foo end",
            })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            feed("/tail<CR>")
            local searched = vim.api.nvim_win_get_cursor(0)
            feed("<C-o>")
            local older = vim.api.nvim_win_get_cursor(0)
            feed("<C-i>")
            local newer = vim.api.nvim_win_get_cursor(0)

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            feed("2/foo<CR>")
            local counted = vim.api.nvim_win_get_cursor(0)
            feed("N")
            local opposite = vim.api.nvim_win_get_cursor(0)

            return {
                searched,
                older,
                newer,
                counted,
                opposite,
                vim.fn.getreg("/"),
                vim.v.searchforward,
            }
        ]])

        ctx.assert.deep_eq("normal search sequence", result, {
            { 3, 0 },
            { 1, 0 },
            { 3, 0 },
            { 4, 0 },
            { 2, 7 },
            "foo",
            1,
        })

        local wrapping = ctx.assert.eval_block(ctx.backend, "search wrap feedback", [[
            local function feed(keys)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
            end

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo", "middle", "foo" })

            local ExMsg = loadModule("lib.excmd.exmsg")
            local original_write = ExMsg._writeWithHL
            local writes = {}
            ExMsg._writeWithHL = function(message, group)
                writes[#writes + 1] = { message, group }
            end

            local events = 0
            vim.api.nvim_create_autocmd("SearchWrapped", {
                callback = function() events = events + 1 end,
            })

            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            feed("/foo<CR>")
            local initial_forward_events = events

            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            feed("n")
            local repeat_forward_events = events

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            feed("?foo<CR>")
            local initial_backward_events = events

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            feed("n")
            local repeat_backward_events = events

            vim.o.shortmess = vim.o.shortmess .. "s"
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            feed("N")
            local suppressed_write_count = #writes
            local suppressed_events = events
            ExMsg._writeWithHL = original_write

            return {
                writes,
                {
                    initial_forward_events,
                    repeat_forward_events,
                    initial_backward_events,
                    repeat_backward_events,
                    suppressed_write_count,
                    suppressed_events,
                },
            }
        ]])

        ctx.assert.deep_eq("search wrap messages", wrapping[1], {
            { "search hit BOTTOM, continuing at TOP", "WarningMsg" },
            { "search hit BOTTOM, continuing at TOP", "WarningMsg" },
            { "search hit TOP, continuing at BOTTOM", "WarningMsg" },
            { "search hit TOP, continuing at BOTTOM", "WarningMsg" },
        })
        ctx.assert.deep_eq("SearchWrapped event timing", wrapping[2], {
            0,
            1,
            1,
            2,
            4,
            3,
        })

        local boundary_errors = ctx.assert.eval_block(ctx.backend, "nowrapscan boundary errors", [[
            local function feed(keys)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
            end

            local ExMsg = loadModule("lib.excmd.exmsg")
            local original_echoerr = ExMsg.echoerr
            local errors = {}
            ExMsg.echoerr = function(message) errors[#errors + 1] = message end
            vim.o.wrapscan = false
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            feed("/foo<CR>")
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            feed("?foo<CR>")
            ExMsg.echoerr = original_echoerr
            return errors
        ]])

        ctx.assert.deep_eq("nowrapscan boundary errors", boundary_errors, {
            "E385: Search hit BOTTOM without match for: foo",
            "E384: Search hit TOP without match for: foo",
        })
    end,
}
