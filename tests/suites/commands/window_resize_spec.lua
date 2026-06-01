return {
    id = "commands.window_resize",
    description = "Ports documented :resize and CTRL-W window-resize behavior, including absolute resize mappings and best-effort clamping.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "window resize parity", [[
            local function close_extra_windows()
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

            local function feed(keys)
                local termcoded = vim.api.nvim_replace_termcodes(keys, true, false, true)
                vim.api.nvim_feedkeys(termcoded, "xt", false)
                pcall(vim.cmd, "redraw")
            end

            close_extra_windows()
            local single_height_before = vim.api.nvim_win_get_height(0)
            vim.cmd("resize 5")
            local single_resize_height = vim.api.nvim_win_get_height(0)
            feed("<C-W>+")
            local single_ctrlw_plus = vim.api.nvim_win_get_height(0)
            feed("<C-W>_")
            local single_ctrlw_underscore = vim.api.nvim_win_get_height(0)

            close_extra_windows()
            vim.cmd("split")
            do
                local wins = vim.api.nvim_tabpage_list_wins(0)
                vim.api.nvim_set_current_win(wins[#wins])
            end
            local split_height_before = vim.api.nvim_win_get_height(0)
            feed("3<C-W>+")
            local split_height_plus = vim.api.nvim_win_get_height(0)
            feed("999<C-W>-")
            local split_height_min = vim.api.nvim_win_get_height(0)
            feed("5<C-W>_")
            local split_height_abs = vim.api.nvim_win_get_height(0)
            feed("<C-W>_")
            local split_height_max = vim.api.nvim_win_get_height(0)

            close_extra_windows()
            local single_width_before = vim.api.nvim_win_get_width(0)
            vim.cmd("vertical resize 30")
            local single_resize_width = vim.api.nvim_win_get_width(0)
            feed("<C-W>|")
            local single_ctrlw_bar = vim.api.nvim_win_get_width(0)

            close_extra_windows()
            vim.cmd("vsplit")
            do
                local wins = vim.api.nvim_tabpage_list_wins(0)
                vim.api.nvim_set_current_win(wins[#wins])
            end
            local split_width_before = vim.api.nvim_win_get_width(0)
            feed("3<C-W>>")
            local split_width_plus = vim.api.nvim_win_get_width(0)
            feed("999<C-W><")
            local split_width_min = vim.api.nvim_win_get_width(0)
            feed("30<C-W>|")
            local split_width_abs = vim.api.nvim_win_get_width(0)
            feed("<C-W>|")
            local split_width_max = vim.api.nvim_win_get_width(0)

            return {
                single_height_before = single_height_before,
                single_resize_height = single_resize_height,
                single_ctrlw_plus = single_ctrlw_plus,
                single_ctrlw_underscore = single_ctrlw_underscore,
                split_height_before = split_height_before,
                split_height_plus = split_height_plus,
                split_height_min = split_height_min,
                split_height_abs = split_height_abs,
                split_height_max = split_height_max,
                single_width_before = single_width_before,
                single_resize_width = single_resize_width,
                single_ctrlw_bar = single_ctrlw_bar,
                split_width_before = split_width_before,
                split_width_plus = split_width_plus,
                split_width_min = split_width_min,
                split_width_abs = split_width_abs,
                split_width_max = split_width_max,
            }
        ]])

        Assert.eq("resize 5 sets single-window height", result.single_resize_height, 5)
        Assert.truthy(
            "CTRL-W + grows a resized single window",
            result.single_ctrlw_plus > result.single_resize_height,
            result
        )
        Assert.truthy(
            "CTRL-W _ restores single-window height toward maximum",
            result.single_ctrlw_underscore > result.single_ctrlw_plus,
            result
        )

        Assert.eq(
            "3 CTRL-W + increases split height by count",
            result.split_height_plus,
            result.split_height_before + 3
        )
        Assert.eq("oversized CTRL-W - clamps at minimum height", result.split_height_min, 1)
        Assert.eq("5 CTRL-W _ sets absolute split height", result.split_height_abs, 5)
        Assert.truthy(
            "bare CTRL-W _ grows split height to the maximum available",
            result.split_height_max > result.split_height_abs,
            result
        )

        Assert.eq(
            "vertical resize does not shrink a single window width",
            result.single_resize_width,
            result.single_width_before
        )
        Assert.eq(
            "CTRL-W | is a no-op on a single full-width window",
            result.single_ctrlw_bar,
            result.single_width_before
        )

        Assert.eq("3 CTRL-W > increases split width by count", result.split_width_plus, result.split_width_before + 3)
        Assert.eq("oversized CTRL-W < clamps at minimum width", result.split_width_min, 1)
        Assert.eq("30 CTRL-W | sets absolute split width", result.split_width_abs, 30)
        Assert.truthy(
            "bare CTRL-W | grows split width to the maximum available",
            result.split_width_max > result.split_width_abs,
            result
        )
    end,
}
