local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Fn = mock.loadModule("vim.lib.luaapi.fn")
local VimExpr = mock.loadModule("vim.lib.excmd.vimxpr")

do
    local out = Fn.items({ a = 1, b = 2 })
    assert_eq("items(dict) returns list", type(out), "table")
    assert_eq("items(dict) count", #out, 2)

    local found = {}
    for i = 1, #out do
        local pair = out[i]
        assert_eq("items(dict) pair is list", type(pair), "table")
        assert_eq("items(dict) pair len", #pair, 2)
        found[pair[1]] = pair[2]
    end

    assert_eq("items(dict) contains a", found.a, 1)
    assert_eq("items(dict) contains b", found.b, 2)
end

do
    local out = Fn.items({})
    assert_eq("items(empty dict) returns list", type(out), "table")
    assert_eq("items(empty dict) count", #out, 0)
end

do
    local ok, err = pcall(function()
        return Fn.items({ 1, 2 })
    end)
    assert_eq("items(list) errors", ok, false)
    assert_true("items(list) emits E1206", tostring(err):find("E1206", 1, true) ~= nil, err)
end

do
    local ok, err = pcall(function()
        return Fn.items(1)
    end)
    assert_eq("items(number) errors", ok, false)
    assert_true("items(number) emits E1206", tostring(err):find("E1206", 1, true) ~= nil, err)
end

do
    local ok, err = pcall(function()
        return Fn.items({ a = 1 }, 2)
    end)
    assert_eq("items too many args errors", ok, false)
    assert_true("items too many args emits E118", tostring(err):find("E118", 1, true) ~= nil, err)
end

do
    local out = VimExpr.evaluate("x->items()", {
        scope = { g = { x = { k = "v" } }, v = {} },
        funcs = Fn,
    })
    assert_eq("items method returns list", type(out), "table")
    assert_eq("items method pair count", #out, 1)
    assert_eq("items method key", out[1][1], "k")
    assert_eq("items method value", out[1][2], "v")
end

print("items builtin tests: OK")
