return {
    id = "api.vim_islist",
    description = "Checks vim.islist/isarray semantics and empty-dict metatable handling.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result, err = backend:eval_lua("{type(vim.islist), type(vim.isarray), type(vim.tbl_islist)}")
        Assert.truthy("eval function existence", result ~= nil, err)
        Assert.table_eq("function tuple", result, {"function", "function", "function"})

        result, err = backend:eval_lua(
            "{vim.islist({}), vim.islist({'a','b','c'}), "
            .. "vim.islist({[1]='a',[3]='c'}), vim.islist({a=1}), vim.islist('x')}")
        Assert.truthy("eval islist cases", result ~= nil, err)
        Assert.table_eq("islist cases", result, {true, true, false, false, false})

        result, err = backend:eval_lua(
            "{vim.isarray({[2]=true,[5]=true}), vim.isarray({[1]=true,a=true}), "
            .. "vim.tbl_islist({1,2})}")
        Assert.truthy("eval isarray cases", result ~= nil, err)
        Assert.table_eq("isarray cases", result, {true, false, true})

        result, err = backend:eval_lua(
            "(function() vim._empty_dict_mt = {}; local t = setmetatable({}, vim._empty_dict_mt); "
            .. "return {vim.islist(t), vim.isarray(t)} end)()")
        Assert.truthy("eval empty_dict_mt", result ~= nil, err)
        Assert.table_eq("empty_dict_mt handling", result, {false, false})
    end,
}
