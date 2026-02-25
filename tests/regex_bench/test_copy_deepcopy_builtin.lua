local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["layout.buffer"] = {},
        ["lib.highlight"] = {
            For = function() return { colors.white, colors.black } end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
    },
})

local buf = mock.create_buffer(1, "/tmp/copy.txt", { "" }, {})
local win = mock.create_window(1, buf, {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

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

local Fn = mock.loadModule("lib.luaapi.fn")
local VimExpr = mock.loadModule("lib.excmd.vimxpr")

local child = { value = 1 }
local list = { child, 2 }
local list_copy = Fn.copy(list)
assert_true("copy list allocates new table", list_copy ~= list, "same table")
assert_true("copy list is shallow", list_copy[1] == child, "item identity changed")
list_copy[2] = 3
assert_eq("copy list does not mutate source slots", list[2], 2)

local dict = setmetatable({ key = child }, { __vimxpr_kind = "dict" })
local dict_copy = Fn.copy(dict)
assert_true("copy dict allocates new table", dict_copy ~= dict, "same table")
assert_true("copy dict is shallow", dict_copy.key == child, "item identity changed")
assert_eq("copy preserves dict kind", Fn.type(dict_copy), 4)

local method_copy = VimExpr.evaluate("x->copy()", {
    scope = { g = { x = list }, v = {} },
    funcs = Fn,
})
assert_true("method copy works", type(method_copy) == "table" and method_copy ~= list, method_copy)

local shared = { n = 1 }
local src = { shared, shared }
local deep = Fn.deepcopy(src)
assert_true("deepcopy allocates root", deep ~= src, "same table")
assert_true("deepcopy allocates nested", deep[1] ~= shared, "shared nested table")
assert_true("deepcopy keeps shared references by default", deep[1] == deep[2], "references diverged")
deep[1].n = 9
assert_eq("deepcopy isolates source graph", src[1].n, 1)
assert_eq("deepcopy shared target remains shared", deep[2].n, 9)

local deep_noref = Fn.deepcopy(src, 1)
assert_true("deepcopy noref duplicates occurrences", deep_noref[1] ~= deep_noref[2], "references still shared")

local cycle = {}
cycle[1] = cycle
local cycle_copy = Fn.deepcopy(cycle)
assert_true("deepcopy default handles cycle", cycle_copy ~= cycle and cycle_copy[1] == cycle_copy, cycle_copy)

local ok_cycle, err_cycle = pcall(function()
    Fn.deepcopy(cycle, 1)
end)
assert_true("deepcopy noref cycle fails with E724", ok_cycle == false and tostring(err_cycle):find("E724", 1, true) ~= nil,
    err_cycle)

local nested = {}
local cursor = nested
for _ = 1, 101 do
    local nxt = {}
    cursor[1] = nxt
    cursor = nxt
end
local ok_depth, err_depth = pcall(function()
    Fn.deepcopy(nested)
end)
assert_true("deepcopy deep nesting fails with E698", ok_depth == false and tostring(err_depth):find("E698", 1, true) ~= nil,
    err_depth)

local method_src = { { 1 } }
local method_deep = VimExpr.evaluate("x->deepcopy()", {
    scope = { g = { x = method_src }, v = {} },
    funcs = Fn,
})
assert_true("method deepcopy allocates root", type(method_deep) == "table" and method_deep ~= method_src, method_deep)
assert_true("method deepcopy allocates nested", method_deep[1] ~= nil and method_deep[1] ~= method_src[1], method_deep)

local ok_copy_arity, err_copy_arity = pcall(function()
    Fn.copy({}, 1)
end)
assert_true("copy arity errors with E118", ok_copy_arity == false and tostring(err_copy_arity):find("E118", 1, true) ~= nil,
    err_copy_arity)

local ok_deepcopy_arity, err_deepcopy_arity = pcall(function()
    Fn.deepcopy({}, 0, 0)
end)
assert_true("deepcopy arity errors with E118", ok_deepcopy_arity == false and tostring(err_deepcopy_arity):find("E118", 1, true) ~= nil,
    err_deepcopy_arity)

print("copy/deepcopy builtin tests: OK")
