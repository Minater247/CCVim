-- Loads all the default mappings for the Command processor.

local Command = loadModule("lib.command")
local Key = loadModule("lib.key")
local Event = loadModule("lib.event")
local Window = loadModule("layout.window")
local Error = loadModule("lib.error")
local WordNav = loadModule("lib.wordnav")
local Syntax = loadModule("lib.syntax")
local Tabpage = loadModule("layout.tabpage")
local CmdRead = loadModule("lib.excmd.cmdread")
local ExMsg = loadModule("lib.excmd.exmsg")

local function K(k, c, s, a) return Key:new(k, c, s, a) end
local function _line_len(buf, s) return buf:str_len(s or "") end
local function _line_sub(buf, s, i, j) return buf:str_sub(s or "", i, j) end
local function _line_ch(buf, s, i) return buf:str_char_at(s or "", i) end

Command.nimap_callback(
    { K(keys.down) },
    function(count)
        windows[curwin]:cursorMove(0, count or 1)
    end)

Command.nimap_callback(
    { K(keys.up) },
    function(count)
        windows[curwin]:cursorMove(0, count and (count * -1) or -1)
    end)

Command.nimap_callback(
    { K(keys.left) },
    function(count)
        windows[curwin]:cursorMove(count and (count * -1) or -1, 0)
    end)

Command.nimap_callback(
    { K(keys.right) },
    function(count)
        windows[curwin]:cursorMove(count or 1, 0)
    end)

Command.nmap_callback(
    { K(keys.j) },
    function(count)
        windows[curwin]:cursorMove(0, count or 1)
    end)

Command.nmap_callback(
    { K(keys.k) },
    function(count)
        windows[curwin]:cursorMove(0, count and (count * -1) or -1)
    end)

Command.nmap_callback(
    { K(keys.h) },
    function(count)
        windows[curwin]:cursorMove(count and (count * -1) or -1, 0)
    end)

Command.nmap_callback(
    { K(keys.l) },
    function(count)
        windows[curwin]:cursorMove(count or 1, 0)
    end)

Command.nmap_callback(
    { K(keys.p, true) },
    function(count)
        windows[curwin]:cursorMove(0, count and (count * -1) or -1)
    end)

Command.nmap_callback(
    { K(keys.j, true) },
    function(count)
        windows[curwin]:cursorMove(0, count or 1)
    end)

Command.nmap_callback(
    { K(keys.n, true) },
    function(count)
        windows[curwin]:cursorMove(0, count or 1)
    end)

Command.nmap_callback(
    { K(keys.g), K(keys.g) },
    function(count)
        local win = windows[curwin]
        win:cursorSetY(count or 1)
        local line = win.buffer:get_line(win.cursory, true)
        if options.get("startofline") and line then
            win:cursorSetX(line:find("%S"))
        else
            win:cursorSetX(0)
        end
    end
)

Command.nmap_callback(
    { K(keys.g), K(keys.j) },
    function(count)
        windows[curwin]:cursorMoveScreen(count or 1)
    end
)

Command.nmap_callback(
    { K(keys.g), K(keys.k) },
    function(count)
        windows[curwin]:cursorMoveScreen(count and (count * -1) or -1)
    end
)

Command.nmap_callback(
    {K(keys.g, false, true)},
    function(count)
        local win = windows[curwin]
	    local buf = win.buffer
        win:cursorSetY(count or buf:line_count(true))
	    local line = buf:get_line(win.cursory, true)
        if options.get("startofline") and line then
            win:cursorSetX(line:find("%S"))
        end
    end
)

Command.nmap_callback(
    {K(keys.h, false, true)},
    function(count)
        local win = windows[curwin]
        win:cursorSetScreenRow(count or 0, { startofline = options.get("startofline") })
    end
)

Command.nmap_callback(
    {K(keys.m, false, true)},
    function(count)
        local win = windows[curwin]
        count = count or 1
        local row = (math.floor(win:textheight() / 2)) - 1 + count
        win:cursorSetScreenRow(row, { startofline = options.get("startofline") })
    end
)

Command.nmap_callback(
    {K(keys.l, false, true)},
    function(count)
        local win = windows[curwin]
        count = count or 1
        local row = (win:textheight()) - 1 - count
        win:cursorSetScreenRow(row, { startofline = options.get("startofline") })
    end
)

Command.nmap_callback(
    {K(keys.zero)},
    function()
        local win = windows[curwin]
        win:cursorMove(-win.cursorx + 1, 0)
    end
)

Command.nmap_callback(
    {K(keys.x)},
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
            local len = _line_len(buf, line)

            if x <= len then
                -- Delete min(n, remaining chars in this line from x)
                local take = math.min(n, len - x + 1)
                out[#out+1] = _line_sub(buf, line, x, x + take - 1)
                splice_line(y, _line_sub(buf, line, 1, x - 1), _line_sub(buf, line, x + take))
                n = n - take
            else
                -- Cursor is at virtual EOL: need to consume a newline (if exists)
                if not lines[y + 1] then break end
                if n == 0 then break end
                out[#out+1] = "\n"
                n = n - 1
                local removed = buf:remove_lines(y + 1, y + 1)
                local nextline = removed[1]
                buf:set_line(y, lines[y] .. nextline, true)
                Syntax.ParseLinetypes(buf, y)
            end
        end

        if #out > 0 then
            registers["unnamed"] = {"inline", out}
            registers["-"] = {"inline", out}
        end

        local new_len = _line_len(buf, lines[y] or "")
        if x > new_len + 1 then x = new_len + 1 end
        win:cursorSetX(x)
        win:cursorSetY(y)
        win.need_redraw = true; need_redraw = true
    end
)

-- TODO: this mapping is incomplete
Command.nmap_callback(
    {K(keys.apostrophe, false, true), K(keys.minus, false, true), K(keys.x)},
    function()
        local win = windows[curwin]
        local buf = win.buffer
        local lines = buf:lines_ref(true)
        local line = lines[win.cursory] or ""
        buf:set_line(win.cursory, _line_sub(buf, line, 1, win.cursorx - 1) .. _line_sub(buf, line, win.cursorx + 1))
        Syntax.ParseLinetypes(buf, win.cursory)
        win:cursorMove(0, 0)
    end
)


Command.nmap_callback(
    {K(keys.five, false, true)},
    function(count)
        if count then
            local win = windows[curwin]
            win:cursorSetY(math.floor((count * win.buffer:line_count(true) + 99) / 100))
            local line = win.buffer:get_line(win.cursory, true)
            if options.get("startofline") and line then
                win:cursorSetX(line:find("%S"))
            end
        else
            windows[curwin]:matchPairs()
        end
    end
)

Command.nmap_callback(
    {K(keys.e, true)},
    function()
        windows[curwin]:scroll(0, 1)
    end
)

Command.nmap_callback(
    {K(keys.y, true)},
    function()
        windows[curwin]:scroll(0, -1)
    end
)

-- TODO: <C-b>, <C-f>, <pageDown> and <pageUp> should set the cursor to either be 5 lines from the top
-- or 4 lines from the bottom, depending on direction scrolled. If no space is available, use the
-- closest line.
Command.nmap_callback(
    {K(keys.b, true)},
    function()
        local win = windows[curwin]
        local amt = math.min(-win:textheight() + 2, -1)
        win:scroll(0, amt)
    end
)

Command.nmap_callback(
    {K(keys.f, true)},
    function()
        local win = windows[curwin]
        local amt = math.max(win:textheight() - 2, 1)
        win:scroll(0, amt)
    end
)

Command.nmap_callback(
    {K(keys.pageUp)},
    function()
        local win = windows[curwin]
        local amt = math.min(-win:textheight() + 2, -1)
        win:scroll(0, amt)
    end
)

Command.nmap_callback(
    {K(keys.pageDown)},
    function()
        local win = windows[curwin]
        local amt = math.max(win:textheight() - 2, 1)
        win:scroll(0, amt)
    end
)

-- TODO: scroll options
Command.nmap_callback(
    {K(keys.d, true)},
    function()
        local win = windows[curwin]
        local amt = math.floor(win:textheight() / 2)
        local cur_row = win:cursorScreenRow()
        win:scroll(0, amt)
        win:cursorSetScreenRow(cur_row, { startofline = options.get("startofline") })
    end
)

Command.nmap_callback(
    {K(keys.u, true)},
    function()
        local win = windows[curwin]
        local amt = math.floor(win:textheight() / 2)
        local cur_row = win:cursorScreenRow()
        win:scroll(0, -amt)
        win:cursorSetScreenRow(cur_row, { startofline = options.get("startofline") })
    end
)

Command.nmap_callback(
    {K(keys.p)},
    function()
        return windows[curwin]:pasteRegister("unnamed", nil, nil, false)
    end
)

Command.nmap_callback(
    {K(keys.p, false, true)},
    function()
        return windows[curwin]:pasteRegister("unnamed", nil, nil, true)
    end
)

Command.nmap_callback(
    {K(keys.backspace)},
    function()
        windows[curwin]:cursorMove(-1, 0)
    end
)

Command.nmap_callback(
    {K(keys.i)},
    function()
        setMode("insert")
    end
)

Command.nmap_callback(
    {K(keys.i, false, true)},
    function()
        setMode("insert", 1)
    end
)

Command.nmap_callback(
    {K(keys.a)},
    function()
        local win = windows[curwin]
        setMode("insert", win.cursorx + 1, win.cursory)
    end
)

Command.nmap_callback(
    {K(keys.a, false, true)},
    function()
        local win = windows[curwin]
        setMode("insert", win.buffer:line_len(win.cursory, true) + 1, win.cursory)
    end
)

Command.nmap_callback(
    {K(keys.o)},
    function()
        local win = windows[curwin]
        local buf = win.buffer
        local new_line = win.cursory + 1
        buf:insert_line(new_line, "", true)

        Syntax.ParseLinetypes(buf, new_line)
        if win:indentkeysHasOpenTrigger("o") or options.get("autoindent", nil, buf) then
            local want = win:computeIndentForLine(new_line)
            win:reindentLine(new_line, want, 1)
        end

        win.need_redraw = true

        setMode("insert", 1, new_line)
    end
)

Command.nmap_callback(
    {K(keys.o, false, true)},
    function()
        local win = windows[curwin]
        local buf = win.buffer
        local new_line = win.cursory
        buf:insert_line(new_line, "", true)

        Syntax.ParseLinetypes(buf, new_line)
        if win:indentkeysHasOpenTrigger("O") or options.get("autoindent", nil, buf) then
            local want = win:computeIndentForLine(new_line)
            win:reindentLine(new_line, want, 1)
        end

        win.need_redraw = true

        setMode("insert", 1, new_line)
    end
)

Command.nmap_callback(
    {K(keys.d), K(keys.d)},
    function(count)
        local win = windows[curwin]
        local buf = win.buffer

        local lines = buf:remove_lines(win.cursory, win.cursory + (count or 1) - 1)

        if #lines == 0 then
            lines[1] = ""
        end

        registers["unnamed"] = {"linewise", lines}
        for i = 8, 2, -1 do
            registers[i] = registers[i - 1]
        end
        registers[1] = {"linewise", lines}

        Syntax.ParseLinetypes(buf, win.cursory)

        win:cursorMove(-win.cursorx, -1)
    end
)

Command.nmap_callback(
    {K(keys.j, false, true)},
    function(count)
        count = count and math.max(count - 1, 1) or 1

        local win = windows[curwin]
        local buf = win.buffer

        for i = 1, count do
            local toinsert = buf:get_line(win.cursory, true)
            if toinsert then
                local removed = buf:remove_lines(win.cursory + 1, win.cursory + 1)
                buf:set_line(win.cursory, (buf:get_line(win.cursory, true) or "") .. " " .. (removed[1] or toinsert))
            end
        end

        Syntax.ParseLinetypes(buf, win.cursory)

        win.need_redraw = true
        need_redraw = true
    end
)

Command.nmap_callback(
    {K(keys.g), K(keys.j, false, true)},
    function(count)
        count = count and math.max(count - 1, 1) or 1

        local win = windows[curwin]
        local buf = win.buffer

        for i = 1, count do
            local toinsert = buf:get_line(win.cursory + 1, true)
            if toinsert then
                local removed = buf:remove_lines(win.cursory + 1, win.cursory + 1)
                buf:set_line(win.cursory, (buf:get_line(win.cursory, true) or "") .. (removed[1] or toinsert))
            end
        end

        Syntax.ParseLinetypes(buf, win.cursory)

        win.need_redraw = true
        need_redraw = true
    end
)

Command.nmap_callback(
    {K(keys.four, false, true)},
    function(count)
        local win = windows[curwin]
        local line = win.buffer:get_line(win.cursory, true)
        if line then
            win:cursorMove(win.buffer:str_len(line), math.max(0, count and (count - 1) or 0))
        end

        -- TODO: this should be set to the max virtual column, but that's not implemented yet
        win._held_vx = math.huge
    end
)

Command.nmap_callback(
    {K(keys.six, false, true)},
    function()
        local win = windows[curwin]
        local line = win.buffer:get_line(win.cursory, true)
        if line then
            local idx = line:find("%S")
            if idx then
                local col = win.buffer:str_col_from_byte(line, idx)
                win:cursorMove(col - win.cursorx, 0)
            end
        end
    end
)

Command.nmap_callback(
    {K(keys.g), K(keys.minus, false, true)},
    function(count)
        local win = windows[curwin]
        local line = win.buffer:get_line(win.cursory, true) or ""
        local idx_byte = line:match("()%S%s*$")
        if idx_byte then
            local idx = win.buffer:str_col_from_byte(line, idx_byte)
            win:cursorMove(idx - win.cursorx, math.max(0, count and (count - 1) or 0))
        end
    end
)

Command.nmap_callback(
    {K(keys.z), K(keys.z)},
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

Command.nmap_callback(
    {K(keys.w)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posNext(win, false, false, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.right, false, true)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posNext(win, false, false, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.w, false, true)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posNext(win, true, false, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.right, true)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posNext(win, true, false, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.e)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posNext(win, false, true, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.e, false, true)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posNext(win, true, true, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.b)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posPrev(win, false, false, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.left, false, true)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posPrev(win, false, false, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.b, false, true)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posPrev(win, true, false, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.left, true)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posPrev(win, true, false, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.g), K(keys.e)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posPrev(win, false, true, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.g), K(keys.e, false, true)},
    function(count)
        local win = windows[curwin]
        local line, col = WordNav.posPrev(win, true, true, count or 1)
        if line and col then
            win:cursorMove(col - win.cursorx, line - win.cursory)
        end
    end
)

Command.nmap_callback(
    {K(keys.h, true)},
    function(count)
        windows[curwin]:cursorMove(count and -count or -1, 0)
    end
)

Command.nmap_callback(
    {K(keys.space)},
    function(count)
        windows[curwin]:cursorMove(count or 1, 0)
    end
)

Command.nmap_callback(
    {K(keys.minus)},
    function(count)
        local win = windows[curwin]
        win:cursorSetY(win.cursory - (count or 1))
        local line = win.buffer:get_line(win.cursory, true)
        if line then
            win:cursorSetX(line:find("%S"))
        end
    end
)

Command.nmap_callback(
    {K(keys.equals, false, true)},
    function(count)
        local win = windows[curwin]
        win:cursorSetY(win.cursory + (count or 1))
        local line = win.buffer:get_line(win.cursory, true)
        if line then
            win:cursorSetX(line:find("%S"))
        end
    end
)

Command.nmap_callback(
    {K(keys.minus, false, true)},
    function(count)
        local win = windows[curwin]
        win:cursorSetY(win.cursory + (count or 1) - 1)
        local line = win.buffer:get_line(win.cursory, true)
        if line then
            win:cursorSetX(line:find("%S"))
        end
    end
)

Command.nmap_callback(
    {K(keys.g), K(keys.t)},
    function(count)
        tabpages[curtp].lastwin = curwin

        if count then
            curtp = math.min(count, #tabpages)
        else
            curtp = (curtp % #tabpages) + 1
        end

        enterWindow(tabpages[curtp].lastwin or tabpages[curtp].windows[1].winnr)

        what_redraw["all"] = true
        need_redraw = true
    end
)

Command.nmap_callback(
    {K(keys.g), K(keys.t, false, true)},
    function(count)
        tabpages[curtp].lastwin = curwin

        local step = (count or 1) % #tabpages
        curtp = ((curtp - 1 - step + #tabpages) % #tabpages) + 1

        enterWindow(tabpages[curtp].lastwin or tabpages[curtp].windows[1].winnr)

        what_redraw["all"] = true
        need_redraw = true
    end
)

Command.nmap_callback(
    {K(keys.y), K(keys.y)},
    function(count)
        local win = windows[curwin]
        local buflines = win.buffer:lines_ref(true)

        local lines = {}
        for i = 1, count or 1 do
            table.insert(lines, buflines[win.cursory + i - 1])
        end

        registers["unnamed"] = {"linewise", lines}
        for i = 8, 2, -1 do
            registers[i] = registers[i - 1]
        end
        registers[1] = {"linewise", lines}
    end
)

Command.nmap_callback(
    {K(keys.semiColon or keys.semicolon, false, true)},
    function()
        CmdRead.read()
        what_redraw["commandline"] = true
        need_redraw = true
    end
)

Command.nmap_callback(
    {K(keys.g, true)},
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

Command.nmap_operator_with_motions(
    {K(keys.d)},
    function(total, motion_name, op_count, mot_count)
        local win = windows[curwin]
        local buf = win.buffer

        total = total or 1

        if motion_name == "$" then
            local lines = {}
            lines[1] = _line_sub(buf, buf:get_line(win.cursory, true) or "", win.cursorx)
            buf:set_line(win.cursory, _line_sub(buf, buf:get_line(win.cursory, true) or "", 1, win.cursorx - 1))

            if total > 1 then
                local removed = buf:remove_lines(win.cursory + 1, win.cursory + total - 1)
                for i = 1, #removed do
                    lines[#lines + 1] = removed[i]
                end
            end

            Syntax.ParseLinetypes(buf, win.cursory)

            registers["unnamed"] = {"inline", lines}
            for i = 8, 2, -1 do
                registers[i] = registers[i - 1]
            end
            registers[1] = {"inline", lines}

            win.need_redraw = true
            need_redraw = true
        elseif motion_name == "w" then
            local collected = {}
            local remaining = total
            while remaining > 0 do
                local line = buf:get_line(win.cursory, true)
                if not line or win.cursorx > _line_len(buf, line) then break end

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
                local len = _line_len(buf, line)
                while i <= len and (_line_ch(buf, line, i) == ' ' or _line_ch(buf, line, i) == '\t') do
                    i = i + 1
                end
                if i > ex + 1 then
                    -- There was trailing whitespace; include it
                    del_end = i - 1
                end

                local removed = _line_sub(buf, line, del_start, del_end)
                table.insert(collected, removed)
                buf:set_line(win.cursory, _line_sub(buf, line, 1, del_start - 1) .. _line_sub(buf, line, del_end + 1), true)
                Syntax.ParseLinetypes(buf, win.cursory)
                -- Keep cursor at del_start (or clamp to line length)
                local new_line = buf:get_line(win.cursory, true)
                local new_len = _line_len(buf, new_line)
                if del_start > new_len then
                    win:cursorSetX(new_len + 1) -- allow position after end
                else
                    win:cursorSetX(del_start)
                end

                remaining = remaining - 1
                ::continue_loop::
            end

            if #collected > 0 then
                registers["unnamed"] = {"inline", collected}
                for i = 8, 2, -1 do
                    registers[i] = registers[i - 1]
                end
                registers[1] = {"inline", collected}
            end

            Syntax.ParseLinetypes(buf, win.cursory)
            win.need_redraw = true
            need_redraw = true
        end

        win:cursorMove(0, 0)
    end,
    {
        ["w"] = {K(keys.w)},
        ["$"] = {K(keys.four, false, true)},
        ["e"] = {K(keys.e)},
    }
)

Command.nmap_operator_with_motions(
    {K(keys.c)},
    function(total, motion_name)
        local win = windows[curwin]
        local buf = win.buffer

        if motion_name == "$" then
            local lines = {}
            lines[1] = _line_sub(buf, buf:get_line(win.cursory, true) or "", win.cursorx)
            buf:set_line(win.cursory, _line_sub(buf, buf:get_line(win.cursory, true) or "", 1, win.cursorx - 1))

            if total > 1 then
                local removed = buf:remove_lines(win.cursory + 1, win.cursory + total - 1)
                for i = 1, #removed do
                    lines[#lines + 1] = removed[i]
                end
            end

            Syntax.ParseLinetypes(buf, win.cursory)

            registers["unnamed"] = {"inline", lines}
            for i = 8, 2, -1 do
                registers[i] = registers[i - 1]
            end
            registers[1] = {"inline", lines}

            setMode("insert")

            win.need_redraw = true
            need_redraw = true
        end
    end,
    {
        ["$"] = {K(keys.four, false, true)}
    }
)

Command.nmap_operator_with_motions(
    {K(keys.w, true)},
    function(total, motion_name)
        if motion_name == "c-w" then
            motion_name = "w"
        end

        windows[curwin]:wincmd(motion_name, total)
    end,
    {
        ["s"] = {K(keys.s)},
        ["v"] = {K(keys.v)},
        ["w"] = {K(keys.w)},
        ["c-w"] = {K(keys.w, true)},
        ["T"] = {K(keys.t, false, true)},
        ["="] = {K(keys.equals)},
        [">"] = {K(keys.period, false, true)},
        ["<"] = {K(keys.comma, false, true)},
        ["+"] = {K(keys.equals, false, true)},
        ["-"] = {K(keys.minus)},
    }
)


-- Insert mode mappings
Command.imap_callback(
    {K(keys.tab, true)},
    function()
        setMode("normal")
    end
)

Command.imap_callback(
    {K(keys.c, true)},
    function()
        setMode("normal")
    end
)


-- DEBUG MAPPINGS
Command.nimap_callback(
    { K(keys.t, true) },
    function()
        Event.HaltLoop()
    end
)

Command.nmap_callback(
    {K(keys.c), K(keys.t), K(keys.p)},
    function()
        LOG_DEBUG("Current tabpage: " .. curtp)
    end
)
