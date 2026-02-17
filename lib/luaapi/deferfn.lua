local Event = loadModule("vim.lib.event")

-- TODO: how does a luv timer struct even look?
return function(fn, timeout)
    return {Event.StartTimer(timeout / 1000, fn)}
end