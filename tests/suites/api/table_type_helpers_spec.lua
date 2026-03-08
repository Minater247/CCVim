return {
    id = "api.table_type_helpers",
    description = "Validates backend table type helper methods (is_list, is_dict, is_empty_dict).",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        -- Test is_list with array
        local result = Assert.eval(backend, "eval array", "{1, 2, 3}")
        Assert.eq("is_list for array", backend:is_list(result), true)
        Assert.eq("is_dict for array", backend:is_dict(result), false)
        Assert.eq("is_empty_dict for array", backend:is_empty_dict(result), false)

        -- Test is_dict with dictionary
        result = Assert.eval(backend, "eval dict", "{a = 1, b = 2}")
        Assert.eq("is_list for dict", backend:is_list(result), false)
        Assert.eq("is_dict for dict", backend:is_dict(result), true)
        Assert.eq("is_empty_dict for dict", backend:is_empty_dict(result), false)

        -- Test is_empty_dict with empty dict (from vim.empty_dict())
        result = Assert.eval(backend, "eval empty_dict", "vim.empty_dict()")
        Assert.eq("is_list for empty_dict", backend:is_list(result), false)
        Assert.eq("is_dict for empty_dict", backend:is_dict(result), true)
        Assert.eq("is_empty_dict for empty_dict", backend:is_empty_dict(result), true)

        -- Test with empty array
        result = Assert.eval(backend, "eval empty array", "{}")
        Assert.eq("is_list for empty array", backend:is_list(result), true)
        Assert.eq("is_dict for empty array", backend:is_dict(result), false)
        Assert.eq("is_empty_dict for empty array", backend:is_empty_dict(result), false)

        -- Test non-table values
        Assert.eq("is_list for number", backend:is_list(42), false)
        Assert.eq("is_dict for string", backend:is_dict("hello"), false)
        Assert.eq("is_empty_dict for nil", backend:is_empty_dict(nil), false)
    end,
}
