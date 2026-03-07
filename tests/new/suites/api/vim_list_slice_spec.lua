return {
    id = "api.vim_list_slice",
    description = "Validates vim.list_slice behavior in both backends.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        if backend.name == "lua_editor" then
            local api = backend:api_build().vim
            Assert.truthy("vim.list_slice exists", type(api.list_slice) == "function", type(api.list_slice))
            Assert.table_eq("slice 2..3", api.list_slice({ 1, 2, 3, 4 }, 2, 3), { 2, 3 })
            Assert.table_eq("slice start only", api.list_slice({ 1, 2, 3 }, 2), { 2, 3 })
            Assert.table_eq("slice finish only", api.list_slice({ 1, 2, 3 }, nil, 2), { 1, 2 })
            Assert.table_eq("slice out of range", api.list_slice({ 1, 2, 3 }, 4, 9), {})
            return
        end

        local result, err = backend:eval_lua("vim.list_slice({1,2,3,4}, 2, 3)")
        Assert.truthy("headless eval ok", result ~= nil, err)
        Assert.eq("headless list_slice result", result, "[2,3]")
    end,
}
