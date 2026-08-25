return {
    id = "runtime.help_syntax_fallback",
    description = "Checks that unsupported Treesitter languages do not claim b:ts_highlight in CCVim; lua-editor-only because it asserts CCVim runtime Treesitter state rather than Neovim-visible parity.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "unsupported treesitter language fallback", [[
            vim.bo.filetype = "help"

            local bufnr = vim.api.nvim_get_current_buf()
            local started = vim.treesitter.start(bufnr)
            local active = vim.treesitter.highlighter.active[bufnr]

            return {
                vim.bo[bufnr].filetype,
                started == nil,
                vim.b[bufnr].ts_highlight,
                active ~= nil,
            }
        ]])

        Assert.eq("help filetype", result[1], "help")
        Assert.eq("start() returns nil for unsupported vimdoc backend", result[2], true)
        Assert.eq("unsupported language does not claim TS highlight", result[3], nil)
        Assert.eq("unsupported language does not activate a highlighter", result[4], false)
    end,
}
