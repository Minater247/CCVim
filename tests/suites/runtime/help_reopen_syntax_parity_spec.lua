return {
    id = "runtime.help_reopen_syntax_parity",
    description = "Compares syntax state with Neovim when an existing help window is reused for a second help topic.",
    supports = { lua_editor = false, headless_nvim = false, parity = true },

    run = function(ctx)
        return ctx.assert.eval_block(ctx.backend, "sequential help syntax parity", [[
            vim.cmd("syntax on")

            local function snapshot()
                local pos = vim.api.nvim_win_get_cursor(0)
                local line = vim.api.nvim_get_current_line()
                local groups = {}
                for col = 1, #line do
                    local name = vim.fn.synIDattr(vim.fn.synID(pos[1], col, 0), "name")
                    if name ~= groups[#groups] then groups[#groups + 1] = name end
                end
                return {
                    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"),
                    vim.bo.filetype,
                    vim.bo.syntax,
                    vim.b.current_syntax,
                    pos,
                    line,
                    groups,
                }
            end

            vim.cmd("help")
            local first = snapshot()
            vim.cmd("help Tutor")
            return { first, snapshot() }
        ]])
    end,
}
