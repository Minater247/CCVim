local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_list_eq(label, got, want)
    assert_eq(label .. " len", #got, #want)
    for i = 1, #want do
        assert_eq(label .. " [" .. i .. "]", got[i], want[i])
    end
end

local mock = MockEnv.setup({ ccvim_path = "vim" })
local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local api = ApiBuild.Build()

assert_eq("vim.list_slice exists", type(api.vim.list_slice), "function")
assert_list_eq("slice 2..3", api.vim.list_slice({ 1, 2, 3, 4 }, 2, 3), { 2, 3 })
assert_list_eq("slice start only", api.vim.list_slice({ 1, 2, 3 }, 2), { 2, 3 })
assert_list_eq("slice finish only", api.vim.list_slice({ 1, 2, 3 }, nil, 2), { 1, 2 })
assert_list_eq("slice out of range", api.vim.list_slice({ 1, 2, 3 }, 4, 9), {})

print("vim.list_slice tests: OK")
