local timerutils = {}

local Event = loadModule("lib.event")

function timerutils.schedule(fn)
    Event.StartTimer(0, fn)
end

function timerutils.schedule_wrap(fn)
    return function(...)
        local args = {...}
        timerutils.schedule(function() fn(table.unpack(args)) end)
    end
end



return timerutils