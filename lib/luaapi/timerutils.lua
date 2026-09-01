local timerutils = {}

local Event = loadModule("lib.event")
local Error = loadModule("lib.error")
local in_fast_event_depth = 0

function timerutils.schedule(fn)
    Event.StartTimer(0, fn)
end

function timerutils.schedule_wrap(fn)
    return function(...)
        local args = {...}
        timerutils.schedule(function() fn(table.unpack(args)) end)
    end
end

function timerutils.in_fast_event()
    return in_fast_event_depth > 0
end

function timerutils.with_fast_event(fn, ...)
    in_fast_event_depth = in_fast_event_depth + 1
    local packed = { pcall(fn, ...) }
    in_fast_event_depth = math.max(0, in_fast_event_depth - 1)
    if not packed[1] then
        error(packed[2], 0)
    end
    return table.unpack(packed, 2)
end

local function to_integer_ms(name, value, default_value, allow_zero)
    if value == nil then
        return default_value
    end
    if type(value) ~= "number" then
        error(("%s: expected number, got %s"):format(name, type(value)), 3)
    end
    if value < 0 or (not allow_zero and value == 0) then
        error(("%s: expected %s number"):format(name, allow_zero and "non-negative" or "positive"), 3)
    end
    return math.floor(value)
end

--- Wait for timeout_ms until callback returns true.
--- Returns: true,nil on success; false,-1 on timeout; false,-2 on interruption.
function timerutils.wait(timeout_ms, callback, interval_ms, fast_only)
    timeout_ms = to_integer_ms("time", timeout_ms, 0, true)
    if callback ~= nil and type(callback) ~= "function" then
        error(("callback: expected function, got %s"):format(type(callback)), 2)
    end
    interval_ms = to_integer_ms("interval", interval_ms, 200, true)
    if fast_only ~= nil and type(fast_only) ~= "boolean" then
        error(("fast_only: expected boolean, got %s"):format(type(fast_only)), 2)
    end

    if timerutils.in_fast_event() then
        error(Error(5560), 2)
    end

    callback = callback or function()
        return false
    end

    if callback() == true then
        return true
    end
    if timeout_ms == 0 then
        return false, -1
    end

    local deadline = os.epoch("utc") + timeout_ms
    local event_filter = fast_only and "timer"

    while true do
        local now = os.epoch("utc")
        if now >= deadline then
            return false, -1
        end

        local remaining = deadline - now
        local next_sleep = interval_ms
        if remaining < next_sleep then
            next_sleep = remaining
        end
        if next_sleep < 0 then
            next_sleep = 0
        end

        local poll_due = false
        local poll_timer_id = Event.StartTimer(next_sleep / 1000, function()
            poll_due = true
        end)

        while not poll_due do
            local ok = Event.PullAndProcess(event_filter)
            if not ok then
                Event.CancelTimer(poll_timer_id)
                return false, -2
            end
        end

        if callback() == true then
            return true
        end
    end
end


return timerutils
