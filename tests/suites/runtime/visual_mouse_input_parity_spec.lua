return {
    id = "runtime.visual_mouse_input",
    description = "Verifies Shift-click characterwise selection through the public mouse-input API against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result, err = backend:eval_ui_block([[
            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
            vim.o.mouse = "nvi"
            vim.o.mousemodel = "popup"
            vim.api.nvim_win_set_cursor(0, { 1, 2 })
            vim.api.nvim_input_mouse("left", "press", "S", 0, 0, 4)
        ]], [[
            return {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
            }
        ]])

        Assert.eq("Shift-click parity error", err, nil)
        Assert.eq("Shift-click enters Visual mode", result.mode, "v")
        Assert.table_eq("Shift-click cursor", result.cursor, { 1, 4 })

        local select_result, select_err = backend:eval_ui_block([[
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "xt", false)
            vim.cmd("enew! | set mouse=nvi mousemodel=popup selectmode=mouse")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
            vim.api.nvim_win_set_cursor(0, { 1, 2 })
            vim.api.nvim_input_mouse("left", "press", "S", 0, 0, 4)
        ]], [[
            return {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
            }
        ]])

        Assert.eq("Select-mode mouse parity error", select_err, nil)
        Assert.eq("selectmode=mouse enters Select mode", select_result.mode, "s")
        Assert.table_eq("Select-mode Shift-click cursor", select_result.cursor, { 1, 4 })
    end,
}
