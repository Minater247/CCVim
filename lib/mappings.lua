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
local Visual = loadModule("lib.visual")
local RegisterUtil = loadModule("lib.registers")
local Scopes = loadModule("lib.luaapi.scopes")
local Tab = loadModule("lib.tab")

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

local function _option_has(name, value)
    for item in options.get(name):gmatch("[^,]+") do
        if item == value then return true end
    end
    return false
end

local function _mov_home()
    windows[curwin]:cursorSetX(1)
end

local function _mov_end()
    local win = windows[curwin]
    win:cursorSetX(math.max(1, win.buffer:line_len(win.cursory, true)))
end

local function _mov_page(direction)
    local win = windows[curwin]
    win:cursorMove(0, direction * math.max(win:textheight() - 2, 1))
end

local function _set_visual_register(kind, value, width, target)
    local entry
    if kind == "line" then
        entry = { "linewise", value }
    elseif kind == "block" then
        entry = { "blockwise", value, width }
    else
        entry = { "charwise", value }
    end
    registers["unnamed"] = entry
    registers[0] = entry
    if target then registers[RegisterUtil.storage_key(target)] = entry end
end

local function _selection_text(win, selection)
    local buf = win.buffer
    if selection.kind == "line" then
        local out = {}
        for lnum = selection.start.lnum, selection.finish.lnum do
            out[#out + 1] = buf:get_line(lnum, true)
        end
        return out
    elseif selection.kind == "block" then
        local out = {}
        for lnum = selection.start.lnum, selection.finish.lnum do
            out[#out + 1] = Visual.slice_block_line(selection, buf:get_line(lnum, true))
        end
        return out
    end

    local out = {}
    for lnum = selection.start.lnum, selection.finish.lnum do
        local line = buf:get_line(lnum, true)
        if selection.start.lnum == selection.finish.lnum then
            out[#out + 1] = Utf8.sub(line, selection.start.col, selection.finish.col)
        elseif lnum == selection.start.lnum then
            out[#out + 1] = Utf8.sub(line, selection.start.col)
        elseif lnum == selection.finish.lnum then
            out[#out + 1] = Utf8.sub(line, 1, selection.finish.col)
        else
            out[#out + 1] = line
        end
    end
    return table.concat(out, "\n")
end

local function _linewise_selection(selection)
    return {
        kind = "line",
        anchor = selection.anchor,
        cursor = selection.cursor,
        start = { lnum = selection.start.lnum, col = 1 },
        finish = { lnum = selection.finish.lnum, col = Scopes.MAXCOL },
    }
end

local function _select_charwise_selection(selection, buf)
    if selection.kind ~= "line" then return selection end
    local last = selection.finish.lnum
    if last < buf:line_count(true) then
        return {
            kind = "char",
            anchor = selection.anchor,
            cursor = selection.cursor,
            start = { lnum = selection.start.lnum, col = 1 },
            finish = { lnum = last + 1, col = 0 },
        }
    end
    return {
        kind = "char",
        anchor = selection.anchor,
        cursor = selection.cursor,
        start = { lnum = selection.start.lnum, col = 1 },
        finish = { lnum = last, col = Utf8.len(buf:get_line(last, true)) },
    }
end

local function _yank_visual_selection(force_linewise)
    local win = windows[curwin]
    local selection = Visual.finish(win)
    if force_linewise then
        selection = _linewise_selection(selection)
    end
    Visual.record_operation(win, selection)
    _set_visual_register(
        selection.kind,
        _selection_text(win, selection),
        selection.width
    )
    win:cursorSet(selection.start.col, selection.start.lnum)
    setMode("normal")
end

local function _delete_visual_selection(insert_after, extend_block_to_eol, force_linewise,
    discard_register, target_register)
    local win = windows[curwin]
    local select_charwise = vimmode == "select" or win.select_operator_charwise
    if win.select_operator_charwise then Command.cancel_select_reselect() end
    local selection = Visual.finish(win)
    local visual_selection = selection
    if force_linewise then
        selection = _linewise_selection(selection)
    end
    if select_charwise then
        selection = _select_charwise_selection(selection, win.buffer)
    end
    Visual.record_operation(win, selection)
    if extend_block_to_eol then
        local end_col = selection.finish.col
        for lnum = selection.start.lnum, selection.finish.lnum do
            end_col = math.max(end_col, Utf8.len(win.buffer:get_line(lnum, true)))
        end
        selection.finish.col = end_col
        selection.width = end_col - selection.start.col + 1
    end
    local buf = win.buffer
    if not discard_register then
        _set_visual_register(selection.kind, _selection_text(win, selection), selection.width, target_register)
    end

    if selection.kind == "line" then
        buf:remove_lines(selection.start.lnum, selection.finish.lnum)
        if insert_after then
            buf:insert_line(selection.start.lnum, "", true)
        elseif buf:line_count(true) == 0 then
            buf:insert_line(1, "", true)
        end
    elseif selection.kind == "block" then
        for lnum = selection.start.lnum, selection.finish.lnum do
            local line = buf:get_line(lnum, true)
            local len = Utf8.len(line)
            if len >= selection.start.col then
                buf:set_line(
                    lnum,
                    Utf8.sub(line, 1, selection.start.col - 1)
                        .. Utf8.sub(line, selection.finish.col + 1),
                    true
                )
            end
        end
    else
        local first = buf:get_line(selection.start.lnum, true)
        local last = buf:get_line(selection.finish.lnum, true)
        if selection.start.lnum == selection.finish.lnum then
            buf:set_line(
                selection.start.lnum,
                Utf8.sub(first, 1, selection.start.col - 1)
                    .. Utf8.sub(first, selection.finish.col + 1),
                true
            )
        else
            buf:set_line(
                selection.start.lnum,
                Utf8.sub(first, 1, selection.start.col - 1)
                    .. Utf8.sub(last, selection.finish.col + 1),
                true
            )
            buf:remove_lines(selection.start.lnum + 1, selection.finish.lnum)
        end
    end

    if selection.kind == "char" then
        Visual.update_marks_after_charwise_join(win, selection)
    end
    Syntax.ParseLinetypes(buf, selection.start.lnum)
    if insert_after then
        if selection.kind == "block" then
            Visual.begin_block_change(win, selection)
        end
        setMode("insert", selection.start.col, selection.start.lnum)
    else
        local cursor_col = force_linewise and visual_selection.finish.col or selection.start.col
        win:cursorSet(cursor_col, selection.start.lnum)
        setMode("normal")
    end
    win:mark_redraw()
end

Command.replace_select = function(text)
    local win = windows[curwin]
    local target = win.select_register
    win.select_register = nil
    Command.cancel_select_reselect()
    _delete_visual_selection(true, false, false, target == "_", target ~= "_" and target or nil)
    win:insertText(text)
end

Command.delete_select = function()
    local win = windows[curwin]
    local target = win.select_register
    win.select_register = nil
    Command.cancel_select_reselect()
    _delete_visual_selection(false, false, false, target == "_", target ~= "_" and target or nil)
end

local function _block_insert(append)
    local win = windows[curwin]
    local selection = Visual.finish(win)
    local col = append and (selection.finish.col + 1) or selection.start.col
    Visual.begin_block_insert(win, selection, col)
    setMode("insert", col, selection.start.lnum)
end

local function _put_visual_selection(preserve_register)
    local win = windows[curwin]
    local selection = Visual.finish(win)
    local entry = registers.unnamed
    if not entry then
        return
    end

    local buf = win.buffer
    local selected_text = _selection_text(win, selection)
    local put_selection
    if selection.kind == "char" and entry[1] == "charwise" then
        local line = buf:get_line(selection.start.lnum, true)
        buf:set_line(
            selection.start.lnum,
            Utf8.sub(line, 1, selection.start.col - 1)
                .. RegisterUtil.entry_to_text(entry)
                .. Utf8.sub(line, selection.finish.col + 1),
            true
        )
        put_selection = {
            kind = "char",
            anchor = { lnum = selection.start.lnum, col = selection.start.col },
            cursor = {
                lnum = selection.start.lnum,
                col = selection.start.col + Utf8.len(RegisterUtil.entry_to_text(entry)) - 1,
            },
            start = { lnum = selection.start.lnum, col = selection.start.col },
            finish = {
                lnum = selection.start.lnum,
                col = selection.start.col + Utf8.len(RegisterUtil.entry_to_text(entry)) - 1,
            },
        }
    elseif selection.kind == "line" and entry[1] == "linewise" then
        buf:remove_lines(selection.start.lnum, selection.finish.lnum)
        local lines = entry[2]
        for i = #lines, 1, -1 do
            buf:insert_line(selection.start.lnum, lines[i], true)
        end
        put_selection = {
            kind = "line",
            anchor = { lnum = selection.start.lnum, col = 1 },
            cursor = { lnum = selection.start.lnum + #lines - 1, col = Scopes.MAXCOL },
            start = { lnum = selection.start.lnum, col = 1 },
            finish = { lnum = selection.start.lnum + #lines - 1, col = Scopes.MAXCOL },
        }
    elseif selection.kind == "block" and entry[1] == "charwise" then
        local text = RegisterUtil.entry_to_text(entry)
        for lnum = selection.start.lnum, selection.finish.lnum do
            local line = buf:get_line(lnum, true)
            buf:set_line(
                lnum,
                Utf8.sub(line, 1, selection.start.col - 1)
                    .. text
                    .. Utf8.sub(line, selection.finish.col + 1),
                true
            )
        end
        put_selection = {
            kind = "block",
            anchor = { lnum = selection.start.lnum, col = selection.start.col },
            cursor = {
                lnum = selection.start.lnum,
                col = selection.start.col + Utf8.len(text) - 1,
            },
            start = { lnum = selection.start.lnum, col = selection.start.col },
            finish = {
                lnum = selection.start.lnum,
                col = selection.start.col + Utf8.len(text) - 1,
            },
            width = Utf8.len(text),
        }
    else
        return
    end

    if not preserve_register then
        _set_visual_register(selection.kind, selected_text, selection.width)
    end
    Visual.set_marks(win, put_selection)
    Visual.remember(win, put_selection)
    Syntax.ParseLinetypes(buf, selection.start.lnum)
    if put_selection.kind == "line" then
        win:cursorSet(put_selection.start.col, put_selection.start.lnum)
    else
        win:cursorSet(put_selection.finish.col, put_selection.finish.lnum)
    end
    setMode("normal")
    win:mark_redraw()
end

local function _toggle_case(text)
    return (text:gsub("%a", function(ch)
        if ch == string.lower(ch) then
            return string.upper(ch)
        end
        return string.lower(ch)
    end))
end

local function _transform_visual_selection(transform)
    local win = windows[curwin]
    local selection = Visual.finish(win)
    local buf = win.buffer
    for lnum = selection.start.lnum, selection.finish.lnum do
        local line = buf:get_line(lnum, true)
        local first_col, last_col
        if selection.kind == "line" then
            first_col, last_col = 1, Utf8.len(line)
        elseif selection.kind == "block" then
            first_col = selection.start.col
            last_col = math.min(selection.finish.col, Utf8.len(line))
        elseif selection.start.lnum == selection.finish.lnum then
            first_col, last_col = selection.start.col, selection.finish.col
        elseif lnum == selection.start.lnum then
            first_col, last_col = selection.start.col, Utf8.len(line)
        elseif lnum == selection.finish.lnum then
            first_col, last_col = 1, selection.finish.col
        else
            first_col, last_col = 1, Utf8.len(line)
        end
        if first_col <= last_col then
            buf:set_line(
                lnum,
                Utf8.sub(line, 1, first_col - 1)
                    .. transform(Utf8.sub(line, first_col, last_col))
                    .. Utf8.sub(line, last_col + 1),
                true
            )
        end
    end
    Syntax.ParseLinetypes(buf, selection.start.lnum)
    win:cursorSet(selection.start.col, selection.start.lnum)
    setMode("normal")
    win:mark_redraw()
end

local function _replace_visual_selection(char)
    _transform_visual_selection(function(text)
        return string.rep(char, Utf8.len(text))
    end)
end

local function _read_visual_replace_char()
    Command.override_emitter[#Command.override_emitter + 1] = function(key)
        table.remove(Command.override_emitter)
        table.remove(Command.emitter_names)
        local char = key:emittable()
        if char then
            _replace_visual_selection(char)
        end
    end
    Command.emitter_names[#Command.emitter_names + 1] = "Visual.replace_char"
end

local function _shift_visual_selection(right, count)
    local win = windows[curwin]
    local selection = Visual.finish(win)
    local buf = win.buffer
    local shift = Tab.shiftwidth_effective(buf) * (count or 1)
    local tcfg = Tab.get_tab_config(buf)
    for lnum = selection.start.lnum, selection.finish.lnum do
        local line = buf:get_line(lnum, true)
        local first_non_blank = 1
        while first_non_blank <= Utf8.len(line) do
            local char = Utf8.char_at(line, first_non_blank)
            if char ~= " " and char ~= "\t" then
                break
            end
            first_non_blank = first_non_blank + 1
        end
        local indent = Tab.vcol_of_prefix(line, first_non_blank, tcfg)
        if right then
            indent = indent + shift
        else
            indent = math.max(0, indent - shift)
        end
        win:reindentLine(lnum, indent, selection.start.col)
    end
    win:cursorSet(selection.start.col, selection.start.lnum)
    setMode("normal")
    win:mark_redraw()
end

local function _join_visual_selection(raw)
    local win = windows[curwin]
    local selection = Visual.finish(win)
    if selection.finish.lnum == selection.start.lnum then
        setMode("normal")
        return
    end

    local buf = win.buffer
    local first = buf:get_line(selection.start.lnum, true)
    local first_len = Utf8.len(first)
    local joined = first
    for lnum = selection.start.lnum + 1, selection.finish.lnum do
        local next_line = buf:get_line(lnum, true)
        if raw then
            joined = joined .. next_line
        else
            local tail = next_line:gsub("^[ \t]+", "")
            if tail ~= "" and not joined:match("[ \t]$") then
                joined = joined .. " "
            end
            joined = joined .. tail
        end
    end
    buf:set_line(selection.start.lnum, joined, true)
    buf:remove_lines(selection.start.lnum + 1, selection.finish.lnum)
    local finish_col
    if raw then
        finish_col = first_len + selection.finish.col
    else
        finish_col = first_len + 1
    end
    buf.marks[">"] = { lnum = selection.start.lnum, col = finish_col }
    Syntax.ParseLinetypes(buf, selection.start.lnum)
    win:cursorSet(first_len + 1, selection.start.lnum)
    setMode("normal")
    win:mark_redraw()
end

local function _select_visual_word(around, isWORD)
    local win = windows[curwin]
    local lnum, start_col, finish_col = WordNav.wordUnder(win, isWORD, win.cursory, win.cursorx)
    if not lnum then
        return
    end
    if around then
        local line = win.buffer:get_line(lnum, true)
        if isWORD then
            while finish_col < Utf8.len(line) do
                local char = Utf8.char_at(line, finish_col + 1)
                if char ~= " " and char ~= "\t" then
                    break
                end
                finish_col = finish_col + 1
            end
        else
            while start_col > 1 do
                local char = Utf8.char_at(line, start_col - 1)
                if char ~= " " and char ~= "\t" then
                    break
                end
                start_col = start_col - 1
            end
            if start_col == 1 then
                while finish_col < Utf8.len(line) do
                    local char = Utf8.char_at(line, finish_col + 1)
                    if char ~= " " and char ~= "\t" then
                        break
                    end
                    finish_col = finish_col + 1
                end
            end
        end
    end
    win.visual_kind = "char"
    win.visual_anchor = { lnum = lnum, col = start_col }
    win:cursorSet(finish_col, lnum)
    win:mark_redraw()
end

local function _select_visual_pair(around, open, close)
    local win = windows[curwin]
    local line = win.buffer:get_line(win.cursory, true)
    local stack = {}
    for col = 1, win.cursorx do
        local char = Utf8.char_at(line, col)
        if char == open then
            stack[#stack + 1] = col
        elseif char == close and #stack > 0 then
            table.remove(stack)
        end
    end
    local start_col = stack[#stack]
    if not start_col then
        return
    end
    local depth = 0
    local finish_col
    for col = start_col, Utf8.len(line) do
        local char = Utf8.char_at(line, col)
        if char == open then
            depth = depth + 1
        elseif char == close then
            depth = depth - 1
            if depth == 0 then
                finish_col = col
                break
            end
        end
    end
    if not finish_col then
        return
    end
    if not around then
        start_col = start_col + 1
        finish_col = finish_col - 1
    end
    win.visual_kind = "char"
    win.visual_anchor = { lnum = win.cursory, col = start_col }
    win:cursorSet(finish_col, win.cursory)
    win:mark_redraw()
end

local function _start_or_switch_visual(kind, count)
    local win = windows[curwin]
    if vimmode == "visual" then
        if win.visual_kind == kind then
            setMode("normal")
        else
            win.visual_kind = kind
            win:mark_redraw()
        end
        return
    end

    count = tonumber(count)
    local previous = count and win.last_visual_operation
    if previous then
        kind = previous.kind
    end
    Visual.begin(win, kind)
    setMode(_option_has("selectmode", "cmd") and "select" or "visual")
    if previous and count then
        if kind == "line" then
            local height = previous.finish.lnum - previous.start.lnum + 1
            win:cursorMove(0, height * count - 1)
        elseif kind == "block" then
            local height = previous.finish.lnum - previous.start.lnum + 1
            win:cursorMove(previous.width * count - 1, height * count - 1)
        elseif previous.start.lnum == previous.finish.lnum then
            local width = previous.finish.col - previous.start.col + 1
            win:cursorMove(width * count - 1, 0)
        end
    elseif count and count > 1 then
        if kind == "line" then
            win:cursorMove(0, count - 1)
        elseif kind == "char" then
            win:cursorMove(count - 1, 0)
        end
    end
end

local function _start_select(kind)
    local win = windows[curwin]
    Visual.begin(win, kind)
    setMode("select")
end

local function _start_shift_selection(move)
    if not _option_has("keymodel", "startsel") then
        move()
        return
    end
    local win = windows[curwin]
    Visual.begin(win, "char")
    setMode(_option_has("selectmode", "key") and "select" or "visual")
    move()
end

local function _select_special_move(move, shifted)
    if not shifted and _option_has("keymodel", "stopsel") then
        setMode("normal")
    end
    move()
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
Command.nmap_builtin_callback({ K(keys.g), K(keys.h) }, function() _start_select("char") end)
Command.nmap_builtin_callback({ K(keys.g), K(keys.h, false, true) }, function() _start_select("line") end)
Command.nmap_builtin_callback({ K(keys.g), K(keys.h, true) }, function() _start_select("block") end)
Command.nmap_builtin_callback({ K(keys.g), K(keys.h, true, true) }, function() _start_select("block") end)
Command.nmap_builtin_callback({ K(keys.g), K(keys.backspace) }, function() _start_select("block") end)

local select_specials = {
    { keys.left, _mov_lt },
    { keys.right, _mov_rt },
    { keys.up, _mov_up },
    { keys.down, _mov_dn },
    { keys.home, _mov_home },
    { keys["end"], _mov_end },
    { keys.pageUp, function() _mov_page(-1) end },
    { keys.pageDown, function() _mov_page(1) end },
}
for i = 1, #select_specials do
    local key, move = select_specials[i][1], select_specials[i][2]
    if key ~= keys.left and key ~= keys.right then
        Command.nmap_builtin_callback({ K(key, false, true) }, function() _start_shift_selection(move) end)
    end
    Command.vmap_builtin_callback({ K(key, false, true) }, move)
    Command.smap_builtin_callback({ K(key) }, function() _select_special_move(move, false) end)
    Command.smap_builtin_callback({ K(key, false, true) }, function()
        _select_special_move(move, true)
    end)
end

-- Visual mode is a single mode with a selection kind stored on the window.
-- Keeping all kinds on this path lets mappings and motion handling stay shared.
Command.count_modes.visual = true
Command.nmap_builtin_callback({ K(keys.v) }, function(count) _start_or_switch_visual("char", count) end)
Command.nmap_builtin_callback(
    { K(keys.v, false, true) },
    function(count) _start_or_switch_visual("line", count) end
)
Command.nmap_builtin_callback({ K(keys.v, true) }, function(count) _start_or_switch_visual("block", count) end)

Command.vmap_builtin_callback({ K(keys.v) }, function(count) _start_or_switch_visual("char", count) end)
Command.vmap_builtin_callback(
    { K(keys.v, false, true) },
    function(count) _start_or_switch_visual("line", count) end
)
Command.vmap_builtin_callback({ K(keys.v, true) }, function(count) _start_or_switch_visual("block", count) end)
Command.vmap_builtin_callback({ K(keys.h) }, _mov_lt)
Command.vmap_builtin_callback({ K(keys.j) }, _mov_dn)
Command.vmap_builtin_callback({ K(keys.k) }, _mov_up)
Command.vmap_builtin_callback({ K(keys.l) }, _mov_rt)
Command.vmap_builtin_callback({ K(keys.left) }, _mov_lt)
Command.vmap_builtin_callback({ K(keys.down) }, _mov_dn)
Command.vmap_builtin_callback({ K(keys.up) }, _mov_up)
Command.vmap_builtin_callback({ K(keys.right) }, _mov_rt)
Command.vmap_builtin_callback({ K(keys.y) }, _yank_visual_selection)
Command.vmap_builtin_callback({ K(keys.d) }, function() _delete_visual_selection(false) end)
Command.vmap_builtin_callback({ K(keys.x) }, function() _delete_visual_selection(false) end)
Command.vmap_builtin_callback({ K(keys.c) }, function() _delete_visual_selection(true) end)
Command.vmap_builtin_callback({ K(keys.s) }, function() _delete_visual_selection(true) end)
Command.vmap_builtin_callback({ K(keys.c, false, true) }, function()
    if windows[curwin].visual_kind == "block" then
        _delete_visual_selection(true, true)
    else
        _delete_visual_selection(true, false, true)
    end
end)
Command.vmap_builtin_callback({ K(keys.i, false, true) }, function() _block_insert(false) end)
Command.vmap_builtin_callback({ K(keys.a, false, true) }, function() _block_insert(true) end)
Command.vmap_builtin_callback({ K(keys.leftBracket, true) }, function() setMode("normal") end)
Command.vmap_builtin_callback({ K(keys.c, true) }, function() setMode("normal") end)
Command.vmap_builtin_callback({ K(keys.g, true) }, function() setMode("select") end)
Command.smap_builtin_callback({ K(keys.g, true) }, function() setMode("visual") end)
Command.smap_builtin_callback({ K(keys.o, true) }, Command.begin_select_once)
Command.smap_builtin_callback({ K(keys.leftBracket, true) }, function() setMode("normal") end)
Command.smap_builtin_callback({ K(keys.c, true) }, function() setMode("normal") end)
Command.smap_builtin_callback({ K(keys.j, true) }, function() Command.replace_select("\r") end)
Command.smap_builtin_callback({ K(keys.backspace) }, Command.delete_select)
Command.smap_builtin_callback({ K(keys.delete) }, Command.delete_select)
Command.smap_builtin_callback({ K(keys.r, true) }, function()
    Command.override_emitter[#Command.override_emitter + 1] = function(key)
        table.remove(Command.override_emitter)
        table.remove(Command.emitter_names)
        local register = key:emittable()
        if register and #register == 1 then windows[curwin].select_register = register end
    end
    Command.emitter_names[#Command.emitter_names + 1] = "Select.register"
end)
if Backend.current().kind == "cc" then
    Command.vmap_builtin_callback({ K(keys.tab, true) }, function() setMode("normal") end)
end
Command.vmap_builtin_callback({ K(keys.o) }, function()
    Visual.other_end(windows[curwin])
end)
Command.vmap_builtin_callback({ K(keys.o, false, true) }, function()
    Visual.other_block_corner(windows[curwin])
end)
Command.vmap_builtin_callback({ K(keys.d, false, true) }, function()
    if windows[curwin].visual_kind == "block" then
        _delete_visual_selection(false, true)
    else
        _delete_visual_selection(false, false, true)
    end
end)
Command.vmap_builtin_callback({ K(keys.y, false, true) }, function()
    _yank_visual_selection(true)
end)
Command.vmap_builtin_callback({ K(keys.p) }, function() _put_visual_selection(false) end)
Command.vmap_builtin_callback({ K(keys.p, false, true) }, function() _put_visual_selection(true) end)
Command.vmap_builtin_callback({ K(keys.u, false, true) }, function()
    _transform_visual_selection(string.upper)
end)
Command.vmap_builtin_callback({ K(keys.u) }, function()
    _transform_visual_selection(string.lower)
end)
Command.vmap_builtin_callback({ K(keys.grave, false, true) }, function()
    _transform_visual_selection(_toggle_case)
end)
Command.vmap_builtin_callback({ K(keys.r) }, _read_visual_replace_char)
Command.vmap_builtin_callback({ K(keys.period, false, true) }, function(count)
    _shift_visual_selection(true, count)
end)
Command.vmap_builtin_callback({ K(keys.comma, false, true) }, function(count)
    _shift_visual_selection(false, count)
end)
Command.vmap_builtin_callback({ K(keys.j, false, true) }, function()
    _join_visual_selection(false)
end)
Command.vmap_builtin_callback({ K(keys.g), K(keys.j, false, true) }, function()
    _join_visual_selection(true)
end)
Command.vmap_builtin_callback({ K(keys.i), K(keys.w) }, function()
    _select_visual_word(false, false)
end)
Command.vmap_builtin_callback({ K(keys.a), K(keys.w) }, function()
    _select_visual_word(true, false)
end)
Command.vmap_builtin_callback({ K(keys.i), K(keys.w, false, true) }, function()
    _select_visual_word(false, true)
end)
Command.vmap_builtin_callback({ K(keys.a), K(keys.w, false, true) }, function()
    _select_visual_word(true, true)
end)
Command.vmap_builtin_callback({ K(keys.i), K(keys.b) }, function()
    _select_visual_pair(false, "(", ")")
end)
Command.vmap_builtin_callback({ K(keys.a), K(keys.b) }, function()
    _select_visual_pair(true, "(", ")")
end)
Command.vmap_builtin_callback({ K(keys.i), K(keys.leftBracket) }, function()
    _select_visual_pair(false, "[", "]")
end)
Command.vmap_builtin_callback({ K(keys.a), K(keys.leftBracket) }, function()
    _select_visual_pair(true, "[", "]")
end)

Command.nmap_builtin_callback({ K(keys.g), K(keys.v) }, function()
    local win = windows[curwin]
    if Visual.restore_last(win) then
        setMode("visual")
    end
end)
Command.vmap_builtin_callback({ K(keys.g), K(keys.v) }, function()
    Visual.swap_with_last(windows[curwin])
end)
Command.vmap_builtin_callback({ K(keys.g), K(keys.v, false, true) }, Command.cancel_select_reselect)

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
local next_word = _wnav(WordNav.posNext, false, false)
Command.nmap_builtin_callback({ K(keys.right, false, true) }, function(count)
    if _option_has("keymodel", "startsel") then
        _start_shift_selection(_mov_rt)
    else
        next_word(count)
    end
end)
Command.nmap_builtin_callback({ K(keys.w, false, true) }, _wnav(WordNav.posNext, true, false))
Command.nmap_builtin_callback({ K(keys.right, true) }, _wnav(WordNav.posNext, true, false))
Command.nmap_builtin_callback({ K(keys.e) }, _wnav(WordNav.posNext, false, true))
Command.nmap_builtin_callback({ K(keys.e, false, true) }, _wnav(WordNav.posNext, true, true))
Command.nmap_builtin_callback({ K(keys.b) }, _wnav(WordNav.posPrev, false, false))
local previous_word = _wnav(WordNav.posPrev, false, false)
Command.nmap_builtin_callback({ K(keys.left, false, true) }, function(count)
    if _option_has("keymodel", "startsel") then
        _start_shift_selection(_mov_lt)
    else
        previous_word(count)
    end
end)
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
