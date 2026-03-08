return {
    id = "runtime.copy_move",
    description = "Ports copy/move Ex command behavior for ranges, aliases, cursor updates, no-ops, and errors.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "copy and move scenarios", [[
            local function set_lines(lines, cursor_line)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { cursor_line or 1, 0 })
            end

            local function lines()
                return vim.api.nvim_buf_get_lines(0, 0, -1, false)
            end

            set_lines({ "1", "2", "3", "4", "5", "6" }, 1)
            vim.cmd("2,3copy 5")
            local copy_lines = lines()
            local copy_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "1", "2", "3", "4", "5", "6" }, 1)
            vim.cmd("2,3t 5")
            local t_lines = lines()
            local t_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "1", "2", "3" }, 2)
            vim.cmd("copy 0")
            local copy_default_lines = lines()
            local copy_default_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "1", "2", "3", "4", "5", "6" }, 1)
            vim.cmd("2,3move 5")
            local move_down_lines = lines()
            local move_down_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "1", "2", "3", "4", "5", "6" }, 1)
            vim.cmd("4,5move 1")
            local move_up_lines = lines()
            local move_up_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "1", "2", "3", "4", "5", "6" }, 1)
            vim.cmd("2,4move 1")
            local move_before_lines = lines()
            local move_before_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "1", "2", "3", "4", "5", "6" }, 1)
            vim.cmd("2,4move 4")
            local move_end_lines = lines()
            local move_end_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "1", "2", "3", "4", "5", "6" }, 1)
            local inside_ok, inside_err = pcall(vim.cmd, "2,4move 3")
            local move_inside_lines = lines()
            local move_inside_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "1", "2", "3" }, 1)
            local copy_missing_ok, copy_missing_err = pcall(vim.cmd, "copy")

            set_lines({ "1", "2", "3" }, 1)
            local move_missing_ok, move_missing_err = pcall(vim.cmd, "move")

            set_lines({ "1", "2", "3" }, 1)
            local copy_bad_ok, copy_bad_err = pcall(vim.cmd, "2copy 99")

            return {
                copy_lines,
                copy_cursor,
                t_lines,
                t_cursor,
                copy_default_lines,
                copy_default_cursor,
                move_down_lines,
                move_down_cursor,
                move_up_lines,
                move_up_cursor,
                move_before_lines,
                move_before_cursor,
                move_end_lines,
                move_end_cursor,
                inside_ok,
                tostring(inside_err or ""),
                move_inside_lines,
                move_inside_cursor,
                copy_missing_ok,
                tostring(copy_missing_err or ""),
                move_missing_ok,
                tostring(move_missing_err or ""),
                copy_bad_ok,
                tostring(copy_bad_err or ""),
            }
        ]])

        Assert.table_eq("copy range inserts below destination", result[1], { "1", "2", "3", "4", "5", "2", "3", "6" })
        Assert.table_eq("copy moves cursor to last copied line", result[2], { 7, 0 })
        Assert.table_eq("t alias matches copy behavior", result[3], { "1", "2", "3", "4", "5", "2", "3", "6" })
        Assert.table_eq("t alias moves cursor to last copied line", result[4], { 7, 0 })
        Assert.table_eq("copy default range uses current line", result[5], { "2", "1", "2", "3" })
        Assert.table_eq("copy default updates cursor to inserted line", result[6], { 1, 0 })
        Assert.table_eq("move down inserts block below destination", result[7], { "1", "4", "5", "2", "3", "6" })
        Assert.table_eq("move down puts cursor on last moved line", result[8], { 5, 0 })
        Assert.table_eq("move up inserts block near top", result[9], { "1", "4", "5", "2", "3", "6" })
        Assert.table_eq("move up puts cursor on last moved line", result[10], { 3, 0 })
        Assert.table_eq("move to range start-1 is no-op", result[11], { "1", "2", "3", "4", "5", "6" })
        Assert.table_eq("move to range start-1 leaves cursor on range end", result[12], { 4, 0 })
        Assert.table_eq("move to range end is no-op", result[13], { "1", "2", "3", "4", "5", "6" })
        Assert.table_eq("move to range end leaves cursor on range end", result[14], { 4, 0 })
        Assert.eq("move inside range fails", result[15], false)
        Assert.top_error_code("move inside range uses E134", result[16], "E134")
        Assert.table_eq("move inside range keeps buffer unchanged", result[17], { "1", "2", "3", "4", "5", "6" })
        Assert.table_eq("move inside range keeps cursor", result[18], { 1, 0 })
        Assert.eq("copy missing destination fails", result[19], false)
        Assert.top_error_code("copy missing destination uses E16", result[20], "E16")
        Assert.eq("move missing destination fails", result[21], false)
        Assert.top_error_code("move missing destination uses E16", result[22], "E16")
        Assert.eq("copy out-of-range destination fails", result[23], false)
        Assert.top_error_code("copy out-of-range destination uses E16", result[24], "E16")
    end,
}
