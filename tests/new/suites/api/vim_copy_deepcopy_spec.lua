return {
    id = "api.vim_copy_deepcopy",
    description = "Validates vim.copy() and vim.deepcopy() behavior with shallow/deep semantics.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        -- Test vim.copy() shallow semantics
        local result, err = backend:eval_lua(
            "(function() "
            .. "local child = {value=1}; "
            .. "local list = {child, 2}; "
            .. "local copy = vim.fn.copy(list); "
            .. "copy[2] = 99; "
            .. "return {copy ~= list, copy[1].value, list[2], copy[2]} "
            .. "end)()")
        Assert.truthy("eval copy shallow", result ~= nil, err)
        Assert.table_eq("copy shallow", result, {true, 1, 2, 99})

        -- Test vim.deepcopy() with shared references
        result, err = backend:eval_lua(
            "(function() "
            .. "local shared = {n=1}; "
            .. "local src = {shared, shared}; "
            .. "local deep = vim.fn.deepcopy(src); "
            .. "return {deep ~= src, deep[1] ~= shared, deep[1] == deep[2]} "
            .. "end)()")
        Assert.truthy("eval deepcopy shared refs", result ~= nil, err)
        Assert.table_eq("deepcopy duplicates shared refs", result, {true, true, false})

        -- Test vim.deepcopy() isolation and duplication
        result, err = backend:eval_lua(
            "(function() "
            .. "local shared = {n=1}; "
            .. "local src = {shared, shared}; "
            .. "local deep = vim.fn.deepcopy(src); "
            .. "deep[1].n = 9; "
            .. "return {src[1].n, deep[2].n} "
            .. "end)()")
        Assert.truthy("eval deepcopy isolation", result ~= nil, err)
        Assert.table_eq("deepcopy isolates and duplicates", result, {1, 1})

        -- Test vim.deepcopy() noref (duplicate shared references)
        result, err = backend:eval_lua(
            "(function() "
            .. "local shared = {n=1}; "
            .. "local src = {shared, shared}; "
            .. "local deep = vim.fn.deepcopy(src, 1); "
            .. "return deep[1] ~= deep[2] "
            .. "end)()")
        Assert.truthy("eval deepcopy noref", result ~= nil, err)
        Assert.eq("deepcopy noref duplicates", result, true)

        -- Test vim.deepcopy() handles cycles
        result, err = backend:eval_lua(
            "(function() "
            .. "local cycle = {}; "
            .. "cycle[1] = cycle; "
            .. "local copy = vim.fn.deepcopy(cycle); "
            .. "return copy ~= cycle and copy[1] == copy "
            .. "end)()")
        Assert.truthy("eval deepcopy cycle", result ~= nil, err)
        Assert.eq("deepcopy handles cycle", result, true)

        -- Test vim.deepcopy() noref fails on cycle (E698)
        result, err = backend:eval_lua(
            "(function() "
            .. "local cycle = {}; "
            .. "cycle[1] = cycle; "
            .. "local ok, err = pcall(function() vim.fn.deepcopy(cycle, 1) end); "
            .. "return {ok, err and tostring(err):find('E698') ~= nil or false} "
            .. "end)()")
        Assert.truthy("eval deepcopy noref cycle", result ~= nil, err)
        Assert.table_eq("deepcopy noref cycle error", result, {false, true})
    end,
}
