return {
    id = "api.treesitter_language_version_getters",
    description = "Ports treesitter language version getter exposure through the public vim and vim.treesitter APIs.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "treesitter language version getters", [[
            local ts = (vim.require and vim.require("vim.treesitter")) or require("vim.treesitter")
            return {
                type(vim._ts_get_language_version),
                type(vim._ts_get_minimum_language_version),
                type(vim._ts_get_language_version()),
                type(vim._ts_get_minimum_language_version()),
                vim._ts_get_minimum_language_version() <= vim._ts_get_language_version(),
                ts.language_version == vim._ts_get_language_version(),
                ts.minimum_language_version == vim._ts_get_minimum_language_version(),
            }
        ]])

        Assert.table_eq("getter shapes and values", result, {
            "function",
            "function",
            "number",
            "number",
            true,
            true,
            true,
        })
    end,
}
