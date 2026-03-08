return {
    id = "api.vim_keys",
    description = "Validates vim.keys() dictionary key extraction behavior.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        -- Test keys() on dictionary
        local result = Assert.eval(backend, "eval keys dict", "vim.fn.keys({a=1, b=2})")
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
        result = Assert.eval(backend, "eval keys empty dict", "vim.fn.keys(vim.empty_dict())")
        Assert.eq("keys empty dict count", #result, 0)

        -- Test keys() on list errors with E1206
        Assert.expect_error(backend, "keys list emits E1206",
            "vim.fn.keys({1, 2})", "E1206")

        -- Test keys() on number errors with E1206
        Assert.expect_error(backend, "keys number emits E1206",
            "vim.fn.keys(1)", "E1206")
    end,
}
