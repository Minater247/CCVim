return {
    id = "api.vim_str_index",
    description = "Validates vim.str_utfindex and vim.str_byteindex on ASCII and UTF-16 code unit mode.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        if backend.name == "lua_editor" then
            local api = backend:api_build().vim
            local u32_len, u16_len = api.str_utfindex("abc")
            Assert.eq("legacy utf32 len", u32_len, 3)
            Assert.eq("legacy utf16 len", u16_len, 3)

            local u32_i, u16_i = api.str_utfindex("abc", 2)
            Assert.eq("legacy utf32 idx", u32_i, 2)
            Assert.eq("legacy utf16 idx", u16_i, 2)

            Assert.eq("legacy str_byteindex ascii", api.str_byteindex("abc", 2, false), 2)
            Assert.eq("new str_utfindex utf-8", api.str_utfindex("abc", "utf-8", 2, false), 2)
            Assert.eq("new str_byteindex utf-8", api.str_byteindex("abc", "utf-8", 2, false), 2)
            Assert.eq("utf-16 str_utfindex ascii", api.str_utfindex("abc", "utf-16", 1, false), 1)
            Assert.eq("utf-16 str_byteindex ascii", api.str_byteindex("abc", "utf-16", 1, false), 1)
            Assert.eq("legacy use_utf16 ascii", api.str_byteindex("abc", 1, true), 1)
            return
        end

        local result, err = backend:eval_lua("{vim.str_utfindex('abc', 2), vim.str_byteindex('abc', 2, false)}")
        Assert.truthy("headless eval ok", result ~= nil, err)
        Assert.eq("headless tuple", result, "[2,2]")
    end,
}
