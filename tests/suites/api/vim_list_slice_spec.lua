return {
    id = "api.vim_list_slice",
    description = "Validates vim.list_slice behavior in both backends.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.eval_eq(backend, "vim.list_slice exists", "type(vim.list_slice)", "function")

        local result = Assert.eval(backend, "eval slice 2..3", "vim.list_slice({1,2,3,4}, 2, 3)")
        Assert.table_eq("slice 2..3", result, {2, 3})

        result = Assert.eval(backend, "eval slice start only", "vim.list_slice({1,2,3}, 2)")
        Assert.table_eq("slice start only", result, {2, 3})

        result = Assert.eval(backend, "eval slice finish only", "vim.list_slice({1,2,3}, nil, 2)")
        Assert.table_eq("slice finish only", result, {1, 2})

        result = Assert.eval(backend, "eval slice out of range", "vim.list_slice({1,2,3}, 4, 9)")
        Assert.table_eq("slice out of range", result, {})
    end,
}
