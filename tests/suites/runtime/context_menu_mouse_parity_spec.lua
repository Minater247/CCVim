return {
    id = "runtime.context_menu_mouse_parity",
    description = "Checks MenuPopup dispatch and the shared menu registry/execution path against native Neovim.",

    run = function(ctx)
        local result, err = ctx.backend:eval_ui_block([[
            vim.cmd("enew! | set mouse=a mousemodel=popup")
            pcall(vim.cmd, "aunmenu CodexContext")
            vim.cmd("amenu 10 CodexContext.Alpha :let g:context_choice = 'alpha'<CR>")
            vim.api.nvim_create_autocmd("MenuPopup", {
                once = true,
                callback = function()
                    vim.g.context_event = vim.api.nvim_get_mode().mode
                end,
            })
            vim.api.nvim_exec_autocmds("MenuPopup", {})
            vim.cmd("emenu CodexContext.Alpha")
        ]], [[
            return { choice = vim.g.context_choice, event = vim.g.context_event,
                visible = vim.fn.pumvisible() }
        ]])

        ctx.assert.eq("context menu input error", err, nil)
        ctx.assert.eq("MenuPopup runs in Normal mode", result.event, "n")
        ctx.assert.eq("context entry uses ordinary :emenu execution", result.choice, "alpha")
        ctx.assert.eq("context menu is closed", result.visible, 0)
    end,
}
