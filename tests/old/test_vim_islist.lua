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

assert_true("vim.islist exists", type(api.vim.islist) == "function", type(api.vim.islist))
assert_true("vim.isarray exists", type(api.vim.isarray) == "function", type(api.vim.isarray))
assert_true("vim.tbl_islist exists", type(api.vim.tbl_islist) == "function", type(api.vim.tbl_islist))

assert_eq("islist empty table", api.vim.islist({}), true)
assert_eq("islist contiguous", api.vim.islist({ "a", "b", "c" }), true)
assert_eq("islist gap", api.vim.islist({ [1] = "a", [3] = "c" }), false)
assert_eq("islist dict key", api.vim.islist({ a = 1 }), false)
assert_eq("islist non-table", api.vim.islist("x"), false)

assert_eq("isarray non-contiguous integers", api.vim.isarray({ [2] = true, [5] = true }), true)
assert_eq("isarray non-integer key", api.vim.isarray({ [1] = true, a = true }), false)
assert_eq("tbl_islist alias", api.vim.tbl_islist({ 1, 2 }), true)

api.vim._empty_dict_mt = {}
local empty_dict = setmetatable({}, api.vim._empty_dict_mt)
assert_eq("islist empty_dict metatable", api.vim.islist(empty_dict), false)
assert_eq("isarray empty_dict metatable", api.vim.isarray(empty_dict), false)

print("vim.islist tests: OK")
