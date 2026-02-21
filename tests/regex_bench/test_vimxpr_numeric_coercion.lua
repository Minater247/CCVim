local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: expected true, got false (%s)"):format(label, tostring(detail)))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Error = mock.loadModule("lib.error")
local VimExpr = mock.loadModule("lib.excmd.vimxpr")
local Options = mock.loadModule("lib.options")
_G.options = Options

local function eval(expr)
    return VimExpr.evaluate(expr, {
        scope = { g = {}, s = {}, l = {}, a = {}, v = {} },
        funcs = {},
    })
end

do
    local rv = eval("[1] + [2]")
    assert_true("list plus list returns table", type(rv) == "table", tostring(rv))
    assert_eq("list plus list count", #rv, 2)
    assert_eq("list plus list first item", rv[1], 1)
    assert_eq("list plus list second item", rv[2], 2)
end

do
    local rv = eval("[] + [3]")
    assert_true("empty list plus list returns table", type(rv) == "table", tostring(rv))
    assert_eq("empty list plus list count", #rv, 1)
    assert_eq("empty list plus list value", rv[1], 3)
end

do
    local rv = eval("'abc' + []")
    assert_true("string plus list returns error", Error.IsError(rv), tostring(rv))
    assert_eq("string plus list code", rv.code, 745)
    assert_true("string plus list message", rv:toString():find("Using a List as a Number", 1, true) ~= nil, rv:toString())
end

do
    local rv = eval("{} + 1")
    assert_true("dict plus number returns error", Error.IsError(rv), tostring(rv))
    assert_eq("dict plus number code", rv.code, 728)
    assert_true("dict plus number message", rv:toString():find("Using a Dictionary as a Number", 1, true) ~= nil,
        rv:toString())
end

do
    local rv = eval("function('len') + 1")
    assert_true("funcref plus number returns error", Error.IsError(rv), tostring(rv))
    assert_eq("funcref plus number code", rv.code, 703)
    assert_true("funcref plus number message", rv:toString():find("Using a Funcref as a Number", 1, true) ~= nil,
        rv:toString())
end

print("vimxpr numeric coercion tests: OK")
