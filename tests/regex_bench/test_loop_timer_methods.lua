local MockEnv = require("vim.tests.test_mocks")

local next_id = 0
local cancelled = {}

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.event"] = {
            StartTimer = function(_secs, _cb)
                next_id = next_id + 1
                return next_id
            end,
            CancelTimer = function(id)
                cancelled[#cancelled + 1] = id
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

local Loop = mock.loadModule("vim.lib.luaapi.loop")
local timer = Loop.new_timer()

assert_true("timer has method start", type(timer.start) == "function", type(timer.start))
assert_true("timer has method again", type(timer.again) == "function", type(timer.again))
assert_true("timer has method stop", type(timer.stop) == "function", type(timer.stop))
assert_true("timer has method close", type(timer.close) == "function", type(timer.close))
assert_true("timer has method set_repeat", type(timer.set_repeat) == "function", type(timer.set_repeat))
assert_true("timer has method get_repeat", type(timer.get_repeat) == "function", type(timer.get_repeat))

local calls = 0
timer:start(50, 100, function()
    calls = calls + 1
end)

assert_eq("timer start marks active", timer._active, true)
assert_eq("timer start assigned id", timer.id, 1)
assert_eq("timer callback not run synchronously", calls, 0)

timer:set_repeat(77)
assert_eq("timer get_repeat returns set value", timer:get_repeat(), 77)
timer:again()
assert_eq("timer again re-arms with new id", timer.id, 2)
assert_eq("timer again cancelled previous id", cancelled[#cancelled], 1)

timer:stop()
assert_eq("timer stop clears active", timer._active, false)
assert_eq("timer stop cancelled current id", cancelled[#cancelled], 2)

timer:close()
assert_eq("timer close marks closed", timer._closed, true)

local ok_closed = pcall(function()
    timer:start(1, 0, function() end)
end)
assert_eq("timer start on closed handle errors", ok_closed, false)

print("loop timer method tests: OK")
