return {
    id = "api.vim_keys",
    description = "Validates vim.keys() dictionary key extraction behavior.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        -- Test keys() on dictionary
        local result, err = backend:eval_lua("vim.fn.keys({a=1, b=2})")
        Assert.truthy("eval keys dict", result ~= nil, err)
        Assert.eq("keys dict is list", backend:is_list(result), true)
        Assert.eq("keys dict count", #result, 2)
        
        -- Check both keys present (order not guaranteed)
        local function contains(tbl, value)
            for i = 1, #tbl do
                if tbl[i] == value then
                    return true
                end
            end
            return false
        end
        Assert.eq("keys contains a", contains(result, "a"), true)
        Assert.eq("keys contains b", contains(result, "b"), true)

        -- Test keys() on empty dict
        result, err = backend:eval_lua("vim.fn.keys(vim.empty_dict())")
        Assert.truthy("eval keys empty dict", result ~= nil, err)
        Assert.eq("keys empty dict count", #result, 0)

        -- Test keys() on list errors with E1206
        result, err = backend:eval_lua(
            "(function() "
            .. "local ok, err = pcall(function() return vim.fn.keys({1, 2}) end); "
            .. "return {ok, err and tostring(err):find('E1206') ~= nil or false} "
            .. "end)()")
        Assert.truthy("eval keys list error", result ~= nil, err)
        Assert.table_eq("keys list emits E1206", result, {false, true})

        -- Test keys() on number errors with E1206
        result, err = backend:eval_lua(
            "(function() "
            .. "local ok, err = pcall(function() return vim.fn.keys(1) end); "
            .. "return {ok, err and tostring(err):find('E1206') ~= nil or false} "
            .. "end)()")
        Assert.truthy("eval keys number error", result ~= nil, err)
        Assert.table_eq("keys number emits E1206", result, {false, true})
    end,
}
