return {
    id = "runtime.netrw_plugin_compiles",
    description = "Loads the bundled netrw opt plugin through packadd and asserts its user commands are registered.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "packadd netrw", [[
            vim.cmd("packadd netrw")
            return {
                vim.fn.exists(":Explore"),
                vim.fn.exists(":Sexplore"),
                vim.fn.exists(":Lexplore"),
                vim.fn.exists(":Nread"),
            }
        ]])

        Assert.table_eq("netrw plugin commands registered", result, { 2, 2, 2, 2 })
    end,
}
