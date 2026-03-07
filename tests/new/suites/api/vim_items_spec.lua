return {
    id = "api.vim_items",
    description = "Validates vim.items() dictionary key-value pair extraction.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        -- Test items() on dictionary
        local result = Assert.eval(backend, "eval items dict", "vim.fn.items({a=1, b=2})")
        Assert.eq("items dict is list", backend:is_list(result), true)
        Assert.eq("items dict count", #result, 2)

        -- Verify pair structure and content (order not guaranteed)
        local found = {}
        for i = 1, #result do
            local pair = result[i]
            Assert.eq("items pair " .. i .. " is list", backend:is_list(pair), true)
            Assert.eq("items pair " .. i .. " length", #pair, 2)
            found[pair[1]] = pair[2]
        end
        Assert.eq("items contains a=1", found.a, 1)
        Assert.eq("items contains b=2", found.b, 2)

        -- Test items() on empty dict
        result = Assert.eval(backend, "eval items empty dict", "vim.fn.items(vim.empty_dict())")
        Assert.eq("items empty dict count", #result, 0)

        -- Test items() on list returns index-value pairs
        result = Assert.eval(backend, "eval items list", "vim.fn.items({10, 20, 30})")
        Assert.eq("items list is list", backend:is_list(result), true)
        Assert.eq("items list count", #result, 3)
        -- Verify index-value pairs (0-indexed in Neovim)
        Assert.table_eq("items list [1]", result[1], {0, 10})
        Assert.table_eq("items list [2]", result[2], {1, 20})
        Assert.table_eq("items list [3]", result[3], {2, 30})

        -- Test items() on number errors with E1225
        Assert.expect_error(backend, "items number emits E1225",
            "vim.fn.items(1)", "E1225")
    end,
}
