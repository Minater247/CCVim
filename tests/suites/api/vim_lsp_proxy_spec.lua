return {
    id = "api.vim_lsp_proxy",
    description = "Ports vim._defer_require and lazy vim.lsp materialization through the public Lua API.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.lsp proxy scenarios", [[
            local before = rawget(vim, "lsp")
            local defer_type = type(vim._defer_require)

            local lsp = vim.lsp
            local after = rawget(vim, "lsp")
            local util = lsp.util

            return {
                defer_type,
                before == nil,
                type(lsp),
                after == lsp,
                type(util),
                type(util.apply_text_edits),
                type(lsp.get_clients),
            }
        ]])

        Assert.eq("vim._defer_require exists", result[1], "function")
        Assert.eq("vim.lsp not materialized before access", result[2], true)
        Assert.eq("vim.lsp resolves to table", result[3], "table")
        Assert.eq("vim.lsp is cached after access", result[4], true)
        Assert.eq("vim.lsp.util resolves to table", result[5], "table")
        Assert.eq("vim.lsp.util.apply_text_edits is callable", result[6], "function")
        Assert.eq("vim.lsp.get_clients is callable", result[7], "function")
    end,
}
