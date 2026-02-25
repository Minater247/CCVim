local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond)
    if not cond then
        error("FAIL " .. label)
    end
end

local mock = MockEnv.setup({ ccvim_path = "vim" })
local OnKey = mock.loadModule("lib.luaapi.on_key")

assert_eq("count starts at zero", OnKey.on_key(), 0)

local ns_base = 500
OnKey.set_namespace_allocator(function(_)
    ns_base = ns_base + 1
    return ns_base
end)

local seen = {}
local ns = OnKey.on_key(function(key, typed)
    seen[#seen + 1] = { key = key, typed = typed }
end, nil, {})

assert_eq("auto namespace comes from allocator", ns, 501)
assert_eq("count after registration", OnKey.on_key(), 1)
assert_eq("dispatch non-consuming callback", OnKey.dispatch("a", "a"), false)
assert_eq("callback called once", #seen, 1)
assert_eq("callback key", seen[1].key, "a")
assert_eq("callback typed", seen[1].typed, "a")

local consume_ns = OnKey.on_key(function()
    return ""
end)
assert_true("consume ns allocated", consume_ns > 0)
assert_eq("dispatch consumed when any callback returns empty string", OnKey.dispatch("b", "b"), true)

OnKey.on_key(nil, consume_ns)
assert_eq("remove callback by namespace", OnKey.on_key(), 1)

local bad_ns = OnKey.on_key(function()
    return "not-empty"
end)
local ok_bad, err_bad = pcall(OnKey.dispatch, "c", "c")
assert_eq("invalid return errors", ok_bad, false)
assert_true("invalid return message", tostring(err_bad):find("return string must be empty", 1, true) ~= nil)
assert_eq("bad callback removed", OnKey.on_key(), 1)
OnKey.on_key(nil, bad_ns)

local err_ns = OnKey.on_key(function()
    error("boom")
end)
local ok_err, err_msg = pcall(OnKey.dispatch, "d", "d")
assert_eq("callback error bubbles", ok_err, false)
assert_true("callback error includes namespace", tostring(err_msg):find("With ns_id " .. err_ns, 1, true) ~= nil)
assert_eq("errored callback removed", OnKey.on_key(), 1)

local nested_calls = 0
local rec_ns = OnKey.on_key(function()
    nested_calls = nested_calls + 1
    local inner = OnKey.dispatch("z", "z")
    assert_eq("recursive dispatch suppressed", inner, false)
end)
assert_eq("outer dispatch works", OnKey.dispatch("e", "e"), false)
assert_eq("outer callback called once", nested_calls, 1)
OnKey.on_key(nil, rec_ns)

OnKey.on_key(nil, ns)
assert_eq("all callbacks removed", OnKey.on_key(), 0)

print("vim.on_key tests: OK")
