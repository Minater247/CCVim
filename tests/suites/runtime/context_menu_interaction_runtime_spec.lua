return {
    id = "runtime.context_menu_interaction",
    description = "Exercises CCVim's context renderer from right click through keyboard selection; lua-editor-only because it asserts the terminal context-menu renderer and mouse bridge, which headless Neovim does not expose.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local defaults = ctx.assert.eval_block(ctx.backend, "default context menu", [[
            vim.cmd("runtime lua/vim/_defaults.lua")
            vim.cmd("set mouse=a mousemodel=popup")
            vim.api.nvim_input_mouse("right", "press", "", 0, 2, 4)
            local pos = vim.fn.pum_getpos()
            local visible = vim.fn.pumvisible()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "mt", false)
            return { visible, pos.size }
        ]])
        ctx.assert.eq("default right-click menu visible", defaults[1], 1)
        ctx.assert.truthy("default right-click menu populated", defaults[2] > 0)

        local result = ctx.assert.eval_block(ctx.backend, "context menu interaction", [[
            vim.cmd("enew! | set mouse=a mousemodel=popup")
            pcall(vim.cmd, "aunmenu PopUp")
            vim.cmd("amenu 10 PopUp.Alpha :let g:context_choice = 'alpha'<CR>")
            vim.cmd("amenu 20 PopUp.Beta :let g:context_choice = 'beta'<CR>")
            vim.api.nvim_input_mouse("right", "press", "", 0, 2, 4)
            local before = vim.fn.pumvisible()
            local enter = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
            vim.api.nvim_feedkeys(enter, "mt", false)
            local keyboard = vim.g.context_choice

            vim.api.nvim_input_mouse("right", "press", "", 0, 2, 4)
            local pos = vim.fn.pum_getpos()
            vim.api.nvim_input_mouse("left", "press", "", 0, pos.row + 1, pos.col)
            local mouse = vim.g.context_choice

            vim.cmd("aunmenu PopUp")
            vim.cmd("amenu PopUp.Tools.Nested :let g:context_choice = 'nested'<CR>")
            vim.api.nvim_input_mouse("right", "press", "", 0, 2, 4)
            local descend = vim.api.nvim_replace_termcodes("<Right><CR>", true, false, true)
            vim.api.nvim_feedkeys(descend, "mt", false)
            local nested = vim.g.context_choice

            vim.cmd("aunmenu PopUp")
            vim.api.nvim_create_autocmd("MenuPopup", {
                once = true,
                callback = function()
                    vim.cmd("amenu PopUp.Dynamic :let g:context_choice = 'dynamic'<CR>")
                end,
            })
            vim.api.nvim_input_mouse("right", "press", "", 0, 2, 4)
            vim.api.nvim_feedkeys(enter, "mt", false)
            return { before, vim.fn.pumvisible(), keyboard, mouse, nested, vim.g.context_choice }
        ]])

        ctx.assert.table_eq(
            "right-click selection lifecycle",
            result,
            { 1, 0, "alpha", "beta", "nested", "dynamic" }
        )
    end,
}
