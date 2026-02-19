local Window = {}
Window.__index = Window -- Share the instance methods

---@class Buffer
local Buffer = loadModule("vim.layout.buffer")
local Highlight = loadModule("vim.lib.highlight")
local FrameTree = loadModule("vim.lib.frame")
local Statusline = loadModule("vim.lib.statusline")
local TexRen = loadModule("vim.lib.texren")
local Syntax = loadModule("vim.lib.syntax")
local Tab = loadModule("vim.lib.tab")
local ListChars = loadModule("vim.lib.listchars")
local Error = loadModule("vim.lib.error")
local Autocmd = loadModule("vim.lib.autocmd")
local VimExpr
local VimFn
local Scopes
local CmdRead

local curr_winno = 1

---@class WinOpts

---@class Window
---@field winnr number The unique window number.
---@field buffer Buffer The buffer associated with this Window.
---@field tabpagenr number The tabpage number of the tabpage containing this window.
---@field opts table<string, any>
---@field scrollx number
---@field scrolly number[]
---@field cursorx number
---@field cursory number
---@field quickfix number
---@field loclist number
---@field _held_vx number|nil
---@field floatpos {reltype:string,x:number,y:number,w:number,h:number}|nil
---@field style string|nil
---@field focusable boolean
---@field frame any
---@field need_redraw boolean|nil
---@field curdir string|nil The local current directory for this window.
---@field syntax_ctx_override table|nil Window-local syntax context override (used by :ownsyntax).

--- Creates a new Window.
---@param buffer Buffer A buffer to initialize the window with, if one is ready.
---@param refwin Window A window to reference when setting up a new window. Used for window splitting.
function Window:new(buffer, refwin)
    local obj = setmetatable({
        winnr     = curr_winno,
        buffer    = buffer or Buffer(true, false, true),
        altbuf    = refwin and refwin.altbuf or nil,
        opts      = {},
        scrollx   = refwin and refwin.scrollx or 1,
        scrolly   = refwin and { refwin.scrolly[1], refwin.scrolly[2] } or { 1, 0 }, -- line offset, internal line offset
        cursorx   = refwin and refwin.cursorx or 1,
        cursory   = refwin and refwin.cursory or 1,
        quickfix  = 0,
        loclist   = 0,

        -- Hold X position
        _held_vx  = nil,

        -- Positioning info
        floatpos  = nil, -- {.reltype, .x, .y, .w, .h}

        style     = nil,

        focusable = true,
    }, Window)

    windows[curr_winno] = obj

    if refwin then
        for k, v in pairs(refwin.opts) do
            obj.opts[k] = v
        end
    end

    obj.buffer.refcount = obj.buffer.refcount + 1

    curr_winno = curr_winno + 1
    return obj
end

function Window:minwidth()
    local base = options.get("winminwidth")

    if (self.style ~= "minimal") and (options.get("number", self) or options.get("relativenumber", self)) then
        base = math.max(base, options.get("numberwidth", self) + 1)
    end

    return base
end

function Window:minheight()
    return options.get("winminheight")
end

-- Map a desired visual column to a byte index (1..#line  in normal mode,
-- 1..#line+1 in insert mode)
function Window:_col1_for_visual_col(line, want_vx, insert_mode)
    local tcfg = Tab.get_tab_config(self.buffer)
    local n = #line

    if want_vx <= 1 then
        return 1
    end

    local best_i, best_v = 1, Tab.vcol_of_prefix(line, 1, tcfg)

    for i = 1, n + 1 do
        local v = Tab.vcol_of_prefix(line, i, tcfg)

        if v <= want_vx then
            best_i, best_v = i, v
        else
            local dist_prev = want_vx - best_v
            local dist_next = v - want_vx

            if insert_mode then
                if dist_next < dist_prev then
                    return i
                else
                    return best_i
                end
            else
                if dist_next < dist_prev then
                    return math.min(i, n)
                else
                    return math.min(best_i, n)
                end
            end
        end
    end

    if insert_mode then
        return n + 1
    else
        return math.max(1, n)
    end
end

-- Wrap helpers (screen-line aware)
function Window:_wrap_params()
    local text_w = self:textwidth()
    if text_w < 0 then text_w = 0 end
    local wraplen = (text_w > 0) and text_w or 0
    local linebreak = options.get("linebreak", self)
    return text_w, {
        wraplen  = wraplen,
        wordwrap = linebreak,
        breakat  = linebreak and options.get("breakat") or nil,
        tabcfg   = Tab.get_tab_config(self.buffer)
    }
end

function Window:_wrap_row_count(line_idx, params)
    self.buffer:ensure_loaded(true)
    local line = self.buffer:get_line(line_idx, true) or ""
    local rendered = TexRen.parse(line, params)
    local n = #rendered
    if n < 1 then n = 1 end
    return n
end

function Window:_wrap_row_count_with_cursor(line_idx, params)
    local rows = self:_wrap_row_count(line_idx, params)
    if (line_idx == self.cursory) and (vimmode == "insert") then
        local lines, _, _, pos = self:_wrap_layout(line_idx, params, self.cursorx)
        if pos and pos.line == (#lines + 1) then
            return rows + 1, true, #lines
        end
    end
    return rows, false, nil
end

function Window:_wrap_layout(line_idx, params, bytepos)
    self.buffer:ensure_loaded(true)
    local line = self.buffer:get_line(line_idx, true) or ""
    local lines, ranges, gsrc, pos = TexRen.layout(line, params, bytepos)
    if #lines < 1 then lines[1] = "" end
    return lines, ranges, gsrc, pos
end

function Window:_wrap_clamp_scroll(params)
    local linecnt = self.buffer:line_count(true)
    local line = self.scrolly[1]
    if line < 1 then line = 1 end
    if line > linecnt then line = linecnt end
    local rows = self:_wrap_row_count_with_cursor(line, params)
    local off = self.scrolly[2] or 0
    if off < 0 then off = 0 end
    if off > rows - 1 then off = math.max(0, rows - 1) end
    self.scrolly[1] = line
    self.scrolly[2] = off
end

-- Returns cursor row offset (0-based) from top of window and screen column (1-based)
function Window:_wrap_cursor_pos(params)
    self:_wrap_clamp_scroll(params)

    local cursor_line = self.cursory
    local cursor_col = self.cursorx
    local row_in_line, col_in_row
    do
        local _, _, _, pos = self:_wrap_layout(cursor_line, params, cursor_col)
        row_in_line = (pos and pos.line) or 1
        col_in_row = (pos and pos.column) or 1
    end

    local top_line = self.scrolly[1]
    local top_off = self.scrolly[2] or 0

    if cursor_line == top_line then
        return (row_in_line - 1) - top_off, col_in_row
    end

    if cursor_line > top_line then
        local offset = self:_wrap_row_count(top_line, params) - top_off
        for l = top_line + 1, cursor_line - 1 do
            offset = offset + self:_wrap_row_count(l, params)
        end
        offset = offset + (row_in_line - 1)
        return offset, col_in_row
    else
        local offset = (self:_wrap_row_count(cursor_line, params) - row_in_line + 1)
        for l = cursor_line + 1, top_line - 1 do
            offset = offset + self:_wrap_row_count(l, params)
        end
        offset = offset + top_off
        return -offset, col_in_row
    end
end

function Window:_wrap_scroll_rows(delta, params)
    if delta == 0 then return end

    local linecnt = self.buffer:line_count(true)
    local line = self.scrolly[1]
    local off = self.scrolly[2] or 0

    if line < 1 then line = 1 end
    if line > linecnt then line = linecnt end

    local function row_count(idx)
        if idx == self.cursory then
            return self:_wrap_row_count_with_cursor(idx, params)
        end
        return self:_wrap_row_count(idx, params)
    end

    if delta > 0 then
        local remaining = delta
        while remaining > 0 do
            local rows = row_count(line)
            if off > rows - 1 then off = rows - 1 end
            local avail = rows - off
            if remaining < avail then
                off = off + remaining
                remaining = 0
            else
                remaining = remaining - avail
                if line >= linecnt then
                    off = rows - 1
                    break
                end
                line = line + 1
                off = 0
            end
        end
    else
        local remaining = -delta
        while remaining > 0 do
            local rows = row_count(line)
            if off > rows - 1 then off = rows - 1 end
            if remaining <= off then
                off = off - remaining
                remaining = 0
            else
                remaining = remaining - off
                if line <= 1 then
                    off = 0
                    break
                end
                remaining = remaining - 1
                line = line - 1
                rows = row_count(line)
                off = rows - 1
                if remaining == 0 then break end
            end
        end
    end

    self.scrolly[1] = line
    self.scrolly[2] = math.max(0, off)
end

function Window:_wrap_pos_from_row_offset(row_offset, params, include_virtual)
    local linecnt = self.buffer:line_count(true)
    local line = self.scrolly[1]
    local off = self.scrolly[2] or 0

    if line < 1 then line = 1 end
    if line > linecnt then line = linecnt end

    local use_virtual = (include_virtual ~= false)
    local function row_count(idx)
        if use_virtual and idx == self.cursory then
            return self:_wrap_row_count_with_cursor(idx, params)
        end
        return self:_wrap_row_count(idx, params)
    end

    local function layout_for(idx)
        return self:_wrap_layout(idx, params, nil)
    end

    if row_offset >= 0 then
        local remaining = row_offset
        while true do
            local lines, ranges, gsrc = layout_for(line)
            local rows = #lines
            if rows < 1 then rows = 1 end
            if off > rows - 1 then off = rows - 1 end
            local avail = rows - off
            if remaining < avail or line >= linecnt then
                local row_in_line = off + remaining + 1
                if row_in_line > rows then row_in_line = rows end
                return line, row_in_line, lines, ranges, gsrc
            end
            remaining = remaining - avail
            line = line + 1
            off = 0
            if line > linecnt then
                line = linecnt
                lines, ranges, gsrc = layout_for(line)
                rows = #lines
                if rows < 1 then rows = 1 end
                return line, rows, lines, ranges, gsrc
            end
        end
    else
        local remaining = -row_offset
        while true do
            local lines, ranges, gsrc = layout_for(line)
            local rows = #lines
            if rows < 1 then rows = 1 end
            if off > rows - 1 then off = rows - 1 end

            if remaining <= off then
                local row_in_line = off - remaining + 1
                return line, row_in_line, lines, ranges, gsrc
            end

            remaining = remaining - off
            if line <= 1 then
                lines, ranges, gsrc = layout_for(1)
                return 1, 1, lines, ranges, gsrc
            end

            remaining = remaining - 1
            line = line - 1
            lines, ranges, gsrc = layout_for(line)
            rows = #lines
            if rows < 1 then rows = 1 end
            off = rows - 1
            if remaining == 0 then
                return line, off + 1, lines, ranges, gsrc
            end
        end
    end
end

function Window:_wrap_bytecol_from_layout(line_idx, row_in_line, screen_col, lines, ranges, gsrc, allow_eol)
    local line_str = self.buffer:get_line(line_idx, true) or ""
    local line_count = #lines
    if row_in_line > line_count then
        return allow_eol and (#line_str + 1) or math.max(1, #line_str)
    end
    local row_str = lines[row_in_line] or ""
    local row_len = #row_str

    if row_len < 1 then
        return 1
    end

    if allow_eol and screen_col > row_len then
        return #line_str + 1
    end

    if screen_col < 1 then screen_col = 1 end
    if screen_col > row_len then screen_col = row_len end

    local range = ranges and ranges[row_in_line]
    local gidx = range and (range.i + screen_col - 1) or screen_col
    local bytecol = gsrc and gsrc[gidx] or screen_col
    if not bytecol or bytecol < 1 then bytecol = 1 end
    return bytecol
end

function Window:_set_cursor_raw(line_idx, col1)
    local linecnt = self.buffer:line_count(true)
    if line_idx < 1 then line_idx = 1 end
    if line_idx > linecnt then line_idx = linecnt end

    local line = self.buffer:get_line(line_idx, true) or ""
    local ll = #line

    local newx = col1 or self.cursorx
    if newx < 1 then
        newx = 1
    else
        if vimmode == "normal" then
            if newx > ll then newx = math.max(1, ll) end
        elseif vimmode == "insert" then
            if newx > ll + 1 then newx = math.max(1, ll + 1) end
        else
            error("idk what to do with the mode: " .. vimmode)
        end
    end

    self.cursory = line_idx
    self.cursorx = newx
end

function Window:cursorScreenRow()
    if not self.opts.wrap then
        return (self.cursory - self.scrolly[1])
    end
    local _, params = self:_wrap_params()
    local row_offset = self:_wrap_cursor_pos(params)
    return row_offset
end

function Window:cursorSetScreenRow(row_offset, opts)
    opts = opts or {}
    local start_of_line = opts.startofline

    if not self.opts.wrap then
        local line = self.scrolly[1] + (row_offset or 0)
        local linecnt = self.buffer:line_count(true)
        if line < 1 then line = 1 end
        if line > linecnt then line = linecnt end

        local col = self.cursorx
        if start_of_line and options.get("startofline") then
            local idx = (self.buffer:get_line(line, true) or ""):find("%S")
            col = idx or 1
        elseif opts.screen_col then
            col = self:_col1_for_visual_col(self.buffer:get_line(line, true) or "", opts.screen_col, vimmode == "insert")
        end

        self:cursorSet(col, line, true)
        return
    end

    local _, params = self:_wrap_params()
    local desired_col = opts.screen_col
    if not desired_col then
        local _, col_in_row = self:_wrap_cursor_pos(params)
        desired_col = col_in_row
    end

    local line_idx, row_in_line, lines, ranges, gsrc = self:_wrap_pos_from_row_offset(row_offset or 0, params)

    local screen_col = desired_col
    if start_of_line and options.get("startofline") then
        local seg = lines[row_in_line] or ""
        local nb = seg:find("%S")
        screen_col = nb or 1
    end

    local col1 = self:_wrap_bytecol_from_layout(line_idx, row_in_line, screen_col, lines, ranges, gsrc, vimmode == "insert")
    self:cursorSet(col1, line_idx, true)
end

function Window:cursorMoveScreen(dy)
    dy = dy or 0
    if dy == 0 then return end
    if not self.opts.wrap then
        self:cursorMove(0, dy)
        return
    end

    local _, params = self:_wrap_params()
    local row_offset, col_in_row = self:_wrap_cursor_pos(params)
    self:cursorSetScreenRow(row_offset + dy, { screen_col = col_in_row })
end

-- TODO: Scroll validation only functions properly on screen lines. Tabs bork things pretty bad
function Window:cursorMove(deltax, deltay, force_reset_held_x)
    self.buffer:ensure_loaded(true)
    deltax = deltax or 0
    deltay = deltay or 0

    if force_reset_held_x then
        self._held_vx = nil
    end

    local had_y_move = (deltay ~= 0)

    if (deltax == 0) and had_y_move and (self._held_vx == nil) and (not force_reset_held_x) then
        local tcfg    = Tab.get_tab_config(self.buffer)
        local line    = self.buffer:get_line(self.cursory, true) or ""
        self._held_vx = Tab.vcol_of_prefix(line, self.cursorx, tcfg)
        if self._held_vx < 1 then self._held_vx = 1 end
    end

    if deltax ~= 0 then
        self._held_vx = nil
    end

    local newy = self.cursory + deltay
    newy = math.max(1, math.min(newy, self.buffer:line_count(true)))

    local newx

    if deltax ~= 0 then
        newx = self.cursorx + deltax
    elseif had_y_move and self._held_vx then
        local line = self.buffer:get_line(newy, true) or ""
        local insert_mode = (vimmode == "insert")
        newx = self:_col1_for_visual_col(line, self._held_vx, insert_mode)
    else
        newx = self.cursorx
    end

    if newx < 1 then
        newx = 1
    else
        local ll = #(self.buffer:get_line(newy, true) or "")
        if vimmode == "normal" then
            if newx > ll then
                newx = math.max(1, ll)
            end
        elseif vimmode == "insert" then
            if newx > ll + 1 then
                newx = math.max(1, ll + 1)
            end
        else
            error("idk what to do with the mode: " .. vimmode)
        end
    end

    self.cursory = newy
    self.cursorx = newx

    if self.opts.wrap then
        local height = self:textheight()
        if height < 1 then height = 1 end
        local _, params = self:_wrap_params()
        local cur_row = self:_wrap_cursor_pos(params)
        if cur_row < 0 then
            self:_wrap_scroll_rows(cur_row, params)
        elseif cur_row >= height then
            self:_wrap_scroll_rows(cur_row - height + 1, params)
        end
        self.scrollx = 0
    else
        local height = self:textheight()
        local offset = newy - self.scrolly[1]

        if offset >= height then
            -- TODO: min scroll options
            self.scrolly[1] = self.scrolly[1] + (offset - height + 1)
        elseif offset < 0 then
            self.scrolly[1] = self.scrolly[1] + offset
        end

        local width = self:textwidth()
        local offset_x = newx - self.scrollx

        if offset_x >= width then
            self.scrollx = self.scrollx + (offset_x - width + 1)
        elseif offset_x < 0 then
            self.scrollx = self.scrollx + offset_x
        end
    end

    need_redraw = true
    self.need_redraw = true

    local n = Autocmd.Run("CursorMoved")
end

function Window:cursorSet(x, y, force_reset_held_x)
    x = x or self.cursorx
    y = y or self.cursory
    self:cursorMove(x - self.cursorx, y - self.cursory, force_reset_held_x)
end

function Window:cursorSetX(x, force_reset_held_x)
    x = x or self.cursorx
    self:cursorMove(x - self.cursorx, 0, force_reset_held_x)
end

function Window:cursorSetY(y, force_reset_held_x)
    y = y or self.cursory
    self:cursorMove(0, y - self.cursory, force_reset_held_x)
end

function Window:scroll(deltax, deltay)
    self.buffer:ensure_loaded(true)
    if deltay ~= 0 then
        if self.opts.wrap then
            local height = self:textheight()
            if height < 1 then height = 1 end
            local _, params = self:_wrap_params()
            self:_wrap_scroll_rows(deltay, params)

            local cur_row, cur_col = self:_wrap_cursor_pos(params)
            if cur_row < 0 then
                local line_idx, row_in_line, lines, ranges, gsrc = self:_wrap_pos_from_row_offset(0, params)
                local col1 = self:_wrap_bytecol_from_layout(line_idx, row_in_line, cur_col, lines, ranges, gsrc,
                    vimmode == "insert")
                self:_set_cursor_raw(line_idx, col1)
            elseif cur_row >= height then
                local line_idx, row_in_line, lines, ranges, gsrc = self:_wrap_pos_from_row_offset(height - 1, params)
                local col1 = self:_wrap_bytecol_from_layout(line_idx, row_in_line, cur_col, lines, ranges, gsrc,
                    vimmode == "insert")
                self:_set_cursor_raw(line_idx, col1)
            end
        else
            local newy = self.scrolly[1] + deltay

            newy = math.max(1, math.min(self.buffer:line_count(true), newy))

            self.scrolly[1] = newy
            if self.cursory < newy then
                self.cursory = newy
            else
                local textheight = self:textheight()
                if self.cursory >= newy + textheight then
                    self.cursory = newy + textheight - 1
                end
            end
        end
    end

    if not self.opts.wrap then
        if deltax ~= 0 then
            local newx = self.scrollx + deltax

            newx = math.max(1, math.min(newx, #(self.buffer:get_line(self.cursory, true) or "")))

            self.scrollx = newx
            if self.cursorx < newx then
                self.cursorx = newx
            else
                local textwidth = self:textwidth()
                if self.cursorx >= newx + textwidth then
                    self.cursorx = newx + textwidth - 1
                end
            end
        end
    else
        LOG_ERROR("Attempt to scroll horizontally with wrap enabled!")
        self.scrollx = 0
    end

    need_redraw = true
    self.need_redraw = true
end

function Window:hasLocalStatusline()
    if self.floatpos or not self.frame then
        return false
    end

    local tabp = tabpages[curtp]
    if not tabp or not tabp.tree then
        return false
    end

    local laststat = options.get("laststatus")
    local _, y = FrameTree.GetXY(self.frame)
    local frame_bottom = y + self.frame.height - 1
    local touches_bottom = frame_bottom >= tabp.tree.height
    if not touches_bottom then
        if laststat == 3 then
            return false
        end
        return true
    end

    if laststat == 2 then
        return true
    end

    if laststat == 1 and #tabp.windows > 1 then
        return true
    end

    return false
end

function Window:hasHorizontalSeparator()
    if self.floatpos or not self.frame then
        return false
    end

    local tabp = tabpages[curtp]
    if not tabp or not tabp.tree then
        return false
    end

    local _, y = FrameTree.GetXY(self.frame)
    local frame_bottom = y + self.frame.height - 1
    if frame_bottom < tabp.tree.height then
        return true
    end

    return self:hasLocalStatusline()
end

--- Compute how many rows are available for text, accounting for the statusline.
--- Returns:
---   rows     -- drawable rows for buffer text (excludes statusline if shown)
---   dostatus -- whether the statusline is currently shown (for the caller to draw)
function Window:textheight()
    local frame = self.frame
    local has_sep = self:hasHorizontalSeparator()

    local rows
    if frame then
        rows = frame.height - (has_sep and 1 or 0)
    elseif self.floatpos then
        rows = self.floatpos.h
    else
        error("textheight: no floatpos or frame!")
    end
    if rows < 0 then rows = 0 end

    return rows, has_sep
end

--- Compute the on-screen text region for this window.
--- Returns:
---   text_x        -- 1-based column where buffer text starts (inside the pane)
---   text_w        -- width of the text drawing area (columns)
---   gutter_w      -- reserved width for the number gutter (0 if hidden)
---   use_right_col -- whether any visible label needs the gutter's rightmost col
---   pane_w        -- drawable pane width after a possible vertical split line
---   view_rows     -- drawable rows after statusline handling
function Window:textwidth()
    self.buffer:ensure_loaded(true)
    local frame = self.frame

    local pane_w
    if frame then
        pane_w = frame.width
        if FrameTree.IsLeftChild(frame) then
            pane_w = pane_w - 1
        end
    elseif self.floatpos then
        pane_w = self.floatpos.w
    else
        error("textwidth: no floatpos or frame!")
    end

    local view_rows, dostatus = self:textheight()

    local number              = (self.style ~= "minimal") and options.get("number", self)
    local rnu                 = (self.style ~= "minimal") and options.get("relativenumber", self)
    local show_numbers        = number or rnu
    local gutter_w            = show_numbers and math.max(0, options.get("numberwidth", self)) or 0

    local use_right_col       = false
    if show_numbers and gutter_w > 0 and view_rows > 0 then
        local start_idx = self.scrolly[1]
        local lines     = self.buffer:lines_ref(true)
        local linecnt   = #lines
        local stop      = math.min(linecnt, start_idx + view_rows - 1)

        for ii = start_idx, stop do
            local label
            if rnu then
                if ii == self.cursory then
                    label = number and tostring(ii) or "0"
                else
                    label = tostring(math.abs(ii - self.cursory))
                end
            else
                label = tostring(ii)
            end
            if #label >= gutter_w then
                use_right_col = true
                break
            end
        end
    end

    local pad = (use_right_col and 1 or 0)
    local text_x = 1 + gutter_w + pad
    local text_w = pane_w - gutter_w - pad
    if text_w < 0 then text_w = 0 end

    return text_w, text_x, gutter_w, use_right_col, view_rows
end

-- xoff and yoff are for global windows using frames. ignored otherwise
function Window:render(xoff, yoff)
    self.buffer:ensure_loaded(true)
    local frame    = self.frame
    local floatpos = self.floatpos
    local baseheight

    local width, height
    if frame then
        width, height = frame.width, frame.height
    elseif floatpos then
        if floatpos.reltype == "editor" then
            xoff, yoff, width, height = floatpos.x, floatpos.y, floatpos.w, floatpos.h
        else
            error("Unhandled floating window type: " .. (floatpos.reltype or "nil (lua nil)"))
        end
    else
        error("Window does not have a frame and has no float information!")
    end
    baseheight = height

    local function setPos(rx, ry)
        local ax = (xoff or 1) + rx - 1
        local ay = (yoff or 1) + ry - 1
        term.setCursorPos(ax, ay)
    end

    -- Clear this window's drawable region first
    Highlight.SetFor("Normal")
    for i = 1, height do
        setPos(1, i)
        term.write(string.rep(" ", width))
    end

    local extendstatus = 0
    local has_sep = self:hasHorizontalSeparator()
    local dostatus = self:hasLocalStatusline()
    if frame and FrameTree.IsLeftChild(frame) then
        Highlight.SetFor("VertSplit")
        local fc = options.ParseKeyedCSL(options.get("fillchars", self), { [":"] = true }).vert or "|"
        local split_rows = height - (has_sep and 1 or 0)
        for i = 1, split_rows do
            setPos(width, i)
            term.write(fc)
        end
        width = width - 1
        extendstatus = extendstatus + 1
    end

    -- Statusline prechecks
    local lines                                             = self.buffer:lines_ref(true)
    local linecnt                                           = #lines
    local start_idx                                         = self.scrolly[1]
    local text_w, text_x, gutter_w, use_right_col, max_rows = self:textwidth()
    local rnu                                               = options.get("relativenumber", self)
    local show_numbers                                      = (self.style ~= "minimal") and
        (options.get("number", self) or rnu)
    local view_top                                          = math.min(math.max(1, start_idx), math.max(1, linecnt))
    local view_bottom

    local function draw_gutter(row_y, label, iscursor, needs_right)
        if gutter_w <= 0 then return end
        setPos(1, 1 + row_y)
        if iscursor and options.get("cursorline", self) then
            Highlight.SetFor("CursorLineNr")
        else
            Highlight.SetFor("LineNr")
        end

        local s   = label or ""
        local len = #s
        if len > gutter_w then
            s = string.rep("+", gutter_w)
        else
            local cap = gutter_w - (needs_right and 0 or 1)

            if (self.style ~= "minimal") and iscursor and options.get("number", self) and options.get("relativenumber", self) then
                if len > cap then
                    s = string.rep("+", gutter_w)
                else
                    s = s .. string.rep(" ", cap - len)
                    if not needs_right then s = s .. " " end
                end
            else
                local pad = cap - len
                if pad < 0 then pad = 0 end
                local left = math.ceil(pad / 2)
                local right = pad - left
                s = string.rep(" ", left) .. s .. string.rep(" ", right)
                if not needs_right then s = s .. " " end
            end
        end

        term.write(s)
        Highlight.SetFor("Normal")
    end

    -- Horizontal scroll (1-based)
    local hscroll = self.scrollx or 1
    if hscroll < 1 then hscroll = 1 end

    CmdRead = CmdRead or loadModule("vim.lib.excmd.cmdread")

    local tabcfg = Tab.get_tab_config(self.buffer)
    local listcfg = nil
    if options.get("list", self) then
        listcfg = ListChars.get(self)
    end
    local visual_y = 0
    local pending_cursor = nil
    local show_cursor = (self.winnr == curwin) and (not CmdRead.is_active())
    local last_visible_idx = math.min(linecnt, start_idx + max_rows - 1)
    local prefetched_blits = Syntax.LinesToBlit(self.buffer, start_idx, last_visible_idx, self)

    -- Draw buffer lines
    for i = start_idx, linecnt do
        if visual_y >= max_rows then break end

        view_bottom = i

        local rendered, blitLines, cursorPos = TexRen.parse(
            lines[i] or "",
            {
                wraplen  = (self.opts.wrap and text_w) or 0,
                wordwrap = self.opts.wrap and options.get("linebreak", self),
                breakat  = (self.opts.wrap and options.get("linebreak", self)) and options.get("breakat") or nil,
                listcfg  = listcfg,
                tabcfg   = tabcfg
            },
            (self.cursory == i) and self.cursorx or nil,
            prefetched_blits[i]
        )

        local have_blit = blitLines and blitLines.fg and blitLines.bg

        local cursor_virtual = false
        if show_cursor and (self.cursory == i) and cursorPos then
            if cursorPos.line == (#rendered + 1) then
                cursor_virtual = true
            elseif self.opts.wrap and (vimmode == "insert") then
                local line_str = lines[i] or ""
                if self.cursorx == (#line_str + 1) then
                    local last = rendered[#rendered] or ""
                    if (text_w > 0) and (#last == text_w) then
                        cursor_virtual = true
                    end
                end
            end
        end

        local j_start = 1
        if self.opts.wrap and i == start_idx then
            local skip = self.scrolly[2] or 0
            if skip < 0 then skip = 0 end
            local max_skip = math.max(0, #rendered - 1)
            if (self.cursory == i) and cursorPos and (cursorPos.line == (#rendered + 1)) then
                max_skip = math.max(max_skip, #rendered)
            end
            if skip > max_skip then skip = max_skip end
            if (self.scrolly[2] or 0) ~= skip then
                self.scrolly[2] = skip
            end
            j_start = 1 + skip
        end

        for j = j_start, #rendered do
            if visual_y >= max_rows then break end

            if show_numbers then
                local label = ""
                local iscursor = i == self.cursory
                if j == 1 then
                    if rnu then
                        if iscursor then
                            label = options.get("number", self) and tostring(i) or "0"
                        else
                            label = tostring(math.abs(i - self.cursory))
                        end
                    else
                        label = tostring(i)
                    end
                end
                draw_gutter(visual_y, label, iscursor, use_right_col)
            end

            -- Visible slice after horizontal scroll
            local text = rendered[j]
            local x1 = hscroll
            local x2 = hscroll + math.max(0, text_w) - 1
            if x2 < x1 then x2 = x1 - 1 end
            local vis_text = (x2 >= x1) and text:sub(x1, x2) or ""

            local fg_slice, bg_slice
            if have_blit then
                local fg_line = blitLines.fg[j] or ""
                local bg_line = blitLines.bg[j] or ""
                fg_slice = (x2 >= x1) and fg_line:sub(x1, x2) or ""
                bg_slice = (x2 >= x1) and bg_line:sub(x1, x2) or ""
            end

            -- Draw text/blit
            if text_w > 0 then
                setPos(text_x, 1 + visual_y)
                if have_blit and #fg_slice == #vis_text and #bg_slice == #vis_text then
                    term.blit(vis_text, fg_slice, bg_slice)
                else
                    Highlight.SetFor("Normal")
                    term.write(vis_text)
                end
            end

            -- Draw cursor using Cursor highlight
            if show_cursor and (not cursor_virtual) and (self.cursory == i) and cursorPos and (cursorPos.line == j) and text_w > 0 then
                local cx_abs = cursorPos.column       -- 1-based in wrapped piece
                local cx_vis = cx_abs - (hscroll - 1) -- 1-based in visible slice

                if cx_vis >= 1 and cx_vis <= math.max(1, math.min(text_w, #vis_text + 1)) then
                    local screen_x = text_x + (cx_vis - 1)
                    local screen_y = 1 + visual_y
                    local ch = cursorPos.ch or " "
                    setPos(screen_x, screen_y)
                    Highlight.SetFor("Cursor")
                    term.write(ch)
                    Highlight.SetFor("Normal")
                end
            end

            visual_y = visual_y + 1
        end

        if show_cursor and cursor_virtual then
            -- Cursor is on the virtual wrap row (EOL exactly at width).
            -- Defer drawing so it can overlay the next visible row.
            pending_cursor = { row_offset = visual_y, col = 1 }
        end
    end

    local buffer_rows_total = visual_y

    -- End-of-buffer fill
    while visual_y < max_rows do
        if text_w > 0 then
            setPos(1, 1 + visual_y)
            Highlight.SetFor("EndOfBuffer")
            term.write(options.ParseKeyedCSL(options.get("fillchars", self), { [":"] = true }).eob or "~")
            Highlight.SetFor("Normal")
        end
        visual_y = visual_y + 1
    end

    -- Deferred cursor overlay for the virtual wrap row.
    if show_cursor and pending_cursor and text_w > 0 then
        local row_offset = pending_cursor.row_offset or 0
        if row_offset >= 0 and row_offset < max_rows then
            local cx_abs = pending_cursor.col or 1
            local cx_vis = cx_abs - (hscroll - 1)
            if cx_vis >= 1 and cx_vis <= math.max(1, text_w) then
                local ch = " "
                if row_offset >= buffer_rows_total then
                    ch = " "
                else
                    local _, wrap_params = self:_wrap_params()
                    wrap_params.listcfg = listcfg
                    local _, row_in_line, lines = self:_wrap_pos_from_row_offset(row_offset, wrap_params, false)
                    local row_str = (lines and lines[row_in_line]) or ""
                    local x1 = hscroll
                    local x2 = hscroll + math.max(0, text_w) - 1
                    if x2 < x1 then x2 = x1 - 1 end
                    local vis_text = (x2 >= x1) and row_str:sub(x1, x2) or ""
                    if cx_vis >= 1 and cx_vis <= #vis_text then
                        ch = vis_text:sub(cx_vis, cx_vis)
                    else
                        ch = " "
                    end
                end
                local screen_x = text_x + (cx_vis - 1)
                local screen_y = 1 + row_offset
                setPos(screen_x, screen_y)
                Highlight.SetFor("Cursor")
                term.write(ch)
                Highlight.SetFor("Normal")
            end
        end
    end

    if not view_bottom then view_bottom = view_top end
    self.view_top = view_top
    self.view_bottom = view_bottom

    -- Statusline
    if dostatus and not self.floatpos then
        setPos(1, baseheight)
        local spans = Statusline.Parse(options.get("statusline", self), self)
        for s = 1, #spans do
            Highlight.SetFor(spans[s][2])
            term.write(spans[s][1])
        end
        Highlight.SetFor("Normal")
    elseif has_sep and not self.floatpos then
        local fcs = options.ParseKeyedCSL(options.get("fillchars", self), { [":"] = true })
        local hc = fcs.horiz or "-"
        Highlight.SetFor("VertSplit")
        setPos(1, baseheight)
        term.write(string.rep(hc, math.max(0, width)))
        Highlight.SetFor("Normal")
    end
end

function Window:drawStatus(xoff, yoff)
    term.setCursorPos(xoff, yoff + self.frame.height - 1)

    local spans = Statusline.Parse(options.get("statusline", self), self)
    for s = 1, #spans do
        Highlight.SetFor(spans[s][2])
        term.write(spans[s][1])
    end

    Highlight.SetFor("Normal")
end

function Window:matchPairs()
    local win   = windows[curwin]
    win.buffer:ensure_loaded(true)
    local lines = win.buffer:lines_ref(true)
    local y     = win.cursory
    local x     = win.cursorx

    local line  = lines[y] or ""
    if #line == 0 or x < 1 or x > #line then
        return
    end

    local mp = options.ParseKeyedCSL(options.get("matchpairs", nil, self.buffer), { [":"] = true })

    -- Build fast lookup tables
    local start2stop, stop2start, is_start, is_stop = {}, {}, {}, {}
    for s, e in pairs(mp) do
        start2stop[s] = e
        stop2start[e] = s
        is_start[s]   = true
        is_stop[e]    = true
    end

    local function ch_at(i)
        return line:sub(i, i)
    end

    -- Forward scan for the matching 'stop' of a given 'start' at position i0
    local function find_match_forward(i0, startc, stopc)
        local depth = 1
        for i = i0 + 1, #line do
            local c = ch_at(i)
            if c == startc then
                depth = depth + 1
            elseif c == stopc then
                depth = depth - 1
                if depth == 0 then
                    return i
                end
            end
        end
        return nil
    end

    -- Backward scan for the matching 'start' of a given 'stop' at position i0
    local function find_match_backward(i0, startc, stopc)
        local depth = 1
        for i = i0 - 1, 1, -1 do
            local c = ch_at(i)
            if c == stopc then
                depth = depth + 1
            elseif c == startc then
                depth = depth - 1
                if depth == 0 then
                    return i
                end
            end
        end
        return nil
    end

    -- Scan forward (strictly after position x) for the first pair character on this line
    local function first_pair_after(pos)
        for i = pos + 1, #line do
            local c = ch_at(i)
            if is_start[c] or is_stop[c] then
                return i, c
            end
        end
        return nil, nil
    end

    local cur = ch_at(x)

    -- Case 1: cursor is on a start or end char -> jump to its match, if any.
    if is_start[cur] then
        local stopc = start2stop[cur]
        local j = find_match_forward(x, cur, stopc)
        if j then self:cursorMove(j - self.cursorx, y - self.cursory) end
        return
    elseif is_stop[cur] then
        local startc = stop2start[cur]
        local j = find_match_backward(x, startc, cur)
        if j then self:cursorMove(j - self.cursorx, y - self.cursory) end
        return
    end

    -- Case 2: not on a pair char -> look forward for first pair char on this line.
    local i, c = first_pair_after(x)
    if not i then
        -- Nothing to do if no pair chars after cursor on this line
        return
    end

    if is_start[c] then
        -- Found a start first -> jump to its matching end (if any).
        local stopc = start2stop[c]
        local j = find_match_forward(i, c, stopc)
        if j then self:cursorMove(j - self.cursorx, y - self.cursory) end
        return
    else
        -- Found an end before any start -> search backward for that end's start.
        local startc = stop2start[c]
        local j = find_match_backward(i, startc, c)
        if j then self:cursorMove(j - self.cursorx, y - self.cursory) end
        return
    end
end

local function _first_non_blank_col1(s)
    for i = 1, #s do
        local ch = s:sub(i, i)
        if ch ~= " " and ch ~= "\t" then
            return i
        end
    end
    return #s + 1
end

local function _decode_indent_key(raw)
    local tok = tostring(raw or "")
    if tok == "" then return nil end

    if tok:sub(1, 1) == "<" and tok:sub(-1) == ">" then
        local inner = tok:sub(2, -2)
        local lower = inner:lower()
        if lower == "return" or lower == "cr" then return "\n" end
        if lower == "tab" then return "\t" end
        if lower == "space" then return " " end
        if lower == "bar" then return "|" end
        if lower == "lt" then return "<" end
        if lower == "bs" then return "\b" end
        if #inner == 1 then return inner end
        return nil
    end

    if tok:sub(1, 1) == "^" and #tok == 2 then
        local b = string.byte(tok:sub(2, 2))
        if b and b >= 64 then
            return string.char(b - 64)
        end
    end

    return tok
end

local function _parse_indentkeys(raw)
    local out = {}
    local items = options.ParseCSL(tostring(raw or ""))
    for i = 1, #items do
        local tok = tostring(items[i] or "")
        if tok ~= "" then
            local spec = {
                before = false,
                noinsert = false,
                start_only = false,
            }
            while true do
                local c = tok:sub(1, 1)
                if c == "!" then
                    spec.noinsert = true
                    tok = tok:sub(2)
                elseif c == "*" then
                    spec.before = true
                    tok = tok:sub(2)
                elseif c == "0" then
                    spec.start_only = true
                    tok = tok:sub(2)
                else
                    break
                end
            end

            if tok == "o" then
                spec.kind = "open"
                spec.which = "o"
            elseif tok == "O" then
                spec.kind = "open"
                spec.which = "O"
            elseif tok == "e" then
                spec.kind = "else"
            elseif tok:sub(1, 2) == "=~" then
                spec.kind = "word"
                spec.word = tok:sub(3)
                spec.ignorecase = true
            elseif tok:sub(1, 1) == "=" then
                spec.kind = "word"
                spec.word = tok:sub(2)
                spec.ignorecase = false
            else
                spec.kind = "key"
                spec.key = _decode_indent_key(tok)
            end
            out[#out + 1] = spec
        end
    end
    return out
end

function Window:_eval_indentexpr(lnum)
    self.buffer:ensure_loaded(true)
    local expr = tostring(options.get("indentexpr", nil, self.buffer) or "")
    if expr == "" then
        return nil, false
    end

    VimExpr = VimExpr or loadModule("vim.lib.excmd.vimxpr")
    VimFn = VimFn or loadModule("vim.lib.luaapi.fn")
    Scopes = Scopes or loadModule("vim.lib.luaapi.scopes")

    local save_y, save_x = self.cursory, self.cursorx
    local max_line = math.max(1, self.buffer:line_count(true))
    local target_y = math.max(1, math.min(max_line, lnum))
    local target_line = self.buffer:get_line(target_y, true) or ""

    self.cursory = target_y
    if self.cursorx > #target_line + 1 then
        self.cursorx = #target_line + 1
    elseif self.cursorx < 1 then
        self.cursorx = 1
    end

    local rv = VimExpr.evaluate(expr, {
        scope = { g = Scopes._g, v = { lnum = lnum } },
        funcs = VimFn,
    })

    self.cursory, self.cursorx = save_y, save_x

    if Error.IsError(rv) then
        return nil, false
    end
    local n = tonumber(rv)
    if not n then
        return nil, false
    end
    return math.floor(n), true
end

function Window:_build_indent_prefix(vcols)
    vcols = math.max(0, math.floor(tonumber(vcols) or 0))
    if vcols == 0 then
        return ""
    end

    if options.get("expandtab", nil, self.buffer) then
        return string.rep(" ", vcols)
    end

    local tcfg = Tab.get_tab_config(self.buffer)
    local out = {}
    local v = 0
    while true do
        local nxt = Tab.next_display_tabstop(v, tcfg)
        if nxt > vcols then
            break
        end
        out[#out + 1] = "\t"
        v = nxt
    end
    if v < vcols then
        out[#out + 1] = string.rep(" ", vcols - v)
    end
    return table.concat(out)
end

function Window:reindentLine(lnum, want_vcol, cursor_col1)
    self.buffer:ensure_loaded(true)
    local lines = self.buffer:lines_ref(true)
    local ln = math.max(1, math.min(lnum, #lines))
    local line = lines[ln] or ""

    local fnb = _first_non_blank_col1(line)
    local old_prefix_len = fnb - 1
    local tail = line:sub(fnb)

    local prefix = self:_build_indent_prefix(want_vcol)
    if prefix == line:sub(1, old_prefix_len) then
        return cursor_col1 or self.cursorx
    end

    lines[ln] = prefix .. tail
    self.buffer.opts.modified = true
    Syntax.ParseLinetypes(self.buffer, math.max(1, ln - 1))

    local col = cursor_col1 or self.cursorx
    local delta = #prefix - old_prefix_len
    col = col + delta
    if col < 1 then col = 1 end
    local max_col = #(lines[ln] or "") + 1
    if col > max_col then col = max_col end
    return col
end

function Window:computeIndentForLine(lnum)
    self.buffer:ensure_loaded(true)
    local lines = self.buffer:lines_ref(true)
    if #lines == 0 then return 0 end

    local ind, ok = self:_eval_indentexpr(lnum)
    if ok then
        if ind >= 0 then
            return ind
        end
    end

    if options.get("autoindent", nil, self.buffer) and lnum > 1 then
        local prev = lines[lnum - 1] or ""
        local tcfg = Tab.get_tab_config(self.buffer)
        local prev_fnb = _first_non_blank_col1(prev)
        return Tab.vcol_of_prefix(prev, prev_fnb, tcfg)
    end

    return 0
end

function Window:indentkeysHasOpenTrigger(which)
    local expr = tostring(options.get("indentexpr", nil, self.buffer) or "")
    if expr == "" then
        return false
    end
    local parsed = _parse_indentkeys(options.get("indentkeys", nil, self.buffer) or "")
    for i = 1, #parsed do
        local item = parsed[i]
        if item.kind == "open" and item.which == which then
            return true
        end
    end
    return false
end

-- TODO: handle the delete character
function Window:insertText(text, line, offset, insetoff, cursor_on_end)
    self.buffer:ensure_loaded(true)
    line           = line or self.cursory
    local ln       = line
    local col1     = (offset or self.cursorx) + (insetoff or 0)

    text           = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")

    local tcfg     = Tab.get_tab_config(self.buffer)
    local scfg     = Tab.get_soft_config(self.buffer)
    local smarttab = options.get("smarttab")
    local has_indentexpr = tostring(options.get("indentexpr", nil, self.buffer) or "") ~= ""
    local indentkeys = _parse_indentkeys(options.get("indentkeys", nil, self.buffer) or "")

    -- parse 'backspace' as a set
    local bs_flags = {}
    do
        local raw = options.get("backspace") or ""
        local items = options.ParseCSL(raw)
        for i = 1, #items do bs_flags[items[i]] = true end
    end

    -- TODO: fetch insert-mode start position from editor state
    local ins_start_line = 1
    local ins_start_col1 = 1

    local function before(aL, aC, bL, bC) return (aL < bL) or (aL == bL and aC < bC) end
    local function is_in_leading_ws(s, c1) return c1 <= _first_non_blank_col1(s) end

    local function whitespace_span_before(s, at_col1)
        local i = at_col1 - 2
        if i < 0 then return at_col1 - 1, at_col1 - 1 end
        while i >= 0 do
            local ch = s:sub(i + 1, i + 1)
            if ch ~= " " and ch ~= "\t" then break end
            i = i - 1
        end
        return i + 1, at_col1 - 2 -- 0-based inclusive span
    end

    local lines = self.buffer:lines_ref(true)
    if ln < 1 then ln = 1 end
    if ln > self.buffer:line_count(true) then ln = self.buffer:line_count(true) end
    local cur = lines[ln] or ""
    if col1 < 1 then col1 = 1 end
    if col1 > #cur + 1 then col1 = #cur + 1 end

    local first_dirty = math.huge
    local function mark_dirty(i)
        if not i or i < 1 then return end
        if i < first_dirty then first_dirty = i end
    end
    local function set_line(i, s)
        lines[i] = s
        mark_dirty(i)
    end

    local function do_split_line()
        local left  = cur:sub(1, col1 - 1)
        local right = cur:sub(col1)
        set_line(ln, left)
        ln = ln + 1
        table.insert(lines, ln, right)
        cur = lines[ln]
        col1 = 1
    end

    local function do_join_prev_line()
        if ln == 1 then return end
        local prev = lines[ln - 1]
        local new_prev = prev .. cur
        set_line(ln - 1, new_prev)
        self.buffer:remove_lines(ln, ln)
        ln = ln - 1
        cur = lines[ln]
        col1 = #prev + 1
    end

    local function vcol_at(c1)
        return Tab.vcol_of_prefix(cur, c1, tcfg)
    end

    local function _reindent_current_line()
        local want = self:computeIndentForLine(ln)
        col1 = self:reindentLine(ln, want, col1)
        cur = lines[ln] or ""
        mark_dirty(ln)
    end

    local function _indentkey_pre_newline()
        for i = 1, #indentkeys do
            local it = indentkeys[i]
            if it.kind == "key" and it.key == "\n" and it.before then
                return true
            end
        end
        return false
    end

    local function _indentkey_match_typed(ch, pre_line, pre_col, post_line, post_col)
        if not has_indentexpr then
            return false
        end

        for i = 1, #indentkeys do
            local it = indentkeys[i]
            if it.kind == "open" then
                -- Insert-mode newline is handled separately.
            elseif it.kind == "key" and it.key == ch then
                if it.start_only then
                    local before_part = pre_line:sub(1, pre_col - 1)
                    if before_part:match("^%s*$") then
                        return true
                    end
                else
                    return true
                end
            elseif it.kind == "else" and ch == "e" then
                local fnb = _first_non_blank_col1(post_line)
                local head = post_line:sub(fnb, fnb + 3):lower()
                if head == "else" then
                    return true
                end
            elseif it.kind == "word" then
                local w = tostring(it.word or "")
                if w ~= "" and post_col > 1 and post_col - 1 >= #w then
                    local lhs = post_line:sub(1, post_col - 1)
                    local tail = lhs:sub(#lhs - #w + 1)
                    local ok_word
                    if it.ignorecase then
                        ok_word = tail:lower() == w:lower()
                    else
                        ok_word = tail == w
                    end
                    if ok_word then
                        if it.start_only then
                            local pre_word = lhs:sub(1, #lhs - #w)
                            if pre_word:match("^%s*$") then
                                return true
                            end
                        else
                            return true
                        end
                    end
                end
            end
        end
        return false
    end

    -- Track whether the last action inserted text (vs. deletion)
    local last_action_inserted = false
    local last_inserted_newline = false

    for c in text:gmatch(".") do
        if c == "\n" then
            if _indentkey_pre_newline() then
                _reindent_current_line()
            end
            do_split_line()
            if has_indentexpr or options.get("autoindent", nil, self.buffer) then
                _reindent_current_line()
            end
            last_action_inserted = true
            last_inserted_newline = true
        elseif c == "\t" then
            local v   = vcol_at(col1)
            local lw  = is_in_leading_ws(cur, col1)
            local ins = Tab.compute_tab_insertion(v, lw, self.buffer)
            cur       = cur:sub(1, col1 - 1) .. ins .. cur:sub(col1)
            set_line(ln, cur)
            col1 = col1 + #ins
            last_action_inserted = (#ins > 0)
            last_inserted_newline = false
        elseif c == "\b" then
            if (not bs_flags.start) and before(ln, col1, ins_start_line, ins_start_col1) then
                goto continue
            end

            if col1 == 1 then
                if bs_flags.eol and ln > 1 then
                    local new_line, new_col1 = ln - 1, #(lines[ln - 1]) + 1
                    if (not bs_flags.start) and before(new_line, new_col1, ins_start_line, ins_start_col1) then
                        goto continue
                    end
                    do_join_prev_line()
                end
                last_action_inserted = false
                last_inserted_newline = false
                goto continue
            end

            if (not bs_flags.indent) and (col1 <= _first_non_blank_col1(cur)) then
                last_action_inserted = false
                last_inserted_newline = false
                goto continue
            end

            local lw = is_in_leading_ws(cur, col1)
            local scfg_eff = scfg
            if smarttab and lw then
                scfg_eff = { vsts = {}, prefix = {}, last_step = nil, numeric_sts = Tab.shiftwidth_effective(self.buffer) }
            end
            local soft_enabled = (#scfg_eff.vsts > 0) or (scfg_eff.numeric_sts and scfg_eff.numeric_sts > 0)

            local i0, i1 = whitespace_span_before(cur, col1)
            if soft_enabled and i1 >= i0 then
                local v1 = vcol_at(col1)
                local v0 = Tab.vcol_of_prefix(cur, i0 + 1, tcfg)
                local want = v1 - Tab.prev_soft_boundary(v1, scfg_eff)
                if want < 1 then want = 1 end
                local run_cols = v1 - v0
                if want > run_cols then want = run_cols end
                if (not bs_flags.start) and (ln == ins_start_line) then
                    local min_col1 = math.max(ins_start_col1, 1)
                    local max_del_chars = col1 - min_col1
                    if max_del_chars < want then want = max_del_chars end
                end
                if want > 0 then
                    local new_cols = run_cols - want
                    local new_ws = string.rep(" ", new_cols)
                    cur = cur:sub(1, i0) .. new_ws .. cur:sub(i1 + 2)
                    set_line(ln, cur)
                    col1 = i0 + #new_ws + 1
                    last_action_inserted = false
                    last_inserted_newline = false
                    goto continue
                end
            end

            local new_col1 = col1 - 1
            if (not bs_flags.start) and before(ln, new_col1, ins_start_line, ins_start_col1) then
                last_action_inserted = false
                last_inserted_newline = false
                goto continue
            end
            cur = cur:sub(1, col1 - 2) .. cur:sub(col1)
            set_line(ln, cur)
            col1 = new_col1
            last_action_inserted = false
            last_inserted_newline = false
        else
            local pre_line = cur
            local pre_col = col1
            cur = cur:sub(1, col1 - 1) .. c .. cur:sub(col1)
            set_line(ln, cur)
            col1 = col1 + 1
            if _indentkey_match_typed(c, pre_line, pre_col, cur, col1) then
                _reindent_current_line()
            end
            last_action_inserted = true
            last_inserted_newline = false
        end
        ::continue::
    end

    -- Cursor placement toggle
    if cursor_on_end and last_action_inserted then
        if last_inserted_newline then
            if ln > 1 then
                ln = ln - 1
                col1 = math.max(1, #lines[ln]) -- ON last char of previous line
            end
        else
            if col1 > 1 then col1 = col1 - 1 end -- ON last inserted char
        end
    end

    self:markUpdate((first_dirty ~= math.huge) and first_dirty or line)

    self:cursorMove(col1 - self.cursorx, ln - self.cursory)
    self.need_redraw = true
    need_redraw = true
end

function Window:pasteRegister(reg_name, line, offset, isBefore)
    self.buffer:ensure_loaded(true)
    line = line or self.cursory
    offset = offset or self.cursorx

    if registers[reg_name] then
        local regval = registers[reg_name]
        if regval[1] == "charwise" then
            self:insertText(regval[2], line, offset, isBefore and 0 or 1, true)
        elseif regval[1] == "linewise" then
            local lines = regval[2]
            local desty
            local buflines = self.buffer:lines_ref(true)

            if isBefore then
                for i = 1, #lines do
                    table.insert(buflines, line + i - 1, lines[i])
                end
                desty = line
            else
                for i = 1, #lines do
                    table.insert(buflines, line + 1, lines[#lines - i + 1])
                end
                desty = line + 1
            end

            self:markUpdate(line)

            self:cursorMove(-self.cursorx, desty - self.cursory)
        elseif regval[1] == "inline" then
            local to_paste = regval[2]
            local buflines = self.buffer:lines_ref(true)

            local cur = buflines[line]
            local cur_len = #cur

            local cx = math.max(1, math.min(offset, math.max(1, cur_len)))
            local prefix_len = isBefore and (cx - 1) or cx

            local prefix = (prefix_len > 0) and cur:sub(1, prefix_len) or ""
            local trail = cur:sub(prefix_len + 1)

            if #to_paste == 1 then
                buflines[line] = prefix .. to_paste[1] .. trail
            else
                buflines[line] = prefix .. to_paste[1]
                for i = 2, #to_paste - 1 do
                    table.insert(buflines, line + (i - 1), to_paste[i])
                end
                table.insert(buflines, line + (#to_paste - 1), to_paste[#to_paste] .. trail)
            end

            self:markUpdate(line)

            self:cursorSet(prefix_len + 1, line)
        else
            error("Unknown register paste type: " .. regval[1])
        end
    else
        return Error(353, reg_name)
    end

    self.need_redraw = true
end

function Window:markUpdate(line)
    local buf = self.buffer
    Syntax.ParseLinetypes(buf, math.max(1, (line or 1) - 1))
    buf.opts.modified = true

    for _, win in pairs(windows) do
        if win.buffer == buf then
            -- Force a cursor update
            win:cursorMove(0, 0)
        end
    end
end

-- force: when ! is specified
-- mustabandon: following this call the buffer must be abandoned - ex, vim is exiting
function Window:close(force, mustabandon, autowrite_kind)
    local status = self.buffer:leave(force, mustabandon, autowrite_kind)
    if status == true then
        return true
    end

    return status
end

function Window:resizeWidth(delta)
    if self.frame then
        return FrameTree.ResizeWidth(self.frame, delta)
    elseif self.floatpos then
        self.floatpos.w = math.max(1, self.floatpos.w + delta)
    end
    return false
end

function Window:resizeHeight(delta)
    if self.frame then
        return FrameTree.ResizeHeight(self.frame, delta)
    end
    self.floatpos.h = math.max(1, self.floatpos.h + delta)
    return false
end

local function cleanup_failed_split_window(win)
    if not win then
        return
    end
    if windows[win.winnr] == win then
        windows[win.winnr] = nil
    end
    local buf = win.buffer
    if buf and type(buf.refcount) == "number" then
        buf.refcount = math.max(0, buf.refcount - 1)
    end
end

-- Functions for moving around windows.
function Window:wincmd(command, count)
    local tp = tabpages[curtp]

    if command == "s" then
        local probe = tp:MakeSplitProbe(self)
        if not tp:WinSplit(0, probe, false, { dry_run = true }) then
            return Error(36)
        end

        -- TODO: set-width split
        local newwin = Window(self.buffer, self)
        if not tp:WinSplit(0, newwin, false) then
            cleanup_failed_split_window(newwin)
            return Error(36)
        end
        enterWindow(newwin.winnr)
    elseif command == "v" then
        local probe = tp:MakeSplitProbe(self)
        if not tp:WinSplit(0, probe, true, { dry_run = true }) then
            return Error(36)
        end

        -- TODO: set-width split
        local newwin = Window(self.buffer, self)
        if not tp:WinSplit(0, newwin, true) then
            cleanup_failed_split_window(newwin)
            return Error(36)
        end
        enterWindow(newwin.winnr)
    elseif command == "w" then
        local tabwins = tp.windows

        -- If a count is given (total), go to window [total] or next focusable from there.
        if count and count > 0 then
            local target = math.min(count, #tabwins)
            -- Find the first focusable window at or after target, wrapping once if needed
            local found
            for k = target, #tabwins do
                if tabwins[k].focusable then
                    found = k
                    break
                end
            end
            if not found then
                for k = 1, target - 1 do
                    if tabwins[k].focusable then
                        found = k
                        break
                    end
                end
            end
            if found then
                enterWindow(tabwins[found].winnr)
            end
            return
        end

        local i = 1
        while tabwins[i] ~= self do
            i = i + 1
            if i > #tabwins then
                LOG_ERROR("Internal error: window index not found in tabpage!")
                return
            end
        end

        local newi = i
        local next
        for k = newi + 1, #tabwins do
            if tabwins[k].focusable then
                next = k
                break
            end
        end
        if not next then
            for k = 1, newi - 1 do
                if tabwins[k].focusable then
                    next = k
                    break
                end
            end
        end
        if next then newi = next end

        enterWindow(tabwins[newi].winnr)
    elseif command == "T" then
        local tabp = tabpages[curtp]
        if #tabp.windows <= 1 then
            return
        end

        local win = windows[curwin]
        tabp:close(win, false, true)

        local ntp = Tabpage(win)

        curtp = ntp.tabnr
    elseif command == "=" then
        tabpages[curtp]:equalize()
    elseif command == ">" then
        self:resizeWidth(count or 1)
    elseif command == "<" then
        self:resizeWidth(count and -count or -1)
    elseif command == "+" then
        self:resizeHeight(count or 1)
    elseif command == "-" then
        self:resizeHeight(count and -count or -1)
    elseif command == "H" then
        -- TODO: Create functions to set up a mock tree and
        --       check if this works before committing to it

        local tabp = tabpages[curtp]
        local win = windows[curwin]

        tabp:close(win, false, true)
    
        tabp:WinSplit(-1, win, true)    
    else
        return Error(474)
    end

    what_redraw["all"] = true
    need_redraw = true
end

setmetatable(Window, { __call = function(self, ...) return self:new(...) end })

return Window
