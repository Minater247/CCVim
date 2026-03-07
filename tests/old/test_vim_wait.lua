local MockEnv = require("vim.tests.test_mocks")

local now_ms = 0
local next_timer_id = 0
local timers = {}
local pull_filters = {}
local interrupt_pull = false

local function reset_state()
    now_ms = 0
    next_timer_id = 0
    timers = {}
    pull_filters = {}
    interrupt_pull = false
end

local function pick_next_timer()
    local next_id, next_due
    for id, t in pairs(timers) do
        if next_due == nil or t.due < next_due then
            next_id = id
            next_due = t.due
        end
    end
    return next_id, next_due
end

local event_stub = {
    StartTimer = function(secs, cb)
        next_timer_id = next_timer_id + 1
        timers[next_timer_id] = {
            due = now_ms + math.floor((secs * 1000) + 0.5),
            cb = cb,
        }
        return next_timer_id
    end,
    CancelTimer = function(id)
        timers[id] = nil
    end,
    PullAndProcess = function(filter)
        pull_filters[#pull_filters + 1] = filter
        if interrupt_pull then
            return false, "Terminated"
        end
        local id, due = pick_next_timer()
        if not id then
            return false, "No pending timer events"
        end
        now_ms = due
        local cb = timers[id].cb
        timers[id] = nil
        cb(id)
        return true
    end,
}

local mock = MockEnv.setup({
    os = {
        epoch = function()
            return now_ms
        end,
    },
    module_stubs = {
        ["lib.event"] = event_stub,
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

local timerutils = mock.loadModule("lib.luaapi.timerutils")

-- Immediate callback run at t=0.
reset_state()
local calls = 0
local ok, reason = timerutils.wait(1000, function()
    calls = calls + 1
    return true
end, 200)
assert_eq("immediate callback success", ok, true)
assert_eq("immediate callback reason", reason, nil)
assert_eq("immediate callback call count", calls, 1)
assert_eq("immediate callback does not pull events", #pull_filters, 0)

-- Timeout with zero wait time still runs callback once immediately.
reset_state()
calls = 0
ok, reason = timerutils.wait(0, function()
    calls = calls + 1
end, 200)
assert_eq("zero timeout result", ok, false)
assert_eq("zero timeout reason", reason, -1)
assert_eq("zero timeout callback call count", calls, 1)

-- Poll at interval boundaries until callback becomes true.
reset_state()
calls = 0
ok, reason = timerutils.wait(1000, function()
    calls = calls + 1
    return calls >= 3
end, 200)
assert_eq("interval success", ok, true)
assert_eq("interval success reason", reason, nil)
assert_eq("interval callback call count", calls, 3)
assert_eq("interval elapsed ms", now_ms, 400)

-- Pull interruptions return -2 and cancel pending poll timer.
reset_state()
interrupt_pull = true
ok, reason = timerutils.wait(1000, function()
    return false
end, 200)
assert_eq("interrupt result", ok, false)
assert_eq("interrupt reason", reason, -2)
assert_eq("interrupt clears timers", next(timers), nil)

-- Callback errors are raised.
reset_state()
local ok_err, err = pcall(function()
    timerutils.wait(1000, function()
        error("boom")
    end, 200)
end)
assert_eq("callback error raised", ok_err, false)
assert_true("callback error message", tostring(err):find("boom", 1, true) ~= nil, err)

-- fast_only should use timer-filtered pull.
reset_state()
calls = 0
ok, reason = timerutils.wait(400, function()
    calls = calls + 1
    return calls >= 2
end, 200, true)
assert_eq("fast_only result", ok, true)
assert_eq("fast_only reason", reason, nil)
assert_eq("fast_only filter used", pull_filters[1], "timer")

-- Cannot be called from fast-event context.
reset_state()
local original_in_fast_event = timerutils.in_fast_event
timerutils.in_fast_event = function()
    return true
end
ok_err, err = pcall(function()
    timerutils.wait(1000, function()
        return false
    end, 200)
end)
timerutils.in_fast_event = original_in_fast_event
assert_eq("fast-event guard raised", ok_err, false)
assert_true("fast-event guard message", tostring(err):find("E5560", 1, true) ~= nil, err)

print("vim.wait tests: OK")
