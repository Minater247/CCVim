return {
    id = "commands.window_navigation",
    description = "Ports directional wincmd movement for unambiguous neighbors plus counted h/l traversal.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "window navigation parity", [[
            local function close_extra_windows()
                local wins = vim.api.nvim_tabpage_list_wins(0)
                local keep = wins[1] or vim.api.nvim_get_current_win()
                vim.api.nvim_set_current_win(keep)
                for i = #wins, 1, -1 do
                    if wins[i] ~= keep then
                        vim.api.nvim_win_close(wins[i], true)
                    end
                end
            end

            local function fill_current_buffer()
                local lines = {}
                for i = 1, 40 do
                    lines[i] = ("line %02d"):format(i)
                end
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            end

            local function reset_layout()
                close_extra_windows()
                vim.cmd("enew!")
                fill_current_buffer()
            end

            local function wincmd(key, count)
                local prefix = count and tostring(count) or ""
                vim.cmd(prefix .. "wincmd " .. key)
            end

            reset_layout()
            vim.o.splitbelow = true
            vim.o.splitright = true

            local top_left = vim.api.nvim_get_current_win()
            vim.cmd("split")
            local bottom_left = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(top_left)
            vim.cmd("vsplit")
            local top_right = vim.api.nvim_get_current_win()
            vim.api.nvim_set_current_win(bottom_left)
            vim.cmd("vsplit")
            local bottom_right = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(top_left)
            wincmd("l")
            local right_from_top_left = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(top_left)
            wincmd("j")
            local down_from_top_left = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(top_right)
            wincmd("j")
            local down_from_top = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(bottom_right)
            wincmd("k")
            local up_from_bottom = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(top_right)
            wincmd("h")
            local left_from_top = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(bottom_right)
            wincmd("h")
            local left_from_bottom_right = vim.api.nvim_get_current_win()

            reset_layout()

            local leftmost = vim.api.nvim_get_current_win()
            vim.cmd("vsplit")
            local middle = vim.api.nvim_get_current_win()
            vim.cmd("vsplit")
            local rightmost = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(rightmost)
            wincmd("h", 2)
            local two_left = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(leftmost)
            wincmd("l", 3)
            local three_right = vim.api.nvim_get_current_win()

            return {
                ids = {
                    top_left = top_left,
                    bottom_left = bottom_left,
                    top_right = top_right,
                    bottom_right = bottom_right,
                    leftmost = leftmost,
                    rightmost = rightmost,
                },
                right_from_top_left = right_from_top_left,
                down_from_top_left = down_from_top_left,
                down_from_top = down_from_top,
                up_from_bottom = up_from_bottom,
                left_from_top = left_from_top,
                left_from_bottom_right = left_from_bottom_right,
                two_left = two_left,
                three_right = three_right,
            }
        ]])

        Assert.eq("wincmd l moves to the window on the right", result.right_from_top_left, result.ids.top_right)
        Assert.eq("wincmd j from top-left moves to the window below", result.down_from_top_left, result.ids.bottom_left)
        Assert.eq("wincmd j from top-right moves to the window below", result.down_from_top, result.ids.bottom_right)
        Assert.eq("wincmd k moves to the window above", result.up_from_bottom, result.ids.top_right)
        Assert.eq("wincmd h from top-right returns to top-left", result.left_from_top, result.ids.top_left)
        Assert.eq("wincmd h from bottom-right returns to bottom-left", result.left_from_bottom_right, result.ids.bottom_left)
        Assert.eq("counted wincmd h traverses multiple windows", result.two_left, result.ids.leftmost)
        Assert.eq("counted wincmd l stops at the last window", result.three_right, result.ids.rightmost)
    end,
}
