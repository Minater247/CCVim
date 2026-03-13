local PopupMenu = {}

local AutoCmd = loadModule("lib.autocmd")
local Highlight = loadModule("lib.highlight")
local FrameTree = loadModule("lib.frame")
local ScreenDraw = loadModule("lib.screendraw")
local scopes = loadModule("lib.luaapi.scopes")
local Utf8 = loadModule("lib.utf8")

local state = {
    active = false,
    mode = "",
    items = {},
    selected = -1, -- 0-based
    scroll = 0, -- 0-based
    startcol = 1,
    prefix = "",
    base = "",
    suffix = "",
    bufnr = nil,
    winid = nil,
    row = 0, -- 0-based screen row
    col = 0, -- 0-based screen col
    width = 0, -- includes scrollbar column if present
    height = 0,
    size = 0,
    scrollbar = false,
    noinsert = false,
    noselect = false,
}

local function _strchars(s)
    return Utf8.len(tostring(s or ""))
end

local function _strsub(s, start_col1, end_col1)
    return Utf8.sub(tostring(s or ""), start_col1, end_col1)
end

local function _truthy(v)
    return not (v == nil or v == false or v == 0)
end

local function _parse_completeopt(win)
    local buf = win.buffer
    local raw = tostring(options.get("completeopt", win, buf) or "")
    local items = options.ParseCSL(raw)
    local has = {}
    for i = 1, #items do
        local item = tostring(items[i] or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if item ~= "" then
            has[item] = true
        end
    end
    return has
end

local function _normalize_item(item)
    local out = {}
    if type(item) == "string" then
        out.word = item
    elseif type(item) == "table" then
        for k, v in pairs(item) do
            out[k] = v
        end
        if out.word == nil then
            out.word = out.abbr or ""
        end
    else
        out.word = tostring(item or "")
    end

    out.word = tostring(out.word or "")
    out.abbr = tostring(out.abbr or "")
    out.kind = tostring(out.kind or "")
    out.menu = tostring(out.menu or "")
    out.info = tostring(out.info or "")
    if out.user_data == nil then
        out.user_data = ""
    end
    if out.dup == nil then out.dup = 0 end
    if out.empty == nil then out.empty = 0 end
    if out.icase == nil then out.icase = 0 end
    if out.equal == nil then out.equal = 0 end

    return out
end

local function _display_text(item)
    local abbr = item.abbr
    if abbr == "" then
        abbr = item.word
    end

    local parts = { abbr }
    if item.kind ~= "" then
        parts[#parts + 1] = item.kind
    end
    if item.menu ~= "" then
        parts[#parts + 1] = item.menu
    end
    return table.concat(parts, " ")
end

local function _window_origin(win)
    if not win then
        return 1, 1
    end

    if win.frame then
        local x, y = FrameTree.GetXY(win.frame)
        local tp = tabpages[win.tabpagenr]
        local yoff = (tp and tp.winyoff) or 0
        return x, y + yoff
    end

    if win.floatpos then
        return (tonumber(win.floatpos.x) or 0) + 1, (tonumber(win.floatpos.y) or 0) + 1
    end

    return 1, 1
end

local function _cursor_screen_row_col(win)
    local x0, y0 = _window_origin(win)
    local _, text_x = win:textwidth()
    local row1 = y0 + math.max(0, (win.cursory or 1) - ((win.scrolly and win.scrolly[1]) or 1))
    local col1 = x0 + (text_x or 1) + math.max(0, (state.startcol or (win.cursorx or 1)) - (win.scrollx or 1)) - 1
    return row1, col1
end

local function _compute_geometry()
    local win = windows[state.winid or curwin]
    local size = #state.items
    local ph = tonumber(options.get("pumheight")) or 0
    local minw = tonumber(options.get("pumwidth")) or 0

    local h = (ph > 0) and math.min(size, ph) or size
    if h < 1 then h = 1 end

    local w = minw
    for i = 1, size do
        w = math.max(w, _strchars(_display_text(state.items[i])))
    end
    if w < 1 then w = 1 end

    local show_scroll = size > h
    if show_scroll then
        w = w + 1
    end

    local cursor_row1, cursor_col1 = _cursor_screen_row_col(win)
    local bottom = math.max(1, screen.height - (tonumber(options.get("cmdheight") or 1) or 1))

    local row1 = cursor_row1 + 1
    if row1 + h - 1 > bottom then
        row1 = cursor_row1 - h
    end
    if row1 < 1 then
        row1 = 1
    end
    if row1 + h - 1 > bottom then
        h = math.max(1, bottom - row1 + 1)
    end

    local col1 = cursor_col1
    if col1 < 1 then col1 = 1 end
    if col1 + w - 1 > screen.width then
        col1 = math.max(1, screen.width - w + 1)
    end

    state.row = row1 - 1
    state.col = col1 - 1
    state.width = w
    state.height = h
    state.size = size
    state.scrollbar = show_scroll
end

local function _selected_item()
    if state.selected < 0 then
        return nil
    end
    return state.items[state.selected + 1]
end

local function _completed_item_value()
    local item = _selected_item()
    if not item then
        return {}
    end
    local out = {}
    for k, v in pairs(item) do
        out[k] = v
    end
    return out
end

local function _set_completed_item()
    scopes._v.completed_item = _completed_item_value()
end

local function _ensure_scroll_visible()
    if state.selected < 0 then
        state.scroll = 0
        return
    end
    if state.selected < state.scroll then
        state.scroll = state.selected
    elseif state.selected >= state.scroll + state.height then
        state.scroll = state.selected - state.height + 1
    end
    if state.scroll < 0 then
        state.scroll = 0
    end
    local max_scroll = math.max(0, state.size - state.height)
    if state.scroll > max_scroll then
        state.scroll = max_scroll
    end
end

local function _set_line_noauto(buf, line_nr, text)
    buf:set_line(line_nr, text, true, true)
end

local function _apply_current_selection(insert)
    local win = windows[state.winid or curwin]
    if not win then
        return
    end
    local buf = win.buffer
    if not buf then
        return
    end

    local word = state.base
    if state.selected >= 0 and insert then
        local item = state.items[state.selected + 1]
        if item then
            word = item.word or ""
        end
    end

    local new_line = state.prefix .. word .. state.suffix
    _set_line_noauto(buf, win.cursory, new_line)
    win.cursorx = _strchars(state.prefix .. word) + 1

    win.need_redraw = true
    what_redraw["windows"] = true
    need_redraw = true
end

local function _changed_event_data()
    return {
        height = state.height,
        width = state.width,
        row = state.row,
        col = state.col,
        size = state.size,
        scrollbar = state.scrollbar,
        completed_item = _completed_item_value(),
        complete_type = "eval",
    }
end

local function _emit_changed()
    AutoCmd.Run("CompleteChanged", {
        bufnr = state.bufnr,
        bufname = (buffers[state.bufnr] and buffers[state.bufnr].name) or "",
        data = _changed_event_data(),
    })
end

local function _emit_done(reason)
    local item = _completed_item_value()
    local data = {
        reason = reason or "",
        complete_type = "eval",
        completed_item = item,
        complete_word = item.word or "",
    }

    AutoCmd.Run("CompleteDonePre", {
        bufnr = state.bufnr,
        bufname = (buffers[state.bufnr] and buffers[state.bufnr].name) or "",
        data = data,
    })

    AutoCmd.Run("CompleteDone", {
        bufnr = state.bufnr,
        bufname = (buffers[state.bufnr] and buffers[state.bufnr].name) or "",
        data = data,
    })
end

function PopupMenu.visible()
    return state.active == true
end

function PopupMenu.info()
    if not state.active then
        return {}
    end
    return {
        height = state.height,
        width = state.width,
        row = state.row,
        col = state.col,
        size = state.size,
        scrollbar = state.scrollbar,
    }
end

function PopupMenu.state()
    return state
end

function PopupMenu.close(reason)
    if not state.active then
        return
    end

    _emit_done(reason or "")

    state.active = false
    state.mode = ""
    state.items = {}
    state.selected = -1
    state.scroll = 0
    state.size = 0
    state.height = 0
    state.width = 0
    state.scrollbar = false
    _set_completed_item()

    what_redraw["windows"] = true
    need_redraw = true
end

function PopupMenu.select(item, insert, finish)
    if not state.active then
        return false
    end

    local idx = tonumber(item or -1) or -1
    if idx < -1 then idx = -1 end
    if idx >= state.size then idx = state.size - 1 end

    state.selected = idx
    _ensure_scroll_visible()
    _set_completed_item()

    _compute_geometry()
    _apply_current_selection(_truthy(insert))
    _emit_changed()

    if _truthy(finish) then
        PopupMenu.close((idx >= 0 and _truthy(insert or finish)) and "accept" or "cancel")
    end
    return true
end

function PopupMenu.step(delta, insert)
    if not state.active then
        return false
    end

    local d = tonumber(delta) or 0
    if d == 0 then
        return false
    end

    local idx = state.selected
    if idx < 0 then
        idx = (d > 0) and 0 or (state.size - 1)
    else
        idx = idx + d
        if idx < 0 then idx = -1 end
        if idx >= state.size then idx = state.size - 1 end
    end

    return PopupMenu.select(idx, insert, false)
end

function PopupMenu.handle_key(key)
    if not state.active then
        return false
    end

    local p = key:printable()
    if p == "<C-n>" or p == "<Down>" then
        return PopupMenu.step(1, true)
    end
    if p == "<C-p>" or p == "<Up>" then
        return PopupMenu.step(-1, true)
    end
    if p == "<C-y>" then
        return PopupMenu.select(state.selected, true, true)
    end
    if p == "<C-e>" then
        return PopupMenu.select(-1, false, true)
    end
    return false
end

function PopupMenu.complete(startcol, matches)
    local win = windows[curwin]
    if not win or not win.buffer then
        return 0
    end

    startcol = tonumber(startcol or win.cursorx) or win.cursorx
    if startcol < 1 then startcol = 1 end
    if startcol > win.cursorx then
        startcol = win.cursorx
    end

    local items = {}
    if type(matches) == "table" then
        for i = 1, #matches do
            local norm = _normalize_item(matches[i])
            if norm.word ~= "" or _truthy(norm.empty) then
                items[#items + 1] = norm
            end
        end
    end

    if #items == 0 then
        if state.active then
            PopupMenu.close("cancel")
        end
        return 0
    end

    local line = win.buffer:get_line(win.cursory, true) or ""
    local curcol = win.cursorx

    state.active = true
    state.mode = "eval"
    state.items = items
    state.size = #items
    state.startcol = startcol
    state.winid = curwin
    state.bufnr = win.buffer.bufnr
    state.prefix = _strsub(line, 1, startcol - 1)
    state.base = _strsub(line, startcol, curcol - 1)
    state.suffix = _strsub(line, curcol)

    local cot = _parse_completeopt(win)
    state.noinsert = cot.noinsert and true or false
    state.noselect = cot.noselect and true or false
    state.selected = state.noselect and -1 or 0
    state.scroll = 0

    _ensure_scroll_visible()
    _compute_geometry()
    _set_completed_item()
    _apply_current_selection(not state.noinsert and state.selected >= 0)
    _emit_changed()
    return 0
end

function PopupMenu.complete_add(expr)
    if not state.active then
        return 0
    end

    local item = _normalize_item(expr)
    if item.word == "" and not _truthy(item.empty) then
        return 0
    end

    for i = 1, #state.items do
        local it = state.items[i]
        local equal
        if _truthy(item.equal) or _truthy(it.equal) then
            equal = true
        elseif _truthy(item.icase) or _truthy(it.icase) then
            equal = (string.lower(it.word) == string.lower(item.word))
        else
            equal = (it.word == item.word)
        end
        if equal and not _truthy(item.dup) then
            return 2
        end
    end

    state.items[#state.items + 1] = item
    state.size = #state.items
    _compute_geometry()
    _emit_changed()
    return 1
end

function PopupMenu.complete_info(what)
    local out = {}
    local include = {}
    local has_filter = false
    if type(what) == "table" then
        for i = 1, #what do
            include[tostring(what[i] or "")] = true
        end
        has_filter = true
    end

    local function put(k, v)
        if (not has_filter) or include[k] then
            out[k] = v
        end
    end

    put("mode", state.active and state.mode or "")
    put("pum_visible", state.active and 1 or 0)
    put("items", state.items or {})
    put("selected", state.active and state.selected or -1)
    put("completed", _completed_item_value())
    return out
end

function PopupMenu.complete_check()
    return 0
end

function PopupMenu.render()
    if not state.active or state.size <= 0 or state.height <= 0 or state.width <= 0 then
        return
    end

    local row1 = state.row + 1
    local col1 = state.col + 1
    local width = state.width
    local content_w = width - (state.scrollbar and 1 or 0)
    if content_w < 1 then content_w = 1 end

    local thumb_top, thumb_h = 0, 0
    if state.scrollbar then
        thumb_h = math.max(1, math.floor((state.height * state.height) / math.max(1, state.size)))
        local avail = math.max(0, state.height - thumb_h)
        local max_scroll = math.max(1, state.size - state.height)
        thumb_top = math.floor((state.scroll * avail) / max_scroll)
    end

    for i = 1, state.height do
        local idx = state.scroll + i
        local text = ""
        local hl = "Pmenu"
        if idx >= 1 and idx <= state.size then
            local item = state.items[idx]
            text = _display_text(item)
            if (idx - 1) == state.selected then
                hl = "PmenuSel"
            end
        end

        local tlen = _strchars(text)
        if tlen > content_w then
            text = _strsub(text, 1, content_w)
            tlen = _strchars(text)
        end
        if tlen < content_w then
            text = text .. string.rep(" ", content_w - tlen)
        end

        ScreenDraw.put_text(row1 + i - 2, col1 - 1, text, hl)

        if state.scrollbar then
            local sb_hl = "PMenuSbar"
            if not Highlight.GroupExists(sb_hl) then
                sb_hl = "Pmenu"
            end
            local in_thumb = (i - 1) >= thumb_top and (i - 1) < (thumb_top + thumb_h)
            ScreenDraw.put_text(row1 + i - 2, col1 + content_w - 1, " ", in_thumb and "PmenuThumb" or sb_hl)
        end
    end
end

return PopupMenu
