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
    end,
}
