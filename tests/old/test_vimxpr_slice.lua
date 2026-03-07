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

local function eval(expr, scope_s)
    return VimExpr.evaluate(expr, {
        scope = { g = {}, s = scope_s or {}, l = {}, a = {}, v = {} },
        funcs = {},
    })
end

do
    local rv = eval("'abcdef'[:-2]")
    assert_eq("string slice omitted start", rv, "abcde")
end

do
    local rv = eval("'abcdef'[2:-2]")
    assert_eq("string slice both bounds", rv, "cde")
end

do
    local rv = eval("[1,2,3,4][1:2]")
    assert_true("list slice returns list", type(rv) == "table", tostring(rv))
    assert_eq("list slice length", #rv, 2)
    assert_eq("list slice first", rv[1], 2)
    assert_eq("list slice second", rv[2], 3)
end

do
    local skip_expr = "s:SynAt(line('.'),col('.')) =~? b:syng_strcom"
    local rv = eval("s:skip_expr[:-14] . \"'comment\\\\|doc'\"", { skip_expr = skip_expr })
    assert_true("javascript indent slice expression parses", not Error.IsError(rv), rv)
    assert_eq("javascript indent slice expression value", rv, "s:SynAt(line('.'),col('.')) =~? 'comment\\|doc'")
end

print("vimxpr slice tests: OK")
