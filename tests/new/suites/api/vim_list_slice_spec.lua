return {
    id = "api.vim_list_slice",
    description = "Validates vim.list_slice behavior in both backends.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result, err = backend:eval_lua("type(vim.list_slice)")
        Assert.truthy("eval type(list_slice)", result ~= nil, err)
        Assert.eq("vim.list_slice exists", result, "function")

        result, err = backend:eval_lua("vim.list_slice({1,2,3,4}, 2, 3)")
        Assert.truthy("eval slice 2..3", result ~= nil, err)
        Assert.table_eq("slice 2..3", result, {2, 3})

        result, err = backend:eval_lua("vim.list_slice({1,2,3}, 2)")
        Assert.truthy("eval slice start only", result ~= nil, err)
        Assert.table_eq("slice start only", result, {2, 3})

        result, err = backend:eval_lua("vim.list_slice({1,2,3}, nil, 2)")
        Assert.truthy("eval slice finish only", result ~= nil, err)
        Assert.table_eq("slice finish only", result, {1, 2})

        result, err = backend:eval_lua("vim.list_slice({1,2,3}, 4, 9)")
        Assert.truthy("eval slice out of range", result ~= nil, err)
        Assert.table_eq("slice out of range", result, {})
    end,
}
