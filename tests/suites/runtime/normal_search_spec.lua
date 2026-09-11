return {
    id = "runtime.normal_search",
    description = "Checks Tutor search, repeat direction, counts, search register, and jump-list navigation",

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
    end,
}
