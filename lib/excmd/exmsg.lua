local ExMsg = {}

local Highlight = loadModule("lib.highlight")
local Tab = loadModule("lib.tab")
local TexRen = loadModule("lib.texren")
local Command = loadModule("lib.command")
local Key = loadModule("lib.key")
local CmdRead = loadModule("lib.excmd.cmdread")

--[[
Array of messages. Each line is {hlgroup, str}.
]]
ExMsg.messages = {}

--[[
Array of messages currently displayed on screen. Includes messages not written to the :messages buffer,
cleared at the end of the script.
{
    {{hlgroup, str}, {hlgroup, str}, ...},
    ...
}
]]
local displaymessages = {}

-- A single message pending, written using :echo.
local echon = {}

local current_hl = "Normal"


--[[
The lines to display for the messages.
{
    {str, fgblit, bgblit},
    ...
}
]]
local blitmessages = {}

--[[
The actual lines to display on the screen, as calculated by TexRen.
]]
local screenlines = {}

-- Cache invalidation for blit/screenline rendering.
local display_dirty = true
local last_screen_width = nil
local last_tabcfg = nil

local function mark_display_dirty()
    display_dirty = true
end

local in_press_enter = false
local in_more = false
local more_top = 1
local more_help_long = false

-- When true, there are transient messages that fit within cmdheight and
-- should be drawn once during the next Tabpage render (back buffer), then
-- cleared.
local pending_one_shot = false

-- =====================================
-- Silent stack (for :silent / :unsilent)
-- =====================================
-- Each frame is either { kind = 'silent', skip_errors = boolean, on_error = fn|nil }
-- or { kind = 'unsilent' } which overrides any outer silent while active.
local silence_stack = {}

-- =====================================
-- UI Suppression (for capture-only APIs)
-- =====================================
local ui_suppress_depth = 0
local function ui_suppressed()
    return ui_suppress_depth > 0
end

function ExMsg.PushUISuppress()
    ui_suppress_depth = ui_suppress_depth + 1
end

function ExMsg.PopUISuppress()
    if ui_suppress_depth > 0 then
        ui_suppress_depth = ui_suppress_depth - 1
    end
end

local function silence_effect()
    -- Return one of: nil (no silent), {kind='silent', skip_errors=?, on_error=?}, or {kind='unsilent'}
    for i = #silence_stack, 1, -1 do
        local f = silence_stack[i]
        if f.kind == 'unsilent' then return f end
        if f.kind == 'silent' and not f.lifted then return f end
    end
    return nil
end

function ExMsg.PushSilent(opts)
    silence_stack[#silence_stack + 1] = {
        kind = 'silent',
        skip_errors = not not (opts and opts.skip_errors),
        on_error = opts and opts.on_error,
    }
end

function ExMsg.PushUnsilent()
    silence_stack[#silence_stack + 1] = { kind = 'unsilent' }
end

function ExMsg.PopSilent()
    if #silence_stack > 0 then
        table.remove(silence_stack)
    end
end

-- Internal: mark the most recent silent frame as lifted (after a non-bang error),
-- so further messages are displayed normally for the remainder of this command.
local function lift_current_silent()
    for i = #silence_stack, 1, -1 do
        local f = silence_stack[i]
        if f.kind == 'silent' then
            f.lifted = true
            break
        end
    end
end

-- =====================================
-- Capture Support (for :exec and APIs)
-- =====================================
-- We avoid monkey-patching public functions (previous approach in api.lua)
-- by maintaining an internal stack of active capture contexts. Each context:
--   { out = {"line1\n", ...}, partial = "pending_echon_text", last_err = nil, saw_full_line = false }
-- Error messages (hlgroup == "ErrorMsg") are NOT added to 'out'; only
-- their last line is tracked via last_err, matching the former semantics.
local capture_stack = {}

-- =====================================
-- :redir Support
-- =====================================
-- Single active redirection context:
--   { out = {"line1", ...}, current = "open_current_line", on_close = fn }
local redir_ctx = nil

local function redir_flush_partial()
    if redir_ctx and redir_ctx.current ~= nil then
        redir_ctx.out[#redir_ctx.out + 1] = redir_ctx.current
        redir_ctx.current = nil
    end
end

local function redir_emit(str, nonewline)
    if not redir_ctx then
        return
    end
    local text = tostring(str or "")
    if nonewline then
        redir_ctx.current = (redir_ctx.current or "") .. text
        return
    end

    redir_flush_partial()
    redir_ctx.current = "\n" .. text
end

function ExMsg.StartRedir(on_close)
    redir_ctx = {
        out = {},
        current = nil,
        on_close = on_close,
    }
    return true
end

function ExMsg.EndRedir()
    if not redir_ctx then
        return true
    end

    redir_flush_partial()
    local ctx = redir_ctx
    redir_ctx = nil

    local ok, rv = pcall(ctx.on_close, table.concat(ctx.out))
    if not ok then
        return false, rv
    end
    if rv ~= nil and rv ~= true then
        return false, rv
    end
    return true
end

local function capture_flush_partial(cap)
    if cap.partial ~= nil and cap.partial ~= "" then
        cap.out[#cap.out + 1] = cap.partial .. "\n"
        cap.partial = ""
    end
end

-- Public: begin a capture; returns a handle (the capture table itself).
function ExMsg.StartCapture()
    local cap = { out = {}, partial = "", last_err = nil, saw_full_line = false }
    capture_stack[#capture_stack + 1] = cap
    return cap
end

-- Public: end a capture; returns (output_string, last_err)
function ExMsg.EndCapture(cap)
    -- Locate (allow out-of-order end for robustness, though typical usage is LIFO)
    local idx
    for i = #capture_stack, 1, -1 do
        if capture_stack[i] == cap then
            idx = i; break
        end
    end
    if not idx then
        return "", nil -- unknown handle; fail softly
    end
    capture_flush_partial(cap)
    table.remove(capture_stack, idx)
    return table.concat(cap.out), cap.last_err
end

-- Renders the display lines to the blit cache.
local function renderdisplay()
    if not display_dirty then return end
    blitmessages = {}

    for i = 1, #displaymessages do
        local line = displaymessages[i]

        local str_parts = {}
        local fg_parts = {}
        local bg_parts = {}

        for _, pair in ipairs(line) do
            local hl = Highlight.For(pair[1])
            local text = tostring(pair[2] or "")
            local len = #text
            if len > 0 then
                str_parts[#str_parts + 1] = text
                fg_parts[#fg_parts + 1] = string.rep(colors.toBlit(hl[1]), len)
                bg_parts[#bg_parts + 1] = string.rep(colors.toBlit(hl[2]), len)
            end
        end

        blitmessages[#blitmessages + 1] = {
            table.concat(str_parts),
            table.concat(fg_parts),
            table.concat(bg_parts)
        }
    end
end

local function calculateScreenLines()
    local tabcfg = Tab.get_tab_config(windows[curwin].buffer)
    if not display_dirty and last_screen_width == screen.width and last_tabcfg == tabcfg then
        return
    end

    renderdisplay()
    screenlines = {}

    for i = 1, #blitmessages do
        local triad = blitmessages[i]
        local new_lines, new_blits = TexRen.parse(
            triad[1],
            {
                wraplen = screen.width,
                wordwrap = true,
                tabcfg = tabcfg -- TODO: not probably how that's done
            },
            nil,
            { triad[2], triad[3] }
        )
        for j = 1, #new_lines do
            screenlines[#screenlines + 1] = { new_lines[j], new_blits.fg[j], new_blits.bg[j] }
        end
    end

    last_screen_width = screen.width
    last_tabcfg = tabcfg
    display_dirty = false
end

-- Render the current page of messages plus the MoreMessage status line.
local function draw_more_page(snap_to_bottom)
    -- Ensure screenlines is up to date for whatever is in displaymessages.
    calculateScreenLines()
    local cmdread_active = CmdRead.is_active()

    local max_lines = screen.height - 1 -- bottom row reserved for the status line

    if snap_to_bottom then
        more_top = math.max(1, #screenlines - max_lines + 1)
    end

    -- Clamp window
    local max_start = math.max(1, #screenlines - max_lines + 1)
    if more_top < 1 then more_top = 1 end
    if more_top > max_start then more_top = max_start end

    -- Clear the message area (all but the bottom status line)
    Highlight.SetFor("Normal")
    for i = 1, max_lines do
        term.setCursorPos(1, screen.height - i)
        term.clearLine()
    end

    -- Draw visible slice bottom-aligned above the status line
    local visible = math.min(max_lines, #screenlines - more_top + 1)
    for i = 1, visible do
        local triad = screenlines[more_top + i - 1]
        local y = (screen.height - 1) - visible + i
        term.setCursorPos(1, y)
        term.blit(triad[1], triad[2], triad[3])
    end

    -- Status line
    term.setCursorPos(1, screen.height)
    term.clearLine()
    if cmdread_active then
        CmdRead.drawCmdline()
    else
        Highlight.SetFor("MoreMsg")
        if more_help_long then
            term.write("-- More -- SPACE/d/j: screen/page/line down, b/u/k: up, q: quit")
        else
            term.write("-- More --")
        end
    end
end


local upref    = Key:new(keys.up)
local downref  = Key:new(keys.down)
local pgupref  = Key:new(keys.pageUp)
local pgdnref  = Key:new(keys.pageDown)
local spaceref = Key:new(keys.space)
local dref     = Key:new(keys.d)
local jref     = Key:new(keys.j)
local bref     = Key:new(keys.b)
local uref     = Key:new(keys.u)
local kref     = Key:new(keys.k)
local qref     = Key:new(keys.q)
local enterref = Key:new(keys.enter)
local colonref = Key:new(keys.semiColon or keys.semicolon, false, true)

local function exit_more()
    in_more = false
    more_help_long = false
    -- pop our handler
    table.remove(Command.override_emitter)
    table.remove(Command.emitter_names)
    -- done with the transient messages area
    displaymessages = {}
    mark_display_dirty()
    what_redraw["all"] = true
    need_redraw = true
end

local function readMore(ch)
    if not in_more then return end

    local max_lines = screen.height - 1
    local half      = math.max(1, math.floor(max_lines / 2))

    if ch == spaceref or ch == pgdnref then
        more_top = more_top + max_lines
    elseif ch == dref then
        more_top = more_top + half
    elseif ch == jref or ch == downref then
        more_top = more_top + 1
    elseif ch == bref or ch == pgupref then
        more_top = more_top - max_lines
    elseif ch == uref then
        more_top = more_top - half
    elseif ch == kref or ch == upref then
        more_top = more_top - 1
    elseif ch == qref then
        exit_more()
        return
    elseif ch == colonref then
        CmdRead.read()
    else
        -- Unsupported key: show long help, keep position.
        more_help_long = true
        draw_more_page()
        return
    end

    -- Accepted key: revert to short prompt and redraw.
    more_help_long = false
    draw_more_page()
end

local function exit_readEnter()
    in_press_enter = false
    table.remove(Command.override_emitter)
    table.remove(Command.emitter_names)
    displaymessages = {}
    mark_display_dirty()
    what_redraw["all"] = true
    need_redraw = true
end

local function readEnter(ch)
    if ch == enterref then
        exit_readEnter()
    elseif ch == colonref then
        CmdRead.read()
    end
end

local function start_more()
    in_more = true
    in_press_enter = false
    more_top = 1
    more_help_long = false

    -- If the hit-enter handler is currently on top, pop it cleanly.
    local top = Command.override_emitter[#Command.override_emitter]
    if top == readEnter then
        table.remove(Command.override_emitter)
        table.remove(Command.emitter_names)
    end

    -- Install the MoreMessage handler once (avoid stacking duplicates).
    top = Command.override_emitter[#Command.override_emitter]
    if top ~= readMore then
        Command.override_emitter[#Command.override_emitter + 1] = readMore
        Command.emitter_names[#Command.emitter_names + 1] = "ExMsg.readMore"
    end

    draw_more_page()
end

-- Redraw the Press ENTER area based on current displaymessages/screenlines only.
-- Pure drawing: does NOT change in_press_enter/in_more or handlers.
local function draw_press_enter()
    calculateScreenLines()

    local cmdheight = options.get("cmdheight")
    local offset = (#screenlines > cmdheight) and -1 or 0
    local cmdread_active = CmdRead.is_active()

    -- Clear the area we're about to draw (bottom-aligned)
    Highlight.SetFor("Normal")
    local toclear = #screenlines
    if #screenlines > cmdheight then
        toclear = toclear + 1
    end
    for i = 1, toclear do
        term.setCursorPos(1, screen.height - i + 1 + offset)
        term.clearLine()
    end

    -- Draw the message lines, bottom-up
    for i = 1, #screenlines do
        term.setCursorPos(1, screen.height - i + 1 + offset)
        local triad = screenlines[#screenlines - i + 1]
        term.blit(triad[1], triad[2], triad[3])
    end

    -- If this is a true press-enter case, paint the prompt + separator.
    if #screenlines > cmdheight then
        term.setCursorPos(1, screen.height)
        term.clearLine()
        if cmdread_active then
            CmdRead.drawCmdline()
        else
            Highlight.SetFor("Question")
            term.write("Press ENTER or type command to continue")
        end

        term.setCursorPos(1, screen.height - #screenlines - 1)
        Highlight.SetFor("MsgSeparator")
        term.write(string.rep(" ", screen.width))
    elseif cmdread_active then
        CmdRead.drawCmdline()
    end

    -- May or may not work reliably to fix redraw. TODO: test this
    what_redraw["commandline"] = false
end


-- Draw current messages and, if needed, the Press ENTER prompt.
-- Also enforces the "MoreMessage" threshold.
local function draw_messages_and_prompt()
    if #displaymessages == 0 then return end

    -- Ensure screenlines are current for logic checks; draw_press_enter() reuses the cache.
    calculateScreenLines()

    local cmdheight = options.get("cmdheight")

    -- Escalate to MoreMessage if we would consume the bottom status line.
    if #screenlines > (screen.height - 1) then
        in_press_enter = false
        start_more() -- pops hit-enter if needed; installs pager
        return
    end

    if #screenlines > cmdheight then
        -- Enter/maintain Press ENTER mode (logic only: state & handler)
        in_press_enter = true

        if not CmdRead.is_active() then
            local top = Command.override_emitter[#Command.override_emitter]
            if top ~= readEnter then
                table.insert(Command.override_emitter, readEnter)
                table.insert(Command.emitter_names, "ExMsg.readEnter")
            end
        end

        -- Pure draw into the current target (front or back buffer)
        draw_press_enter()
    else
        -- No Press ENTER required; draw these messages as part of the next
        -- tabpage render (to the back buffer) then clear. Avoid drawing here,
        -- as the double-buffer swap would wipe front-buffer output.
        in_press_enter = false
        pending_one_shot = true
        what_redraw["commandline"] = true
        need_redraw = true
    end
end


function ExMsg.Redraw()
    if in_more then
        draw_more_page(false)
    elseif in_press_enter then
        draw_press_enter()
    end
end

function ExMsg.DrawOneShot()
    if pending_one_shot and #displaymessages > 0 then
        -- Draw the one-shot messages into the current buffer (tabpage back buffer)
        draw_press_enter()
        -- Clear after drawing once
        pending_one_shot = false
        displaymessages = {}
        mark_display_dirty()
        return true
    end
    return false
end

-- Return true when an ExMsg UI overlay is active (More/Press ENTER), which
-- occupies the lower message/cmdline region and should not be overwritten by
-- other renderers in the same frame.
function ExMsg.IsOverlayActive()
    return in_more or in_press_enter
end

local function emit(str, hlgroup, nonewline, flush, savetomsg)
    if flush then
        ExMsg.flush()
    end

    if ui_suppressed() then
        redir_emit(str, nonewline)
        -- Suppress UI/history but still honor capture_stack.
        if #capture_stack > 0 then
            for _, cap in ipairs(capture_stack) do
                if hlgroup == "ErrorMsg" and not nonewline then
                    cap.last_err = str
                else
                    if nonewline then
                        cap.partial = (cap.partial or "") .. str
                    else
                        capture_flush_partial(cap)
                        cap.out[#cap.out + 1] = str .. "\n"
                        cap.saw_full_line = true
                    end
                end
            end
        end
        return
    end

    local eff = silence_effect()

    -- When silent and non-error (or error with skip_errors), swallow UI/history but still honor capture_stack.
    if eff and eff.kind == 'silent' then
        local is_error = (hlgroup == "ErrorMsg")
        local let_through_error = (is_error and not eff.skip_errors)
        if not let_through_error then
            redir_emit(str, nonewline)
            -- Swallow message from UI/history, but add to capture per semantics
            if #capture_stack > 0 then
                for _, cap in ipairs(capture_stack) do
                    if is_error and not nonewline then
                        cap.last_err = str
                    else
                        if nonewline then
                            cap.partial = (cap.partial or "") .. str
                        else
                            capture_flush_partial(cap)
                            cap.out[#cap.out + 1] = str .. "\n"
                            cap.saw_full_line = true
                        end
                    end
                end
            end
            -- If this was an error and we are skipping errors, notify the silent on_error hook.
            if is_error and eff.skip_errors then
                LOG_DEBUG("silent error suppressed: %s", tostring(str))
                if eff.on_error then
                    pcall(eff.on_error, str)
                end
            end
            return
        end
        -- else: fall through to normal UI handling for non-skipped errors,
        -- and lift the silent so subsequent messages are not silent.
        lift_current_silent()
    end

    if nonewline then
        echon[#echon + 1] = { hlgroup, str }
    else
        displaymessages[#displaymessages + 1] = { { hlgroup, str } }
        mark_display_dirty()
        if savetomsg then
            ExMsg.messages[#ExMsg.messages + 1] = { hlgroup, str }
        end
    end
    if in_press_enter then
        draw_messages_and_prompt()
    end

    if in_more then
        draw_more_page(true)
    end

    redir_emit(str, nonewline)

    -- Capture handling (post UI logic to ensure capture sees same segmentation)
    if #capture_stack > 0 then
        for _, cap in ipairs(capture_stack) do
            if hlgroup == "ErrorMsg" and not nonewline then
                -- Track only last error; do not append to normal output
                cap.last_err = str
            else
                if nonewline then
                    cap.partial = (cap.partial or "") .. str
                else
                    -- New full line; flush any pending partial first
                    capture_flush_partial(cap)
                    cap.out[#cap.out + 1] = str .. "\n"
                    cap.saw_full_line = true
                end
            end
        end
    end
end

function ExMsg.echoerr(message)
    emit(message, "ErrorMsg", false, true, true)
end

function ExMsg.echo(message)
    emit(message, current_hl, false, true, false)
end

function ExMsg.echohl(group)
    if not group or group == "" or group:lower() == "none" then
        current_hl = "Normal"
    else
        current_hl = tostring(group)
    end
end

function ExMsg.echon(message)
    emit(message, current_hl, true, false, false)
end

function ExMsg.echomsg(message)
    emit(message, current_hl, false, true, true)
end

function ExMsg._writeWithHL(message, group)
    emit(message, group, false, true, false)
end

-- Flushes any pending `echon` to the display buffer.
function ExMsg.flush()
    if #echon > 0 then
        if not ui_suppressed() then
            displaymessages[#displaymessages + 1] = echon
            mark_display_dirty()
        end
    end
    echon = {}

    -- Flush any partial capture lines (mirrors promotion of echon -> display line)
    if #capture_stack > 0 then
        for _, cap in ipairs(capture_stack) do
            capture_flush_partial(cap)
        end
    end

    redir_flush_partial()
end

function ExMsg.exitRead()
    if in_more then
        exit_more()
    elseif in_press_enter then
        exit_readEnter()
    end
end

-- Marks the end of a script, where the user may resume their control of the program.
-- Flushes any pending `echon` and passes control to the MoreMessage handler.
function ExMsg.Finalize()
    if not windows[curwin] then
        -- We likely are exiting. In any case, we can't do much here
        return
    end

    ExMsg.flush()

    if in_more then
        -- Already paging; just refresh the view with any flushed lines.
        draw_more_page(false)
        return
    end

    if #displaymessages > 0 then
        draw_messages_and_prompt()
    end
end

return ExMsg
