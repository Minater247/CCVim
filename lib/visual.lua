-- Shared Visual-mode selection state and range helpers.

local Visual = {}

local Utf8 = loadModule("lib.utf8")
local Scopes = loadModule("lib.luaapi.scopes")

local MODE_CHAR = {
    char = "v",
    line = "V",
    block = string.char(22),
}

local function copy_pos(pos)
    return { lnum = pos.lnum, col = pos.col }
end

local function before_or_equal(a, b)
    return a.lnum < b.lnum or (a.lnum == b.lnum and a.col <= b.col)
end

function Visual.mode_char(kind)
    local mode = MODE_CHAR[kind]
    assert(mode, "invalid Visual selection kind")
    return mode
end

function Visual.active(win)
    return vimmode == "visual" and win.visual_anchor ~= nil
end

function Visual.begin(win, kind)
    win.visual_anchor = { lnum = win.cursory, col = win.cursorx }
    win.visual_kind = kind
    win:mark_redraw()
end

function Visual.selection(win)
    if not win.visual_anchor then
        return nil
    end

    local anchor = copy_pos(win.visual_anchor)
    local cursor = { lnum = win.cursory, col = win.cursorx }
    local kind = win.visual_kind
    local start, finish
    if kind == "line" then
        local top = math.min(anchor.lnum, cursor.lnum)
        local bottom = math.max(anchor.lnum, cursor.lnum)
        start = { lnum = top, col = 1 }
        finish = { lnum = bottom, col = Scopes.MAXCOL }
    elseif kind == "block" then
        start = {
            lnum = math.min(anchor.lnum, cursor.lnum),
            col = math.min(anchor.col, cursor.col),
        }
        finish = {
            lnum = math.max(anchor.lnum, cursor.lnum),
            col = math.max(anchor.col, cursor.col),
        }
    elseif before_or_equal(anchor, cursor) then
        start, finish = anchor, cursor
    else
        start, finish = cursor, anchor
    end

    return {
        kind = kind,
        anchor = anchor,
        cursor = cursor,
        start = start,
        finish = finish,
        width = (kind == "block") and (finish.col - start.col + 1) or nil,
    }
end

function Visual.finish(win)
    local selection = Visual.selection(win)
    if not selection then
        return nil
    end

    local buf = win.buffer
    buf.marks["<"] = { lnum = selection.start.lnum, col = selection.start.col }
    buf.marks[">"] = { lnum = selection.finish.lnum, col = selection.finish.col }
    win.last_visual = {
        kind = selection.kind,
        anchor = copy_pos(selection.anchor),
        cursor = copy_pos(selection.cursor),
        start = copy_pos(selection.start),
        finish = copy_pos(selection.finish),
        width = selection.width,
    }
    win.last_visual_mode = Visual.mode_char(selection.kind)
    win.visual_anchor = nil
    win.visual_kind = nil
    win:mark_redraw()
    return selection
end

function Visual.restore_last(win)
    local previous = win.last_visual
    if not previous then
        return false
    end
    win.visual_anchor = copy_pos(previous.anchor)
    win.visual_kind = previous.kind
    win:cursorSet(previous.cursor.col, previous.cursor.lnum)
    win:mark_redraw()
    return true
end

function Visual.contains(selection, lnum, col)
    local start, finish = selection.start, selection.finish
    if selection.kind == "line" then
        return lnum >= start.lnum and lnum <= finish.lnum
    elseif selection.kind == "block" then
        return lnum >= start.lnum and lnum <= finish.lnum
            and col >= start.col and col <= finish.col
    end

    if lnum < start.lnum or lnum > finish.lnum then
        return false
    end
    if start.lnum == finish.lnum then
        return col >= start.col and col <= finish.col
    elseif lnum == start.lnum then
        return col >= start.col
    elseif lnum == finish.lnum then
        return col <= finish.col
    end
    return true
end

function Visual.slice_block_line(selection, line)
    local len = Utf8.len(line)
    if len < selection.start.col then
        return ""
    end
    return Utf8.sub(line, selection.start.col, math.min(selection.finish.col, len))
end

function Visual.begin_block_change(win, selection)
    local rows = {}
    for lnum = selection.start.lnum, selection.finish.lnum do
        local line = win.buffer:get_line(lnum, true)
        rows[#rows + 1] = {
            lnum = lnum,
            prefix = Utf8.sub(line, 1, selection.start.col - 1),
            suffix = Utf8.sub(line, selection.start.col),
        }
    end
    win.visual_block_change = { rows = rows }
end

function Visual.complete_block_change(win)
    local state = win.visual_block_change
    if not state then
        return false
    end
    win.visual_block_change = nil

    local first = state.rows[1]
    if not first then
        return false
    end
    local line = win.buffer:get_line(first.lnum, true)
    local prefix_len = Utf8.len(first.prefix)
    local suffix_len = Utf8.len(first.suffix)
    local inserted_end = Utf8.len(line) - suffix_len
    if inserted_end < prefix_len then
        return false
    end
    local inserted = Utf8.sub(line, prefix_len + 1, inserted_end)
    for i = 2, #state.rows do
        local row = state.rows[i]
        win.buffer:set_line(row.lnum, row.prefix .. inserted .. row.suffix, true)
    end
    return true
end

return Visual
