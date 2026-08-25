return {
    id = "api.lsp_lua_ui_parity",
    description = "Exercises Lua LSP hover and definition through the public buffer UI handlers.",

    run = function(ctx)
        local source = debug.getinfo(1, "S").source:sub(2)
        local root = source:match("^(.*)/tests/suites/api/") or "."
        local server = root .. "/lib/luaapi/lsp_lua.lua"
        local result = ctx.assert.eval_block(ctx.backend, "Lua LSP UI", string.format([[
            vim.cmd("enew!")
            vim.bo.filetype = "lua"
            local bufnr = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_set_name(bufnr, "/tmp/ccvim-lsp-ui.lua")
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                "local apple = 1",
                "print(apple)",
            })
            local lua_lsp = vim.lsp.lua
            if not _G.loadModule then lua_lsp = assert(loadfile(%q))() end
            local id = lua_lsp.start({ bufnr = bufnr })
            assert(vim.wait(500, function()
                local client = vim.lsp.get_client_by_id(id)
                return client and client.initialized
            end, 5))

            vim.api.nvim_win_set_cursor(0, { 2, 1 })
            vim.lsp.buf.hover({ border = "single" })
            local hover_open = vim.wait(500, function() return #vim.api.nvim_list_wins() > 1 end, 5)
            local hover_lines = {}
            for _, win in ipairs(vim.api.nvim_list_wins()) do
                if win ~= vim.api.nvim_get_current_win() then
                    hover_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
                    vim.api.nvim_win_close(win, true)
                end
            end

            vim.api.nvim_win_set_cursor(0, { 2, 8 })
            vim.lsp.buf.definition({ reuse_win = true })
            local jumped = vim.wait(500, function()
                return vim.api.nvim_win_get_cursor(0)[1] == 1
            end, 5)
            vim.lsp.get_client_by_id(id):stop(true)
            return { hover_open = hover_open, hover_lines = hover_lines, jumped = jumped }
        ]], server))

        ctx.assert.eq("Lua hover opens preview", result.hover_open, true)
        ctx.assert.table_eq("Lua hover contents", result.hover_lines, { "`print(...)`", "", "Print values" })
        ctx.assert.eq("Lua definition jumps to declaration", result.jumped, true)
    end,
}
