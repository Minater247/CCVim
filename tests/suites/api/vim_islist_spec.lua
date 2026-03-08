return {
    id = "api.vim_islist",
    description = "Checks vim.islist/isarray semantics and empty-dict metatable handling.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval(
            backend,
            "eval function existence",
            "{type(vim.islist), type(vim.isarray), type(vim.tbl_islist)}"
        )
        Assert.table_eq("function tuple", result, {"function", "function", "function"})

        result = Assert.eval(backend, "eval islist cases",
            "{vim.islist({}), vim.islist({'a','b','c'}), "
            .. "vim.islist({[1]='a',[3]='c'}), vim.islist({a=1}), vim.islist('x')}")
        Assert.table_eq("islist cases", result, {true, true, false, false, false})

        result = Assert.eval(backend, "eval isarray cases",
            "{vim.isarray({[2]=true,[5]=true}), vim.isarray({[1]=true,a=true}), "
            .. "vim.tbl_islist({1,2})}")
        Assert.table_eq("isarray cases", result, {true, false, true})

        result = Assert.eval_block(backend, "eval empty_dict_mt", [[
            vim._empty_dict_mt = {}
            local t = setmetatable({}, vim._empty_dict_mt)
            return {vim.islist(t), vim.isarray(t)}
        ]])
        Assert.table_eq("empty_dict_mt handling", result, {false, false})
    end,
}
