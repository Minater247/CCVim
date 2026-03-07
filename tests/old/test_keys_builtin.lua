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

local function contains(tbl, value)
    for i = 1, #tbl do
        if tbl[i] == value then
            return true
        end
    end
    return false
end

local Fn = mock.loadModule("lib.luaapi.fn")

do
    local out = Fn.fn.keys({ a = 1, b = 2 })
    assert_eq("keys(dict) returns list", type(out), "table")
    assert_eq("keys(dict) count", #out, 2)
    assert_true("keys(dict) contains a", contains(out, "a"), table.concat(out, ","))
    assert_true("keys(dict) contains b", contains(out, "b"), table.concat(out, ","))
end

do
    local out = Fn.fn.keys({})
    assert_eq("keys(empty dict) returns list", type(out), "table")
    assert_eq("keys(empty dict) count", #out, 0)
end

do
    local ok, err = pcall(function()
        return Fn.fn.keys({ 1, 2 })
    end)
    assert_eq("keys(list) errors", ok, false)
    assert_true("keys(list) emits E1206", tostring(err):find("E1206", 1, true) ~= nil, err)
end

do
    local ok, err = pcall(function()
        return Fn.fn.keys(1)
    end)
    assert_eq("keys(number) errors", ok, false)
    assert_true("keys(number) emits E1206", tostring(err):find("E1206", 1, true) ~= nil, err)
end

do
    local ok, err = pcall(function()
        return Fn.fn.keys({ a = 1 }, 2)
    end)
    assert_eq("keys too many args errors", ok, false)
    assert_true("keys too many args emits E118", tostring(err):find("E118", 1, true) ~= nil, err)
end

print("keys builtin tests: OK")
