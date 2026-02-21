local Keymap = {}

local Command = loadModule("lib.command")
local Key = loadModule("lib.key")

-- TODO: this has many more options I'm not currently using
function Keymap.set(mode, lhs, rhs, opts)
    opts = opts or {}

    local cmd_opts = {}
    local b = opts.buffer
    if b == true or b == 0 then
        cmd_opts.buffer_local = true
    elseif type(b) == "number" then
        cmd_opts.buffer = buffers[b]
    end

    lhs = Key.strtoseq(lhs)

    if opts.callback then
        Command.map_callback(mode, lhs, opts.callback, cmd_opts)
    elseif type(rhs) == "function" then
        Command.map_callback(mode, lhs, rhs, cmd_opts)
    else
        rhs = Key.strtoseq(rhs)
        if opts.noremap then
            Command.noremap_keys(mode, lhs, rhs, cmd_opts)
        else
            Command.remap_keys(mode, lhs, rhs, cmd_opts)
        end
    end
end


return Keymap