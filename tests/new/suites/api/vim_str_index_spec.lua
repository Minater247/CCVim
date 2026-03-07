return {
    id = "api.vim_str_index",
    description = "Validates vim.str_utfindex and vim.str_byteindex on ASCII and UTF-16 code unit mode.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result, err = backend:eval_lua("{vim.str_utfindex('abc', 2), vim.str_byteindex('abc', 2, false)}")
        Assert.truthy("eval baseline tuple", result ~= nil, err)
        Assert.table_eq("baseline tuple", result, {2, 2})

        result, err = backend:eval_lua(
            "{vim.str_byteindex('abc', 2, false), vim.str_utfindex('abc', 'utf-8', 2, false), "
            .. "vim.str_byteindex('abc', 'utf-8', 2, false)}")
        Assert.truthy("eval utf-8 tuple", result ~= nil, err)
        Assert.table_eq("utf-8 tuple", result, {2, 2, 2})

        result, err = backend:eval_lua(
            "{vim.str_utfindex('abc', 'utf-16', 1, false), vim.str_byteindex('abc', 'utf-16', 1, false), "
            .. "vim.str_byteindex('abc', 1, true)}")
        Assert.truthy("eval utf-16 tuple", result ~= nil, err)
        Assert.table_eq("utf-16 tuple", result, {1, 1, 1})
    end,
}
