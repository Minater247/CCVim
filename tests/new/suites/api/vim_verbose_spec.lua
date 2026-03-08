return {
    id = "api.vim_verbose",
    description = "Ports :verbose count handling and restoration of the verbose option.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "verbose command scenarios", [[
            vim.cmd("set verbose=7")
            vim.cmd("2verbose let g:inside_count = &verbose")
            local after_explicit = vim.go.verbose

            vim.cmd("verbose let g:inside_default = &verbose")
            local after_default = vim.go.verbose

            vim.cmd("2verbose set verbose=9")
            local after_inner_set = vim.go.verbose

            return {
                vim.g.inside_count,
                after_explicit,
                vim.g.inside_default,
                after_default,
                after_inner_set,
            }
        ]])

        Assert.eq("inside explicit count", result[1], 2)
        Assert.eq("restore explicit count", result[2], 7)
        Assert.eq("inside default count", result[3], 1)
        Assert.eq("restore default count", result[4], 7)
        Assert.eq("restore after inner set", result[5], 7)
    end,
}
