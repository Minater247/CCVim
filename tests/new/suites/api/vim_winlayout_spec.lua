return {
    id = "api.vim_winlayout",
    description = "Ports winlayout() through real tabpage frame trees for leaf, split, nested split, and invalid-tab cases.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "winlayout scenarios", [[
            local function reset_single_window()
                local wins = vim.api.nvim_tabpage_list_wins(0)
                local keep = wins[1] or vim.api.nvim_get_current_win()
                vim.api.nvim_set_current_win(keep)
                for i = #wins, 1, -1 do
                    local win = wins[i]
                    if win ~= keep then
                        vim.api.nvim_win_close(win, true)
                    end
                end
                vim.cmd("enew!")
            end

            reset_single_window()
            local single_win = vim.api.nvim_get_current_win()
            local single = vim.fn.winlayout()

            reset_single_window()
            local split_base = vim.api.nvim_get_current_win()
            vim.cmd("split")
            local split = vim.fn.winlayout()
            local split_top = vim.api.nvim_get_current_win()

            reset_single_window()
            local nested_base = vim.api.nvim_get_current_win()
            vim.cmd("split")
            local nested_top = vim.api.nvim_get_current_win()
            local nested_bottom = nested_base
            vim.api.nvim_set_current_win(nested_bottom)
            vim.cmd("vsplit")
            local nested = vim.fn.winlayout()
            local nested_left = vim.api.nvim_get_current_win()
            local nested_right = nested_bottom

            local invalid = vim.fn.winlayout(9999)

            return {
                single[1] == "leaf" and single[2] == single_win,
                split[1] == "col"
                    and #split[2] == 2
                    and split[2][1][1] == "leaf"
                    and split[2][1][2] == split_top
                    and split[2][2][1] == "leaf"
                    and split[2][2][2] == split_base,
                nested[1] == "col"
                    and #nested[2] == 2
                    and nested[2][1][1] == "leaf"
                    and nested[2][1][2] == nested_top
                    and nested[2][2][1] == "row"
                    and #nested[2][2][2] == 2
                    and nested[2][2][2][1][1] == "leaf"
                    and nested[2][2][2][1][2] == nested_left
                    and nested[2][2][2][2][1] == "leaf"
                    and nested[2][2][2][2][2] == nested_right,
                type(invalid) == "table" and #invalid == 0,
            }
        ]])

        Assert.eq("single window is a leaf layout", result[1], true)
        Assert.eq("horizontal split forms a col layout", result[2], true)
        Assert.eq("nested vertical split forms row inside col", result[3], true)
        Assert.eq("invalid tabnr returns empty list", result[4], true)

        Assert.expect_error_code_block(backend, "winlayout extra arg emits E118", [[
            vim.fn.winlayout(1, 2)
        ]], "E118")
    end,
}
