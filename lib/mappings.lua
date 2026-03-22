-- Loads all the default mappings for the Command processor.

local Command = loadModule("lib.command")
local Key = loadModule("lib.key")
local Event = loadModule("lib.event")
local WordNav = loadModule("lib.wordnav")
local Syntax = loadModule("lib.syntax")
local CmdRead = loadModule("lib.excmd.cmdread")
local ExMsg = loadModule("lib.excmd.exmsg")
local Utf8 = loadModule("lib.utf8")
local Backend = loadModule("lib.backend")

local function K(k, c, s, a) return Key:new(k, c, s, a) end

local function push_register(regtype, value)
    registers["unnamed"] = { regtype, value }
    for i = 8, 2, -1 do
        registers[i] = registers[i - 1]
    end
    registers[1] = { regtype, value }
end

local function _mov_dn(n)
    windows[curwin]:cursorMove(0, n or 1)
end
local function _mov_up(n)
    windows[curwin]:cursorMove(0, n and -n or -1)
end
local function _mov_lt(n)
    windows[curwin]:cursorMove(n and -n or -1, 0)
end
local function _mov_rt(n)
    windows[curwin]:cursorMove(n or 1, 0)
end

Command.nimap_builtin_callback({ K(keys.down) }, _mov_dn)
Command.nimap_builtin_callback({ K(keys.up) }, _mov_up)
Command.nimap_builtin_callback({ K(keys.left) }, _mov_lt)
Command.nimap_builtin_callback({ K(keys.right) }, _mov_rt)
Command.nmap_builtin_callback({ K(keys.j) }, _mov_dn)
Command.nmap_builtin_callback({ K(keys.k) }, _mov_up)
Command.nmap_builtin_callback({ K(keys.h) }, _mov_lt)
Command.nmap_builtin_callback({ K(keys.l) }, _mov_rt)
Command.nmap_builtin_callback({ K(keys.p, true) }, _mov_up)
Command.nmap_builtin_callback({ K(keys.j, true) }, _mov_dn)
Command.nmap_builtin_callback({ K(keys.n, true) }, _mov_dn)

Command.nmap_builtin_callback(
    { K(keys.g), K(keys.g) },
    function(count)
        local win = windows[curwin]
        win:cursorSetY(count or 1)
        if options.get("startofline") then
            win:cursorToFirstNonBlank()
        else
            win:cursorSetX(0)
        end
    end
)

Command.nmap_builtin_callback(
    { K(keys.g), K(keys.j) },
    function(count)
        windows[curwin]:cursorMoveScreen(count or 1)
    end
)

Command.nmap_builtin_callback(
    { K(keys.g), K(keys.k) },
    function(count)
        windows[curwin]:cursorMoveScreen(count and (count * -1) or -1)
    end
)

Command.nmap_builtin_callback(
    { K(keys.g, false, true) },
    function(count)
        local win = windows[curwin]
        win:cursorSetY(count or win.buffer:line_count(true))
        win:cursorApplyStartofline()
    end
)

Command.nmap_builtin_callback(
    { K(keys.h, false, true) },
    function(count)
        local win = windows[curwin]
        win:cursorSetScreenRow(count or 0, { startofline = options.get("startofline") })
    end
)

Command.nmap_builtin_callback(
    { K(keys.m, false, true) },
    function(count)
        local win = windows[curwin]
        count = count or 1
        local row = (math.floor(win:textheight() / 2)) - 1 + count
        win:cursorSetScreenRow(row, { startofline = options.get("startofline") })
    end
)

Command.nmap_builtin_callback(
    { K(keys.l, false, true) },
    function(count)
        local win = windows[curwin]
        count = count or 1
        local row = (win:textheight()) - 1 - count
        win:cursorSetScreenRow(row, { startofline = options.get("startofline") })
    end
)

Command.nmap_builtin_callback(
    { K(keys.zero) },
    function()
        local win = windows[curwin]
        win:cursorMove(-win.cursorx + 1, 0)
    end
)

Command.nmap_builtin_callback(
    { K(keys.x) },
    function(count)
        local win = windows[curwin]
        local buf = win.buffer
        local lines = buf:lines_ref(true)
        local n = (count or 1)
        if n <= 0 then return end

        local y, x = win.cursory, win.cursorx
        local out = {}

        local function splice_line(idx, left, right)
            buf:set_line(idx, left .. right, true)
            Syntax.ParseLinetypes(buf, idx)
        end

        while n > 0 do
            local line = lines[y]
            if not line then break end
            local len = Utf8.len(line)

            if x <= len then
                -- Delete min(n, remaining chars in this line from x)
                local take = math.min(n, len - x + 1)
                out[#out + 1] = Utf8.sub(line, x, x + take - 1)
                splice_line(y, Utf8.sub(line, 1, x - 1), Utf8.sub(line, x + take))
                n = n - take
            else
                -- Cursor is at virtual EOL: need to consume a newline (if exists)
                if not lines[y + 1] then break end
                if n == 0 then break end
                out[#out + 1] = "\n"
                n = n - 1
                local removed = buf:remove_lines(y + 1, y + 1)
                local nextline = removed[1]
                buf:set_line(y, lines[y] .. nextline, true)
                Syntax.ParseLinetypes(buf, y)
            end
        end

        if #out > 0 then
            registers["unnamed"] = { "inline", out }
            registers["-"] = { "inline", out }
        end

        local new_len = Utf8.len(lines[y])
        if x > new_len + 1 then x = new_len + 1 end
        win:cursorSetX(x)
        win:cursorSetY(y)
        win:mark_redraw()
    end
)

-- TODO: this mapping is incomplete
Command.nmap_builtin_callback(
    { K(keys.apostrophe, false, true), K(keys.minus, false, true), K(keys.x) },
    function()
        local win = windows[curwin]
        local buf = win.buffer
        local lines = buf:lines_ref(true)
        local line = lines[win.cursory]
        buf:set_line(win.cursory, Utf8.sub(line, 1, win.cursorx - 1) .. Utf8.sub(line, win.cursorx + 1))
        Syntax.ParseLinetypes(buf, win.cursory)
        win:cursorMove(0, 0)
    end
)


Command.nmap_builtin_callback(
    { K(keys.five, false, true) },
    function(count)
        if count then
            local win = windows[curwin]
            win:cursorSetY(math.floor((count * win.buffer:line_count(true) + 99) / 100))
            win:cursorApplyStartofline()
        else
            windows[curwin]:matchPairs()
        end
    end
)

Command.nmap_builtin_callback(
    { K(keys.e, true) },
    function()
        windows[curwin]:scroll(0, 1)
    end
)
Command.nmap_builtin_callback(
    { K(keys.y, true) },
    function()
        windows[curwin]:scroll(0, -1)
    end
)

-- TODO: <C-b>, <C-f>, <pageDown> and <pageUp> should set the cursor to either be 5 lines from the top
-- or 4 lines from the bottom, depending on direction scrolled. If no space is available, use the
-- closest line.
local function _spage_dn()
    local w = windows[curwin]; w:scroll(0, math.max(w:textheight() - 2, 1))
end
local function _spage_up()
    local w = windows[curwin]; w:scroll(0, math.min(-w:textheight() + 2, -1))
end
Command.nmap_builtin_callback({ K(keys.b, true) }, _spage_up)
Command.nmap_builtin_callback({ K(keys.f, true) }, _spage_dn)
Command.nmap_builtin_callback({ K(keys.pageUp) }, _spage_up)
Command.nmap_builtin_callback({ K(keys.pageDown) }, _spage_dn)

-- TODO: scroll options
local function _scroll_half(dir)
    local win = windows[curwin]
    local cur_row = win:cursorScreenRow()
    win:scroll(0, dir * math.floor(win:textheight() / 2))
    win:cursorSetScreenRow(cur_row, { startofline = options.get("startofline") })
end
Command.nmap_builtin_callback(
    { K(keys.d, true) },
    function()
        _scroll_half(1)
    end
)
Command.nmap_builtin_callback(
    { K(keys.u, true) },
    function()
        _scroll_half(-1)
    end
)

Command.nmap_builtin_callback(
    { K(keys.u) },
    function(count)
        local win = windows[curwin]
        win.buffer:undo(win, count or 1)
        win:mark_redraw()
    end
)
Command.nmap_builtin_callback(
    { K(keys.r, true) },
    function(count)
        local win = windows[curwin]
        win.buffer:redo(win, count or 1)
        win:mark_redraw()
    end
)
Command.nmap_builtin_callback(
    { K(keys.u, false, true) },
    function()
        local win = windows[curwin]
        win.buffer:undo_line(win)
        win:mark_redraw()
    end
)

Command.nmap_builtin_callback(
    { K(keys.p) },
    function()
        return windows[curwin]:pasteRegister("unnamed", nil, nil, false)
    end
)
Command.nmap_builtin_callback(
    { K(keys.p, false, true) },
    function()
        return windows[curwin]:pasteRegister("unnamed", nil, nil, true)
    end
)

Command.nmap_builtin_callback(
    { K(keys.backspace) },
    function()
        windows[curwin]:cursorMove(-1, 0)
    end
)

Command.nmap_builtin_callback(
    { K(keys.i) },
    function()
        setMode("insert")
    end
)

Command.nmap_builtin_callback(
    { K(keys.i, false, true) },
    function()
        setMode("insert", 1)
    end
)

Command.nmap_builtin_callback(
    { K(keys.a) },
    function()
        local win = windows[curwin]
        setMode("insert", win.cursorx + 1, win.cursory)
    end
)

Command.nmap_builtin_callback(
    { K(keys.a, false, true) },
    function()
        local win = windows[curwin]
        setMode("insert", win.buffer:line_len(win.cursory, true) + 1, win.cursory)
    end
)

local function _open_line(win, below)
    local buf = win.buffer
    local new_line = win.cursory + (below and 1 or 0)
    buf:insert_line(new_line, "", true)
    Syntax.ParseLinetypes(buf, new_line)
    if win:indentkeysHasOpenTrigger(below and "o" or "O") or options.get("autoindent", nil, buf) then
        win:reindentLine(new_line, win:computeIndentForLine(new_line), 1)
    end
    win.need_redraw = true
    setMode("insert", 1, new_line)
end
Command.nmap_builtin_callback(
    { K(keys.o) },
    function()
        _open_line(windows[curwin], true)
    end
)
Command.nmap_builtin_callback(
    { K(keys.o, false, true) },
    function()
        _open_line(windows[curwin], false)
    end
)

Command.nmap_builtin_callback(
    { K(keys.d), K(keys.d) },
    function(count)
        local win = windows[curwin]
        local buf = win.buffer

        local lines = buf:remove_lines(win.cursory, win.cursory + (count or 1) - 1)

        if #lines == 0 then
            lines[1] = ""
        end

        push_register("linewise", lines)

        Syntax.ParseLinetypes(buf, win.cursory)

        win:cursorMove(-win.cursorx, -1)
    end
)

Command.nmap_builtin_callback(
    { K(keys.j, false, true) },
    function(count)
        count = count and math.max(count - 1, 1) or 1

        local win = windows[curwin]
        local buf = win.buffer

        for _ = 1, count do
            local toinsert = buf:get_line(win.cursory, true)
            if toinsert then
                local removed = buf:remove_lines(win.cursory + 1, win.cursory + 1)
                buf:set_line(win.cursory, (buf:get_line(win.cursory, true) or "") .. " " .. (removed[1] or toinsert))
            end
        end

        Syntax.ParseLinetypes(buf, win.cursory)

        win:mark_redraw()
    end
)

Command.nmap_builtin_callback(
    { K(keys.g), K(keys.j, false, true) },
    function(count)
        count = count and math.max(count - 1, 1) or 1

        local win = windows[curwin]
        local buf = win.buffer

        for _ = 1, count do
            local toinsert = buf:get_line(win.cursory + 1, true)
            if toinsert then
                local removed = buf:remove_lines(win.cursory + 1, win.cursory + 1)
                buf:set_line(win.cursory, (buf:get_line(win.cursory, true) or "") .. (removed[1] or toinsert))
            end
        end

        Syntax.ParseLinetypes(buf, win.cursory)

        win:mark_redraw()
    end
)

Command.nmap_builtin_callback(
    { K(keys.four, false, true) },
    function(count)
        local win = windows[curwin]
        local line = win.buffer:get_line(win.cursory, true)
        if line then
            win:cursorMove(Utf8.len(line), math.max(0, count and (count - 1) or 0))
        end

        -- TODO: this should be set to the max virtual column, but that's not implemented yet
        win._held_vx = math.huge
    end
)

Command.nmap_builtin_callback(
    { K(keys.six, false, true) },
    function()
        local win = windows[curwin]
        local line = win.buffer:get_line(win.cursory, true)
        if line then
            local idx = line:find("%S")
            if idx then
                local col = Utf8.col_from_byte(line, idx)
                win:cursorMove(col - win.cursorx, 0)
            end
        end
    end
)

Command.nmap_builtin_callback(
    { K(keys.g), K(keys.minus, false, true) },
    function(count)
        local win = windows[curwin]
        local line = win.buffer:get_line(win.cursory, true) or ""
        local idx_byte = line:match("()%S%s*$")
        if idx_byte then
            local idx = Utf8.col_from_byte(line, idx_byte)
            win:cursorMove(idx - win.cursorx, math.max(0, count and (count - 1) or 0))
        end
    end
)

Command.nmap_builtin_callback(
    { K(keys.z), K(keys.t) },
    function(count)
        local win = windows[curwin]
        if count then
            win:cursorSetY(count)
            win:cursorApplyStartofline()
        end

        if win.opts.wrap then
            local _, params = win:_wrap_params()
            local cur_row = win:_wrap_cursor_pos(params)
            win:_wrap_scroll_rows(cur_row, params)
        else
            win.scrolly[1] = win.cursory
            win.scrolly[2] = 0
        end
        win:mark_redraw()
    end
)

Command.nmap_builtin_callback(
    { K(keys.z), K(keys.z) },
    function()
        local win = windows[curwin]
        local text_w = win:textwidth()
        if text_w <= 0 then return end

        local rows = win:textheight()
        local hscroll = win.scrollx or 1
        if hscroll < 1 then hscroll = 1 end

        local target_col = hscroll + math.floor((text_w - 1) / 2)
        local target_row = math.floor((rows - 1) / 2)
        win:cursorSetScreenRow(target_row, { screen_col = target_col })
    end
)

Command.nmap_builtin_callback(
    { K(keys.z), K(keys.b) },
    function(count)
        local win = windows[curwin]
        if count then
            win:cursorSetY(count)
            win:cursorApplyStartofline()
        end

        local target_row = math.max(0, win:textheight() - 1)
        if win.opts.wrap then
            local _, params = win:_wrap_params()
            local cur_row = win:_wrap_cursor_pos(params)
            win:_wrap_scroll_rows(cur_row - target_row, params)
        else
            local top = win.cursory - target_row
            local linecnt = win.buffer:line_count(true)
            if top < 1 then top = 1 end
            if top > linecnt then top = linecnt end
            win.scrolly[1] = top
            win.scrolly[2] = 0
        end
        win:mark_redraw()
    end
)

local function _wnav(fn, big, at_end)
    return function(count)
        local win = windows[curwin]
        local line, col = fn(win, big, at_end, count or 1)
        if line and col then win:cursorSet(col, line) end
    end
end
Command.nmap_builtin_callback({ K(keys.w) }, _wnav(WordNav.posNext, false, false))
Command.nmap_builtin_callback({ K(keys.right, false, true) }, _wnav(WordNav.posNext, false, false))
Command.nmap_builtin_callback({ K(keys.w, false, true) }, _wnav(WordNav.posNext, true, false))
Command.nmap_builtin_callback({ K(keys.right, true) }, _wnav(WordNav.posNext, true, false))
Command.nmap_builtin_callback({ K(keys.e) }, _wnav(WordNav.posNext, false, true))
Command.nmap_builtin_callback({ K(keys.e, false, true) }, _wnav(WordNav.posNext, true, true))
Command.nmap_builtin_callback({ K(keys.b) }, _wnav(WordNav.posPrev, false, false))
Command.nmap_builtin_callback({ K(keys.left, false, true) }, _wnav(WordNav.posPrev, false, false))
Command.nmap_builtin_callback({ K(keys.b, false, true) }, _wnav(WordNav.posPrev, true, false))
Command.nmap_builtin_callback({ K(keys.left, true) }, _wnav(WordNav.posPrev, true, false))
Command.nmap_builtin_callback({ K(keys.g), K(keys.e) }, _wnav(WordNav.posPrev, false, true))
Command.nmap_builtin_callback({ K(keys.g), K(keys.e, false, true) }, _wnav(WordNav.posPrev, true, true))

Command.nmap_builtin_callback({ K(keys.h, true) }, _mov_lt)
Command.nmap_builtin_callback({ K(keys.space) }, _mov_rt)

local function _cur_fnb(delta)
    local w = windows[curwin]
    w:cursorSetY(w.cursory + delta)
    w:cursorToFirstNonBlank()
end
Command.nmap_builtin_callback(
    { K(keys.minus) },
    function(count)
        _cur_fnb(-(count or 1))
    end
)
Command.nmap_builtin_callback(
    { K(keys.equals, false, true) },
    function(count)
        _cur_fnb(count or 1)
    end
)
Command.nmap_builtin_callback(
    { K(keys.minus, false, true) },
    function(count)
        _cur_fnb((count or 1) - 1)
    end
)

Command.nmap_builtin_callback(
    { K(keys.g), K(keys.t) },
    function(count)
        tabpages[curtp].lastwin = curwin

        if count then
            curtp = tabpages[curtp]:ordinal_all(count)
        else
            curtp = tabpages[curtp]:wrap_offset_all(curtp, 1)
        end

        enterWindow(tabpages[curtp].lastwin or tabpages[curtp].windows[1].winnr)

        what_redraw["all"] = true
        need_redraw = true
    end
)

Command.nmap_builtin_callback(
    { K(keys.g), K(keys.t, false, true) },
    function(count)
        tabpages[curtp].lastwin = curwin

        local step = count or 1
        curtp = tabpages[curtp]:wrap_offset_all(curtp, -step)

        enterWindow(tabpages[curtp].lastwin or tabpages[curtp].windows[1].winnr)

        what_redraw["all"] = true
        need_redraw = true
    end
)

Command.nmap_builtin_callback(
    { K(keys.y), K(keys.y) },
    function(count)
        local win = windows[curwin]
        local buflines = win.buffer:lines_ref(true)

        local lines = {}
        for i = 1, count or 1 do
            table.insert(lines, buflines[win.cursory + i - 1])
        end

        push_register("linewise", lines)
    end
)

Command.nmap_builtin_callback(
    { K(keys.semiColon or keys.semicolon, false, true) },
    function()
        CmdRead.read()
        what_redraw["commandline"] = true
        need_redraw = true
    end
)

Command.nmap_builtin_callback(
    { K(keys.g, true) },
    function()
        local win = windows[curwin]
        local buf = win.buffer

        local bn = "\"" .. (buf.name or "[No Name]") .. "\""
        local line_count = buf:line_count(true)
        local lines
        if line_count > 0 then
            lines = tostring(line_count) .. " line" .. (line_count > 1 and "s " or " ")
        else
            lines = "--No lines in buffer--"
        end

        local scroll
        if line_count > 0 then
            scroll = "--" .. tostring(math.floor(win.cursory / line_count * 100)) .. "%--"
        else
            scroll = ""
        end

        ExMsg.echo(bn .. " " .. (buf.opts.modified and "[Modified] " or "") .. lines .. scroll)
    end
)



-- Normal mode operators

Command.nmap_builtin_operator_with_motions(
    { K(keys.d) },
    function(total, motion_name)
        local win = windows[curwin]
        local buf = win.buffer

        total = total or 1

        if motion_name == "$" then
            local lines = {}
            lines[1] = Utf8.sub(buf:get_line(win.cursory, true), win.cursorx)
            buf:set_line(win.cursory, Utf8.sub(buf:get_line(win.cursory, true), 1, win.cursorx - 1))

            if total > 1 then
                local removed = buf:remove_lines(win.cursory + 1, win.cursory + total - 1)
                for i = 1, #removed do
                    lines[#lines + 1] = removed[i]
                end
            end

            Syntax.ParseLinetypes(buf, win.cursory)

            push_register("inline", lines)

            win:mark_redraw()
        elseif motion_name == "w" then
            local collected = {}
            local remaining = total
            while remaining > 0 do
                local line = buf:get_line(win.cursory, true)
                if not line or win.cursorx > Utf8.len(line) then break end

                local ly, sx, ex = WordNav.wordUnder(win, false, win.cursory, win.cursorx)
                if not ly then
                    -- Not on a word; try to advance to next word start; if none, stop
                    local ny, nx = WordNav.posNext(win, false, false, 1, win.cursory, win.cursorx)
                    if not ny then break end
                    win:cursorSetY(ny)
                    win:cursorSetX(nx)
                    ly, sx, ex = WordNav.wordUnder(win, false, ny, nx)
                    if not ly then break end
                    line = buf:get_line(ly, true)
                end

                -- Deletion starts at current cursor position within the word
                local del_start = win.cursorx
                if del_start < sx then del_start = sx end -- safety
                if del_start > ex then
                    -- Cursor past end of word (shouldn't happen), move to next word
                    local ny, nx = WordNav.posNext(win, false, false, 1, win.cursory, win.cursorx)
                    if not ny then break end
                    win:cursorSetY(ny); win:cursorSetX(nx)
                    goto continue_loop
                end

                local del_end = ex
                -- Look for following whitespace run
                local i = ex + 1
                local len = Utf8.len(line)
                while i <= len and (Utf8.char_at(line, i) == ' ' or Utf8.char_at(line, i) == '\t') do
                    i = i + 1
                end
                if i > ex + 1 then
                    -- There was trailing whitespace; include it
                    del_end = i - 1
                end

                local removed = Utf8.sub(line, del_start, del_end)
                table.insert(collected, removed)
                buf:set_line(
                    win.cursory,
                    Utf8.sub(line, 1, del_start - 1) .. Utf8.sub(line, del_end + 1),
                    true
                )
                Syntax.ParseLinetypes(buf, win.cursory)
                -- Keep cursor at del_start (or clamp to line length)
                local new_line = buf:get_line(win.cursory, true)
                local new_len = Utf8.len(new_line)
                if del_start > new_len then
                    win:cursorSetX(new_len + 1) -- allow position after end
                else
                    win:cursorSetX(del_start)
                end

                remaining = remaining - 1
                ::continue_loop::
            end

            if #collected > 0 then
                push_register("inline", collected)
            end

            Syntax.ParseLinetypes(buf, win.cursory)
            win:mark_redraw()
        end

        win:cursorMove(0, 0)
    end,
    {
        ["w"] = { K(keys.w) },
        ["$"] = { K(keys.four, false, true) },
        ["e"] = { K(keys.e) },
    }
)

Command.nmap_builtin_operator_with_motions(
    { K(keys.c) },
    function(total, motion_name)
        local win = windows[curwin]
        local buf = win.buffer

        if motion_name == "$" then
            local lines = {}
            lines[1] = Utf8.sub(buf:get_line(win.cursory, true), win.cursorx)
            buf:set_line(win.cursory, Utf8.sub(buf:get_line(win.cursory, true), 1, win.cursorx - 1))

            if total > 1 then
                local removed = buf:remove_lines(win.cursory + 1, win.cursory + total - 1)
                for i = 1, #removed do
                    lines[#lines + 1] = removed[i]
                end
            end

            Syntax.ParseLinetypes(buf, win.cursory)

            push_register("inline", lines)

            setMode("insert")

            win:mark_redraw()
        end
    end,
    {
        ["$"] = { K(keys.four, false, true) }
    }
)

Command.nmap_builtin_operator_with_motions(
    { K(keys.w, true) },
    function(total, motion_name)
        if motion_name == "c-w" then
            motion_name = "w"
        end

        windows[curwin]:wincmd(motion_name, total)
    end,
    {
        ["h"] = { K(keys.h) },
        ["j"] = { K(keys.j) },
        ["k"] = { K(keys.k) },
        ["l"] = { K(keys.l) },
        ["s"] = { K(keys.s) },
        ["v"] = { K(keys.v) },
        ["w"] = { K(keys.w) },
        ["c-w"] = { K(keys.w, true) },
        ["T"] = { K(keys.t, false, true) },
        ["="] = { K(keys.equals) },
        ["|"] = { K(keys.backslash, false, true) },
        [">"] = { K(keys.period, false, true) },
        ["<"] = { K(keys.comma, false, true) },
        ["+"] = { K(keys.equals, false, true) },
        ["-"] = { K(keys.minus) },
        ["_"] = { K(keys.minus, false, true) },
    }
)


-- Insert mode mappings
local function _set_normal() setMode("normal") end
local insert_mode_exit_lhs
if Backend.current().kind == "cc" then
    insert_mode_exit_lhs = { K(keys.tab, true) }
else
    insert_mode_exit_lhs = { K(keys.leftBracket, true) }
end
Command.imap_builtin_callback(insert_mode_exit_lhs, _set_normal)
Command.imap_builtin_callback({ K(keys.c, true) }, _set_normal)


-- DEBUG MAPPINGS
Command.nimap_builtin_callback(
    { K(keys.t, true) },
    function()
        Event.HaltLoop()
    end
)

Command.nmap_builtin_callback(
    { K(keys.c), K(keys.t), K(keys.p) },
    function()
        LOG_DEBUG("Current tabpage: " .. curtp)
    end
)
