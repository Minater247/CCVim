local Event  = {}

local timers = {}
local running

local Command
local Key    = loadModule("lib.key")
local OnKey = loadModule("lib.luaapi.on_key")
local ExMsg  = loadModule("lib.excmd.exmsg")
local Error = loadModule("lib.error")

function Event.StartTimer(time, callback)
    local id = os.startTimer(time)
    timers[id] = callback
    return id
end

function Event.CancelTimer(id)
    if not id then return end
    os.cancelTimer(id)
    timers[id] = nil
end

local mods_down = {
    [keys.leftShift] = false,
    [keys.rightShift] = false,
    [keys.leftCtrl] = false,
    [keys.rightCtrl] = false,
    [keys.leftAlt] = false,
    [keys.rightAlt] = false,
}

local ignored_keys = {
    [keys.capsLock]   = true,
    [keys.numLock]    = true,
    [keys.scrollLock] = true,
}

local function is_modifier(k)
    return mods_down[k] ~= nil
end

local function current_mod_flags()
    local shifted = mods_down[keys.leftShift] or mods_down[keys.rightShift]
    local ctrld   = mods_down[keys.leftCtrl] or mods_down[keys.rightCtrl]
    local alted   = mods_down[keys.leftAlt] or mods_down[keys.rightAlt]
    return ctrld, shifted, alted
end

local function key_to_on_key_string(key)
    local ch = key:emittable()
    if ch then
        -- vim.on_key follows nvim keycode behavior where Enter is "\r".
        if ch == "\n" then
            return "\r"
        end
        return ch
    end
    return key:printable() or ""
end

function Event.RunLoop()
    running = true

    need_redraw = true
    what_redraw["all"] = true

    while running do
        if need_redraw then
            need_redraw = false
            tabpages[curtp]:render()
            what_redraw = {}
        end

        local ev = { os.pullEvent() }

        if ev[1] == "key" then
            local k = ev[2]

            if is_modifier(k) then
                mods_down[k] = true
            elseif not ignored_keys[k] then
                local c, s, a = current_mod_flags()
                local key = Key:new(k, c, s, a)
                local keystr = key_to_on_key_string(key)
                local discard = OnKey.dispatch(keystr, keystr)
                if not discard then
                    Command.HandleKey(key)
                end
                need_redraw = true
            end
        elseif ev[1] == "key_up" then
            local k = ev[2]
            if is_modifier(k) then
                mods_down[k] = false
            end
        elseif ev[1] == "timer" then
            if timers[ev[2]] then timers[ev[2]](ev[2]) end
        elseif ev[1] == "monitor_resize" or ev[1] == "term_resize" then
            local w, h = term.getSize()
            local ok, err = _V.apply_terminal_resize(w, h, ev[1])
            if not ok and err then
                local msg
                if Error.IsError(err) then
                    msg = err:toString()
                else
                    msg = tostring(err)
                end
                ExMsg.echoerr(msg)
            end
        end
        ExMsg.Finalize()
    end
end

function Event.HaltLoop()
    running = false
end

function Event.LoadCommandModule()
    Command = loadModule("lib.command")
end

return Event
