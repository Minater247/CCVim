local notify = {}

local ExMsg

notify.notify = function(msg, level, opts)
    ExMsg = ExMsg or loadModule("vim.lib.excmd.exmsg")

    -- TODO: proper semantics for this
    ExMsg.echo("[" .. (level or 0) .. "-notify]: " .. msg)
end


return notify