return {
    id = "runtime.buffer_switch_cursor",
    description = "Checks that switching to a shorter buffer clamps the cursor before buffer callbacks use it",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "buffer switch cursor clamp", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "1", "2", "3", "4", "5" })
            vim.api.nvim_win_set_cursor(0, { 5, 0 })

            local direct = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_win_set_buf(0, direct)
            local direct_cursor = vim.api.nvim_win_get_cursor(0)
            local direct_line = vim.api.nvim_buf_get_lines(
                direct,
                direct_cursor[1] - 1,
                direct_cursor[1],
                true
            )[1]

            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "1", "2", "3", "4", "5" })
            vim.api.nvim_win_set_cursor(0, { 5, 0 })
            vim.cmd("enew!")
            local command_cursor = vim.api.nvim_win_get_cursor(0)
            local command_line = vim.api.nvim_buf_get_lines(
                0,
                command_cursor[1] - 1,
                command_cursor[1],
                true
            )[1]

            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "1", "2", "3", "4", "5" })
            vim.api.nvim_win_set_cursor(0, { 5, 0 })
            vim.api.nvim_buf_set_lines(0, 0, 2, false, {})
            local delete_above = vim.api.nvim_win_get_cursor(0)

            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "1", "2", "3", "4", "5" })
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            vim.api.nvim_buf_set_lines(0, 1, 4, false, {})
            local delete_containing = vim.api.nvim_win_get_cursor(0)

            return {
                direct_cursor,
                direct_line,
                command_cursor,
                command_line,
                delete_above,
                delete_containing,
            }
        ]])

        ctx.assert.deep_eq("short buffer cursor and strict row access", result, {
            { 1, 0 },
            "",
            { 1, 0 },
            "",
            { 3, 0 },
            { 2, 0 },
        })
    end,
}
