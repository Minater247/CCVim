local Event  = {}

local timers = {}
local running

local Command
local Key    = loadModule("lib.key")
local OnKey = loadModule("lib.luaapi.on_key")
local ExMsg  = loadModule("lib.excmd.exmsg")
local Error = loadModule("lib.error")
local FrameTree = loadModule("lib.frame")
local Autocmd = loadModule("lib.autocmd")
local Scopes = loadModule("lib.luaapi.scopes")
local TimerUtils = loadModule("lib.luaapi.timerutils")

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

local mouse_down = {
    [1] = false,
    [2] = false,
    [3] = false,
}

local mouse_click_state = {
    [1] = nil,
    [2] = nil,
    [3] = nil,
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

local function shift_is_held()
    return mods_down[keys.leftShift] or mods_down[keys.rightShift]
end

local function mouse_enabled_for_current_mode()
    local mouse = options.get("mouse")
    if mouse == "" then
        return false
    end
    if mouse:find("a", 1, true) then
        return true
    end

    local mode_char = "n"
    if vimmode == "insert" then
        mode_char = "i"
    elseif vimmode == "cmdline" then
        mode_char = "c"
    elseif vimmode == "visual" or vimmode == "select" then
        mode_char = "v"
    end

    if mouse:find(mode_char, 1, true) then
        return true
    end

    if mouse:find("h", 1, true) then
        local win = windows[curwin]
        if options.get("filetype", nil, win.buffer) == "help" then
            return true
        end
    end

    return false
end

local function parse_mousescroll_amount(axis)
    local amount = (axis == "hor") and 6 or 3
    local raw = options.get("mousescroll")
    for part in raw:gmatch("([^,]+)") do
        local p = part:gsub("^%s+", ""):gsub("%s+$", "")
        local dir, n = p:match("^([%a]+)%s*:%s*(%d+)$")
        if dir and dir:lower() == axis then
            amount = tonumber(n)
        end
    end
    return math.floor(amount)
end

local function click_count(button, x, y)
    local now = os.epoch("utc")
    local max_gap = math.max(0, math.floor(options.get("mousetime")))

    local count = 1
    local prev = mouse_click_state[button]
    if prev and prev.x == x and prev.y == y and (now - prev.time) <= max_gap then
        count = math.min(prev.count + 1, 4)
    end

    mouse_click_state[button] = {
        x = x,
        y = y,
        time = now,
        count = count,
    }
    return count
end

local function target_window_at(x, y)
    local tab = tabpages[curtp]
    if not tab or not tab.tree then
        return nil
    end

    local local_y = y - (tab.winyoff or 0)
    if local_y < 1 then
        return nil
    end

    local frame, local_x, local_row = FrameTree.FrameAtWithLocal(tab.tree, x, local_y)
    if not frame or not frame.window then
        return nil
    end

    return frame.window, frame, local_x, local_row
end

local function focus_window(win)
    enterWindow(win.winnr)
end

local function set_mouse_vvars(win, button, x, y, clicks)
    local v = Scopes._v
    v.mouse_win = win.winnr
    v.mouse_winid = win.winnr
    v.mouse_lnum = win.cursory
    v.mouse_line = win.cursory
    v.mouse_col = win.cursorx
    v.mouse_curscol = win.cursorx
    v.mouse_button = button
    v.mouse_clicks = clicks
    v.mouse_screencol = x
    v.mouse_screenrow = y
end

local function mapping_mode_alias()
    return string.sub(vimmode, 1, 1)
end

local mouse_button_names = {
    [1] = "Left",
    [2] = "Right",
    [3] = "Middle",
}

local mouse_kind_suffixes = {
    click = "Mouse",
    drag = "Drag",
    release = "Release",
}

local function mouse_notation_name(kind, button, clicks, direction)
    if kind == "scroll" then
        return direction == -1 and "ScrollWheelUp" or "ScrollWheelDown"
    end

    local name = mouse_button_names[button] .. mouse_kind_suffixes[kind]
    if clicks >= 2 then
        return tostring(clicks) .. "-" .. name
    end
    return name
end

local function last_click_count(button)
    local prev = mouse_click_state[button]
    if prev and prev.count then
        return prev.count
    end
    return 1
end

local function mouse_key_for_event(kind, button, clicks, direction)
    local name = mouse_notation_name(kind, button, clicks, direction)
    local ctrld, shifted, alted = current_mod_flags()
    return Key.mouse_key(name, ctrld, shifted, alted)
end

local function dispatch_mouse_key(key)
    local keystr = Key.to_map_notation(key.numeric)
    local discard = OnKey.dispatch(keystr, keystr)
    if discard then
        return true
    end

    local has_mapping = Command.has_mapping(mapping_mode_alias(), { key })
    if not has_mapping then
        return false
    end
    Command.HandleKey(key)
    return true
end

local function place_cursor_from_click(win, local_x, local_y)
    local text_rows = win:textheight()
    if local_y < 1 or local_y > text_rows then
        return false
    end

    local text_w, text_x = win:textwidth()
    if text_w < 1 then
        return false
    end

    local row_offset = local_y - 1
    local vis_col = local_x - text_x + 1
    if vis_col < 1 then
        vis_col = 1
    elseif vis_col > text_w then
        vis_col = text_w
    end

    if not win.opts.wrap then
        vis_col = vis_col + (win.scrollx - 1) - 1
    end

    win:cursorSetScreenRow(row_offset, { screen_col = vis_col })
    return true
end

local function fire_menu_popup(win, button, x, y, clicks)
    Autocmd.Run("MenuPopup", {
        bufnr = win.buffer.bufnr,
        bufname = win.buffer.name,
        data = {
            button = button,
            x = x,
            y = y,
            clicks = clicks,
        },
    })
end

local function handle_mouse_click(button, x, y)
    if not mouse_enabled_for_current_mode() then
        return
    end

    local win, _, local_x, local_y = target_window_at(x, y)
    if not win then
        return
    end

    local clicks = click_count(button, x, y)
    mouse_down[button] = true
    focus_window(win)
    set_mouse_vvars(win, button, x, y, clicks)

    local click_key = mouse_key_for_event("click", button, clicks, nil)
    if dispatch_mouse_key(click_key) then
        need_redraw = true
        return
    end

    local model = options.get("mousemodel")

    if button == 1 then
        place_cursor_from_click(win, local_x, local_y)
    elseif button == 2 then
        if model == "popup_setpos" then
            place_cursor_from_click(win, local_x, local_y)
            fire_menu_popup(win, button, x, y, clicks)
        elseif model == "popup" then
            fire_menu_popup(win, button, x, y, clicks)
        else
            place_cursor_from_click(win, local_x, local_y)
        end
    elseif button == 3 then
        place_cursor_from_click(win, local_x, local_y)
    end

    need_redraw = true
end

local function handle_mouse_drag(button, x, y)
    if not mouse_enabled_for_current_mode() then
        return
    end
    if not mouse_down[button] then
        return
    end

    local win, _, local_x, local_y = target_window_at(x, y)
    if not win then
        return
    end

    focus_window(win)
    local clicks = last_click_count(button)
    set_mouse_vvars(win, button, x, y, clicks)

    local drag_key = mouse_key_for_event("drag", button, clicks, nil)
    if dispatch_mouse_key(drag_key) then
        need_redraw = true
        return
    end

    if button == 1 or button == 2 then
        place_cursor_from_click(win, local_x, local_y)
    end
    need_redraw = true
end

local function handle_mouse_up(button, x, y)
    mouse_down[button] = false
    local win
    local t = target_window_at(x, y)
    if t then
        win = t
    else
        win = windows[curwin]
    end

    local clicks = last_click_count(button)
    set_mouse_vvars(win, button, x, y, clicks)

    if mouse_enabled_for_current_mode() then
        local release_key = mouse_key_for_event("release", button, clicks, nil)
        if dispatch_mouse_key(release_key) then
            need_redraw = true
            return
        end
    end
    need_redraw = true
end

local function handle_mouse_scroll(direction, x, y)
    if not mouse_enabled_for_current_mode() then
        return
    end
    if direction ~= -1 and direction ~= 1 then
        return
    end

    local win = target_window_at(x, y)
    if not win then
        return
    end

    focus_window(win)
    set_mouse_vvars(win, 0, x, y, 0)

    local scroll_key = mouse_key_for_event("scroll", 0, nil, direction)
    if dispatch_mouse_key(scroll_key) then
        need_redraw = true
        return
    end

    local amount
    if shift_is_held() then
        amount = win:textheight()
    else
        amount = parse_mousescroll_amount("ver")
    end
    if amount < 1 then
        return
    end

    win:scroll(0, direction * amount)
    need_redraw = true
end

function Event.ProcessEvent(ev)
    if ev[1] == "key" then
        local k = ev[2]

        if is_modifier(k) then
            mods_down[k] = true
        elseif not ignored_keys[k] then
            local c, s, a = current_mod_flags()
            local key = Key:new(k, c, s, a)
            local keystr = Key.to_termcode_string(key)
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
    elseif ev[1] == "mouse_click" then
        handle_mouse_click(ev[2], ev[3], ev[4])
    elseif ev[1] == "mouse_drag" then
        handle_mouse_drag(ev[2], ev[3], ev[4])
    elseif ev[1] == "mouse_up" then
        handle_mouse_up(ev[2], ev[3], ev[4])
    elseif ev[1] == "mouse_scroll" then
        handle_mouse_scroll(ev[2], ev[3], ev[4])
    elseif ev[1] == "timer" then
        local timer_id = ev[2]
        local cb = timers[timer_id]
        timers[timer_id] = nil
        if cb then
            TimerUtils.with_fast_event(function()
                cb(timer_id)
            end)
        end
    elseif ev[1] == "monitor_resize" or ev[1] == "term_resize" then
        local w, h = term.getSize()
        local ok, err = apply_terminal_resize(w, h, ev[1])
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

function Event.PullAndProcess(filter)
    local e1, e2, e3, e4, e5, e6 = os.pullEvent(filter)
    Event.ProcessEvent({ e1, e2, e3, e4, e5, e6 })
    return true
end

function Event.RunLoop()
    running = true

    need_redraw = true
    what_redraw["all"] = true

    while running do
        local defer_redraw = false
        if need_redraw and options.get("lazyredraw") then
            defer_redraw = lazyredraw_block > 0 and not lazyredraw_force
        end

        if need_redraw and not defer_redraw then
            need_redraw = false
            tabpages[curtp]:render()
            what_redraw = {}
            lazyredraw_force = false
        end

        local ok, err = Event.PullAndProcess()
        if not ok then
            error(err)
        end
    end
end

function Event.HaltLoop()
    running = false
end

function Event.LoadCommandModule()
    Command = loadModule("lib.command")
end

return Event
