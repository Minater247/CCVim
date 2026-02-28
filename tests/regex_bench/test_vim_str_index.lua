local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local mock = MockEnv.setup({ ccvim_path = "vim" })
local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local api = ApiBuild.Build()

assert_true("vim.str_utfindex exists", type(api.vim.str_utfindex) == "function", type(api.vim.str_utfindex))
assert_true("vim.str_byteindex exists", type(api.vim.str_byteindex) == "function", type(api.vim.str_byteindex))

local u32_len, u16_len = api.vim.str_utfindex("abc")
assert_eq("legacy str_utfindex utf32 len", u32_len, 3)
assert_eq("legacy str_utfindex utf16 len", u16_len, 3)

local u32_i, u16_i = api.vim.str_utfindex("abc", 2)
assert_eq("legacy str_utfindex utf32 idx", u32_i, 2)
assert_eq("legacy str_utfindex utf16 idx", u16_i, 2)

assert_eq("legacy str_byteindex ascii", api.vim.str_byteindex("abc", 2, false), 2)

assert_eq("new str_utfindex utf-8", api.vim.str_utfindex("abc", "utf-8", 2, false), 2)
assert_eq("new str_byteindex utf-8", api.vim.str_byteindex("abc", "utf-8", 2, false), 2)

assert_eq("utf-16 str_utfindex ascii", api.vim.str_utfindex("abc", "utf-16", 1, false), 1)
assert_eq("utf-16 str_byteindex ascii", api.vim.str_byteindex("abc", "utf-16", 1, false), 1)
assert_eq("legacy use_utf16 ascii", api.vim.str_byteindex("abc", 1, true), 1)

print("vim str index tests: OK")
