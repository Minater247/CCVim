local notify = {}

local ExMsg
local notified_messages = {}

notify.notify = function(msg, level, opts)
    ExMsg = ExMsg or loadModule("lib.excmd.exmsg")

    -- TODO: proper semantics for this
    ExMsg.echo("[" .. (level or 0) .. "-notify]: " .. msg)
end

notify.notify_once = function(msg, level, opts)
    if notified_messages[msg] then
        return false
    end
    notify.notify(msg, level, opts)
    notified_messages[msg] = true
    return true
end


return notify
