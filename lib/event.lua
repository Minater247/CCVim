local Event  = {}

local timers = {}
local running

local Command
local Key    = loadModule("lib.key")
local OnKey = loadModule("lib.luaapi.on_key")
local ExMsg  = loadModule("lib.excmd.exmsg")
local FrameTree = loadModule("lib.frame")
local Autocmd = loadModule("lib.autocmd")
local Fn = loadModule("lib.luaapi.fn")
local Scopes = loadModule("lib.luaapi.scopes")
local TimerUtils = loadModule("lib.luaapi.timerutils")
local Visual = loadModule("lib.visual")

local function current_backend()
    return rawget(_ENV, "backend")
        or rawget(_G, "backend")
        or rawget(_ENV, "backend_proxy")
        or rawget(_ENV, "backend_ref")
end

function Event.StartTimer(time, callback)
    local id = current_backend().start_timer(time)
    timers[id] = callback
    return id
end

function Event.CancelTimer(id)
    if not id then return end
    current_backend().cancel_timer(id)
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

local mouse_down_pos = {
    [1] = nil,
    [2] = nil,
    [3] = nil,
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
    local now = current_backend().get_epoch()
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

local function find_click_zone(zones, x)
    for i = 1, #zones do
        local zone = zones[i]
        if x >= zone.start_col and x <= zone.end_col then
            return zone
        end
    end
    return nil
end

local function click_zone_at(x, y)
    local tab = tabpages[curtp]

    if y == 1 then
        local stal = options.get("showtabline")
        if stal == 2 or (stal == 1 and tab:count_all() > 1) then
            local zone = find_click_zone(tab.tabline_click_zones, x)
            if zone then
                return zone, windows[curwin], nil, x, y
            end
        end
    end

    if options.get("laststatus") == 3 and y == (tab.winyoff + tab.tree.height + 1) then
        local zone = find_click_zone(tab.global_statusline_click_zones, x)
        if zone then
            return zone, windows[curwin], nil, x, y
        end
    end

    local local_y = y - tab.winyoff
    if local_y < 1 then
        return nil
    end

    local frame, local_x, local_row = FrameTree.FrameAtWithLocal(tab.tree, x, local_y)
    if not frame or not frame.window then
        return nil
    end

    if local_row == frame.height then
        local zone = find_click_zone(frame.window.statusline_click_zones, local_x)
        if zone then
            return zone, frame.window, frame, local_x, local_row
        end
    end

    return nil, frame.window, frame, local_x, local_row
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
        if direction == "up" then
            return "ScrollWheelUp"
        end
        if direction == "down" then
            return "ScrollWheelDown"
        end
        if direction == "left" then
            return "ScrollWheelLeft"
        end
        if direction == "right" then
            return "ScrollWheelRight"
        end
        error("Unknown mouse scroll direction: " .. tostring(direction))
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

local _btn_names = {[1]="l", [2]="r", [3]="m"}
local function click_button_name(button) return _btn_names[button] or "" end

local function click_modifier_string()
    local c, s, a = current_mod_flags()
    return (s and "s" or "") .. (c and "c" or "") .. (a and "a" or "")
end

local function switch_to_tab_from_click(tabnr)
    local target = tonumber(tabnr)
    if not target or not tabpages[target] then
        return false
    end

    tabpages[curtp].lastwin = curwin
    curtp = target
    enterWindow(tabpages[curtp].lastwin or tabpages[curtp].windows[1].winnr)
    what_redraw["all"] = true
    need_redraw = true
    return true
end

local function close_tab_from_click(tabnr)
    local target = tonumber(tabnr)
    if not target then
        return false
    end
    if target == 999 then
        target = curtp
    end

    local target_tab = tabpages[target]
    if not target_tab then
        return false
    end

    local prev_tab = curtp
    local prev_win = curwin
    local switched = false

    if prev_tab ~= target then
        tabpages[prev_tab].lastwin = prev_win
        curtp = target
        enterWindow(target_tab.lastwin or target_tab.windows[1].winnr)
        switched = true
    end

    local ok = tabpages[curtp]:close(windows[curwin], false)
    if ok ~= true then
        if switched then
            curtp = prev_tab
            enterWindow(prev_win)
        end
        return false
    end

    if switched then
        curtp = prev_tab
        enterWindow(prev_win)
    end

    what_redraw["all"] = true
    need_redraw = true
    return true
end

local function dispatch_click_zone(zone, win, button, clicks)
    if not zone then
        return false
    end

    if zone.kind == "tab" then
        if button == 1 then
            return switch_to_tab_from_click(zone.tabnr)
        elseif button == 3 then
            return close_tab_from_click(zone.tabnr)
        end
        return false
    elseif zone.kind == "close_tab" then
        if button == 1 then
            return close_tab_from_click(zone.tabnr)
        end
        return false
    elseif zone.kind == "function" and type(zone.func) == "string" and zone.func ~= "" then
        focus_window(win)
        Fn._call(zone.func, zone.minwid or 0, clicks, click_button_name(button), click_modifier_string())
        what_redraw["all"] = true
        need_redraw = true
        return true
    end

    return false
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
        vis_col = vis_col + (win.scrollx - 1)
    end

    win:cursorSetScreenRow(row_offset, { screen_col = vis_col })
    return true
end

local function point_distance(a, b)
    return math.abs(a.lnum - b.lnum) + math.abs(a.col - b.col)
end

local function place_visual_endpoint(win, local_x, local_y, choose_nearest)
    local anchor
    local cursor
    if choose_nearest and vimmode == "visual" and win.visual_anchor then
        anchor = { lnum = win.visual_anchor.lnum, col = win.visual_anchor.col }
        cursor = { lnum = win.cursory, col = win.cursorx }
    end
    if not place_cursor_from_click(win, local_x, local_y) then
        return false
    end
    if anchor and point_distance(anchor, { lnum = win.cursory, col = win.cursorx })
        <= point_distance(cursor, { lnum = win.cursory, col = win.cursorx })
    then
        win.visual_anchor = cursor
    end
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

    local zone, win, _, local_x, local_y = click_zone_at(x, y)
    if not win then
        return
    end

    local clicks = click_count(button, x, y)
    mouse_down[button] = true
    set_mouse_vvars(win, button, x, y, clicks)

    local click_key = mouse_key_for_event("click", button, clicks, nil)
    if dispatch_mouse_key(click_key) then
        need_redraw = true
        return
    end

    if dispatch_click_zone(zone, win, button, clicks) then
        return
    end

    focus_window(win)

    local model = options.get("mousemodel")
    local _, shifted, alted = current_mod_flags()
    local was_visual = vimmode == "visual" and win.visual_anchor ~= nil

    if button == 1 then
        if (model == "popup" or model == "popup_setpos") and (shifted or alted) then
            if vimmode == "normal" then
                Visual.begin(win, alted and "block" or "char")
                setMode("visual")
            end
            place_visual_endpoint(win, local_x, local_y, was_visual)
        elseif vimmode == "visual" then
            setMode("normal")
            place_cursor_from_click(win, local_x, local_y)
        else
            place_cursor_from_click(win, local_x, local_y)
        end
    elseif button == 2 then
        if model == "popup_setpos" then
            local selection = was_visual and Visual.selection(win)
            place_cursor_from_click(win, local_x, local_y)
            if selection then
                if Visual.contains(selection, win.cursory, win.cursorx) then
                    win:cursorSet(selection.cursor.col, selection.cursor.lnum)
                else
                    setMode("normal")
                end
            end
            fire_menu_popup(win, button, x, y, clicks)
        elseif model == "popup" then
            fire_menu_popup(win, button, x, y, clicks)
        else
            if vimmode == "normal" then
                Visual.begin(win, alted and "block" or "char")
                setMode("visual")
            end
            place_visual_endpoint(win, local_x, local_y, was_visual)
        end
    elseif button == 3 then
        place_cursor_from_click(win, local_x, local_y)
    end

    mouse_down_pos[button] = { lnum = win.cursory, col = win.cursorx }

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

    if button == 1 and vimmode == "normal" then
        local start = mouse_down_pos[button]
        if start then
            win:cursorSet(start.col, start.lnum)
            Visual.begin(win, "char")
            setMode("visual")
        end
    end

    if button == 1 or button == 2 then
        place_visual_endpoint(win, local_x, local_y, button == 2)
    end
    need_redraw = true
end

local function handle_mouse_up(button, x, y)
    mouse_down[button] = false
    mouse_down_pos[button] = nil
    local win, _, local_x, local_y = target_window_at(x, y)
    if not win then win = windows[curwin] end

    local clicks = last_click_count(button)
    set_mouse_vvars(win, button, x, y, clicks)

    if mouse_enabled_for_current_mode() then
        local release_key = mouse_key_for_event("release", button, clicks, nil)
        if dispatch_mouse_key(release_key) then
            need_redraw = true
            return
        end
    end
    if button == 2 and vimmode == "visual" and options.get("mousemodel") == "extend"
        and local_x and local_y
    then
        place_visual_endpoint(win, local_x, local_y, true)
    end
    need_redraw = true
end

local function handle_mouse_scroll(direction, x, y)
    if not mouse_enabled_for_current_mode() then
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

    if direction == "up" or direction == "down" then
        local amount
        if shift_is_held() then
            amount = win:textheight()
        else
            amount = parse_mousescroll_amount("ver")
        end
        if amount < 1 then
            return
        end
        win:scroll(0, direction == "up" and -amount or amount)
    elseif direction == "left" or direction == "right" then
        local amount = parse_mousescroll_amount("hor")
        if amount < 1 then
            return
        end
        win:scroll(direction == "left" and -amount or amount, 0)
    else
        error("Unknown mouse scroll direction: " .. tostring(direction))
    end
    need_redraw = true
end

function Event.ProcessEvent(ev)
    if ev[1] == "key" then
        local k = ev[2]

        if is_modifier(k) then
            mods_down[k] = true
        elseif not ignored_keys[k] then
            local c, s, a
            if ev[4] ~= nil or ev[5] ~= nil then
                c = ev[3] == true
                s = ev[4] == true
                a = ev[5] == true
            else
                c, s, a = current_mod_flags()
            end
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
        local w, h = current_backend().size()
        if type(ev[2]) == "number" and type(ev[3]) == "number" then
            w, h = ev[2], ev[3]
        end
        local ok, err = apply_terminal_resize(w, h, ev[1])
        if not ok then
            ExMsg.echoerr(err:toString())
        end
    end

    ExMsg.Finalize()
end

function Event.InputMouse(button, action, modifier, grid, row, col)
    if grid ~= 0 then
        error("Only grid 0 is supported", 2)
    end

    if type(row) ~= "number" or type(col) ~= "number" then
        error("Mouse row and column must be numbers", 2)
    end

    local normalized_modifier = tostring(modifier or ""):upper()
    local saved_modifiers = {
        [keys.leftShift] = mods_down[keys.leftShift],
        [keys.leftCtrl] = mods_down[keys.leftCtrl],
        [keys.leftAlt] = mods_down[keys.leftAlt],
    }
    mods_down[keys.leftShift] = normalized_modifier:find("S", 1, true) ~= nil
    mods_down[keys.leftCtrl] = normalized_modifier:find("C", 1, true) ~= nil
    mods_down[keys.leftAlt] = normalized_modifier:find("A", 1, true) ~= nil

    local x = math.floor(col) + 1
    local y = math.floor(row) + 1
    local button_num = ({ left = 1, right = 2, middle = 3 })[button]

    local ok, err = pcall(function()
        if button == "wheel" then
            if action ~= "up" and action ~= "down" and action ~= "left" and action ~= "right" then
                error("Invalid wheel action: " .. tostring(action), 2)
            end
            Event.ProcessEvent({ "mouse_scroll", action, x, y })
        elseif button_num == nil then
            error("Unsupported mouse button: " .. tostring(button), 2)
        elseif action == "press" then
            Event.ProcessEvent({ "mouse_click", button_num, x, y })
        elseif action == "drag" then
            Event.ProcessEvent({ "mouse_drag", button_num, x, y })
        elseif action == "release" then
            Event.ProcessEvent({ "mouse_up", button_num, x, y })
        else
            error("Invalid mouse action: " .. tostring(action), 2)
        end
    end)

    mods_down[keys.leftShift] = saved_modifiers[keys.leftShift]
    mods_down[keys.leftCtrl] = saved_modifiers[keys.leftCtrl]
    mods_down[keys.leftAlt] = saved_modifiers[keys.leftAlt]
    if not ok then
        error(err, 0)
    end
end

function Event.PullAndProcess(filter)
    local e1, e2, e3, e4, e5, e6 = current_backend().pull_event(filter)
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
