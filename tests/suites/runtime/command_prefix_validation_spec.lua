return {
    id = "runtime.command_prefix_validation",
    description = "Validates central count/range handling for commands that allow count, allow line ranges, or allow neither.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "command prefix validation", [[
            local suffix = 0

            local function reset_single_window()
                local wins = vim.api.nvim_tabpage_list_wins(0)
                local keep = wins[1] or vim.api.nvim_get_current_win()
                vim.api.nvim_set_current_win(keep)
                for i = #wins, 1, -1 do
                    if wins[i] ~= keep then
                        vim.api.nvim_win_close(wins[i], true)
                    end
                end
                vim.cmd("enew!")
            end

            local function set_three_windows()
                suffix = suffix + 1
                local tag = tostring(suffix)
                reset_single_window()
                vim.cmd("file prefix_one_" .. tag)
                vim.cmd("split")
                vim.cmd("enew!")
                vim.cmd("file prefix_two_" .. tag)
                vim.cmd("split")
                vim.cmd("enew!")
                vim.cmd("file prefix_three_" .. tag)
                vim.cmd("1wincmd w")
            end

            local function win_names()
                local out = {}
                local wins = vim.api.nvim_tabpage_list_wins(0)
                for i = 1, #wins do
                    out[i] = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(wins[i]))
                end
                return out
            end

            local echo_count_ok, echo_count_err = pcall(vim.cmd, '2echo "x"')
            local echo_range_ok, echo_range_err = pcall(vim.cmd, '1,2echo "x"')

            set_three_windows()
            local close_before = win_names()
            vim.cmd("2close")
            local close_after = win_names()
            local close_current = vim.fn.winnr()

            set_three_windows()
            local close_range_before = win_names()
            local close_range_ok, close_range_err = pcall(vim.cmd, "1,2close")
            local close_range_after = win_names()
            local close_range_current = vim.fn.winnr()

            return {
                echo_count_ok,
                tostring(echo_count_err or ""),
                echo_range_ok,
                tostring(echo_range_err or ""),
                close_before,
                close_after,
                close_current,
                close_range_before,
                close_range_ok,
                tostring(close_range_err or ""),
                close_range_after,
                close_range_current,
            }
        ]])

        Assert.eq("echo rejects count prefix", result[1], false)
        Assert.top_error_code("echo count prefix uses E481", result[2], "E481")
        Assert.eq("echo rejects line range prefix", result[3], false)
        Assert.top_error_code("echo range prefix uses E481", result[4], "E481")
        Assert.eq("counted close starts with three windows", #result[5], 3)
        Assert.eq("counted close leaves two windows", #result[6], 2)
        Assert.eq("counted close keeps current window", result[7], 1)
        Assert.eq("counted close keeps first window", result[6][1], result[5][1])
        Assert.eq("counted close drops second window", result[6][2], result[5][3])
        Assert.eq("close range prefix starts with three windows", #result[8], 3)
        Assert.eq("close range prefix succeeds", result[9], true)
        Assert.eq("close range prefix leaves empty error", result[10], "")
        Assert.eq("close range prefix leaves two windows", #result[11], 2)
        Assert.eq("close range prefix keeps current window", result[12], 1)
        Assert.eq("close range prefix keeps first window", result[11][1], result[8][1])
        Assert.eq("close range prefix drops second window", result[11][2], result[8][3])
    end,
}
