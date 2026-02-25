local MockEnv = require("vim.tests.test_mocks")

local next_id = 0
local cancelled = {}
local scheduled = {}

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.event"] = {
            StartTimer = function(_secs, cb)
                next_id = next_id + 1
                scheduled[next_id] = cb
                return next_id
            end,
            CancelTimer = function(id)
                cancelled[#cancelled + 1] = id
                scheduled[id] = nil
            end,
        },
    },
})

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

local Loop = mock.loadModule("lib.luaapi.loop")

local check = Loop.new_check()
assert_true("check has method start", type(check.start) == "function", type(check.start))
assert_true("check has method stop", type(check.stop) == "function", type(check.stop))
assert_true("check has method close", type(check.close) == "function", type(check.close))
assert_true("check has method is_active", type(check.is_active) == "function", type(check.is_active))
assert_true("check has method is_closing", type(check.is_closing) == "function", type(check.is_closing))

local calls = 0
check:start(function()
    calls = calls + 1
end)
assert_eq("check start marks active", check:is_active(), true)
assert_eq("check start marks not closing", check:is_closing(), false)
assert_eq("check start assigned id", check.id, 1)

scheduled[1]()
assert_eq("check callback ran", calls, 1)
assert_eq("check callback rescheduled", check.id, 2)

check:stop()
assert_eq("check stop clears active", check:is_active(), false)
assert_eq("check stop clears id", check.id, nil)
assert_eq("check stop cancels pending id", cancelled[#cancelled], 2)

check:close()
assert_eq("check close marks closing", check:is_closing(), true)

local ok_closed = pcall(function()
    check:start(function() end)
end)
assert_eq("check start on closed handle errors", ok_closed, false)

local t1 = Loop.now()
local t2 = Loop.now()
assert_true("loop.now returns number", type(t1) == "number", type(t1))
assert_true("loop.now is non-decreasing", t2 >= t1, ("%s < %s"):format(tostring(t2), tostring(t1)))

print("loop check method tests: OK")
