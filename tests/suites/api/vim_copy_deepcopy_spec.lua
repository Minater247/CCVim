return {
    id = "api.vim_copy_deepcopy",
    description = "Validates vim.copy() and vim.deepcopy() behavior with shallow/deep semantics.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        -- Test vim.copy() shallow semantics
        local result = Assert.eval_block(backend, "eval copy shallow", [[
            local child = {value = 1}
            local list = {child, 2}
            local copy = vim.fn.copy(list)
            copy[2] = 99
            return {copy ~= list, copy[1].value, list[2], copy[2]}
        ]])
        Assert.table_eq("copy shallow", result, {true, 1, 2, 99})

        -- Test vim.deepcopy() with shared references
        result = Assert.eval_block(backend, "eval deepcopy shared refs", [[
            local shared = {n = 1}
            local src = {shared, shared}
            local deep = vim.fn.deepcopy(src)
            return {deep ~= src, deep[1] ~= shared, deep[1] == deep[2]}
        ]])
        Assert.table_eq("deepcopy duplicates shared refs", result, {true, true, false})

        -- Test vim.deepcopy() isolation and duplication
        result = Assert.eval_block(backend, "eval deepcopy isolation", [[
            local shared = {n = 1}
            local src = {shared, shared}
            local deep = vim.fn.deepcopy(src)
            deep[1].n = 9
            return {src[1].n, deep[2].n}
        ]])
        Assert.table_eq("deepcopy isolates and duplicates", result, {1, 1})

        -- Test vim.deepcopy() noref (duplicate shared references)
        result = Assert.eval_block(backend, "eval deepcopy noref", [[
            local shared = {n = 1}
            local src = {shared, shared}
            local deep = vim.fn.deepcopy(src, 1)
            return deep[1] ~= deep[2]
        ]])
        Assert.eq("deepcopy noref duplicates", result, true)

        -- Test vim.deepcopy() handles cycles
        result = Assert.eval_block(backend, "eval deepcopy cycle", [[
            local cycle = {}
            cycle[1] = cycle
            local copy = vim.fn.deepcopy(cycle)
            return copy ~= cycle and copy[1] == copy
        ]])
        Assert.eq("deepcopy handles cycle", result, true)

        -- Test vim.deepcopy() noref fails on cycle (E698)
        Assert.expect_error_code_block(backend, "deepcopy noref cycle error", [[
            local cycle = {}
            cycle[1] = cycle
            vim.fn.deepcopy(cycle, 1)
        ]], "E698")
    end,
}
