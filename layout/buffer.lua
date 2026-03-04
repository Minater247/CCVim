local Buffer = {}
Buffer.__index = Buffer -- Share the instance methods

local Error = loadModule("lib.error")
local ExMsg = loadModule("lib.excmd.exmsg")
local AutoCmd = loadModule("lib.autocmd")
local VimFs = loadModule("lib.luaapi.fs")
local Syntax = loadModule("lib.syntax")
local Utf8 = loadModule("lib.utf8")
local BufAttach = loadModule("lib.bufattach")
local Sign

local curr_bufno = 1

local function _request_full_redraw()
    what_redraw["all"] = true
    need_redraw = true
end

local function _run_textchanged(buf, noauto)
    if noauto then
        return
    end
    if windows[curwin].buffer ~= buf then
        return
    end
    local event
    if vimmode == "terminal" then
        event = "TextChangedT"
    elseif vimmode == "insert" then
        event = "TextChangedI"
    else
        event = "TextChanged"
    end
    AutoCmd.Run(event, {
        bufnr = buf.bufnr,
        bufname = buf.name,
    })
end

local function _slice_lines(lines, s, e)
    local out = {}
    for i = s, e do
        out[#out + 1] = lines[i] or ""
    end
    return out
end

local function _bytes_of_lines(lines)
    local total = 0
    for i = 1, #lines do
        total = total + #(lines[i] or "")
    end
    if #lines > 1 then
        total = total + (#lines - 1)
    end
    return total
end

local function _bytes_before_row(lines, row0)
    local total = 0
    for i = 1, row0 do
        total = total + #(lines[i] or "") + 1
    end
    return total
end

local function _text_sizes(text)
    text = text or ""
    if text == "" then
        return 0, 0
    end
    if not text:find("[\128-\255]") then
        local n = #text
        return n, n
    end
    local codepoints = 0
    local codeunits = 0
    Utf8.each_codepoint(text, function(cp)
        codepoints = codepoints + 1
        if cp > 0xFFFF then
            codeunits = codeunits + 2
        else
            codeunits = codeunits + 1
        end
    end)
    return codepoints, codeunits
end

local function _notify_buf_lines(buf, payload)
    if not buf then
        return
    end
    local need_utf_sizes = BufAttach.has_utf_sizes_listener(buf.bufnr)
    local deleted_lines = payload.deleted_lines
    if deleted_lines ~= nil then
        if need_utf_sizes then
            local deleted_codepoints = 0
            local deleted_codeunits = 0
            for i = 1, #deleted_lines do
                local line_cp, line_cu = _text_sizes(deleted_lines[i])
                deleted_codepoints = deleted_codepoints + line_cp
                deleted_codeunits = deleted_codeunits + line_cu
                if i < #deleted_lines then
                    deleted_codepoints = deleted_codepoints + 1
                    deleted_codeunits = deleted_codeunits + 1
                end
            end
            payload.deleted_codepoints = payload.deleted_codepoints or deleted_codepoints
            payload.deleted_codeunits = payload.deleted_codeunits or deleted_codeunits
        end
        payload.deleted_lines = nil
    end
    local deleted_text = payload.deleted_text
    if deleted_text ~= nil then
        if need_utf_sizes then
            local text_cp, text_cu = _text_sizes(deleted_text)
            payload.deleted_codepoints = payload.deleted_codepoints or text_cp
            payload.deleted_codeunits = payload.deleted_codeunits or text_cu
        end
        payload.deleted_text = nil
    end
    BufAttach.notify_lines(buf.bufnr, payload)
end

local function _copy_lines(lines, start1, end1)
    local s = start1 or 1
    local e = end1 or #lines
    if e < s then
        return {}
    end
    local out = {}
    table.move(lines, s, e, 1, out)
    return out
end

local function _line_diff_bounds(before, after)
    local before_len = #before
    local after_len = #after
    local shared = math.min(before_len, after_len)

    local first = 1
    while first <= shared and before[first] == after[first] do
        first = first + 1
    end

    if first > before_len and first > after_len then
        return nil, nil, nil
    end

    local before_end = before_len
    local after_end = after_len
    while before_end >= first and after_end >= first and before[before_end] == after[after_end] do
        before_end = before_end - 1
        after_end = after_end - 1
    end

    return first, before_end, after_end
end

local function _undo_entry_after_lines(entry)
    if not entry.changed_start then
        return _copy_lines(entry.before_lines)
    end

    local start = entry.changed_start
    local before = entry.before_lines
    local out = {}

    local prefix_end = start - 1
    local dst = 1
    if prefix_end >= 1 then
        table.move(before, 1, prefix_end, dst, out)
        dst = dst + prefix_end
    end

    local after_chunk = entry.after_chunk
    local after_count = #after_chunk
    if after_count > 0 then
        table.move(after_chunk, 1, after_count, dst, out)
        dst = dst + after_count
    end

    local suffix_start = start + entry.before_count
    if suffix_start <= #before then
        table.move(before, suffix_start, #before, dst, out)
    end

    return out
end

local function _buffer_window(buf)
    local win = windows[curwin]
    if win.buffer == buf then
        return win
    end
    for _, candidate in pairs(windows) do
        if candidate.buffer == buf then
            return candidate
        end
    end
    return nil
end

local function _notify_full_replace(buf, old_lines, new_lines)
    local old_count = #old_lines
    local new_count = #new_lines
    local old_byte = _bytes_of_lines(old_lines)
    local new_byte = _bytes_of_lines(new_lines)
    _notify_buf_lines(buf, {
        firstline = 0,
        lastline = old_count,
        new_lastline = new_count,
        byte_count = old_byte,
        deleted_lines = old_lines,
        bytes = {
            start_row = 0,
            start_col = 0,
            start_byte = 0,
            old_end_row = (old_count > 0) and (old_count - 1) or 0,
            old_end_col = (old_count > 0) and #(old_lines[old_count] or "") or 0,
            old_end_byte = old_byte,
            new_end_row = (new_count > 0) and (new_count - 1) or 0,
            new_end_col = (new_count > 0) and #(new_lines[new_count] or "") or 0,
            new_end_byte = new_byte,
        },
    })
end

local function _undo_limit(buf)
    local levels = tonumber(options.get("undolevels", nil, buf))
    levels = math.floor(levels)
    if levels < 0 then
        return -1
    end
    if levels == 0 then
        return 1
    end
    return levels
end

---@class BufOpts
---@field buflisted boolean Whether the buffer shows up in bufer lists.
---@field modified boolean Whether the buffer has been modified

---@class Buffer
---@field state string The current buffer state: active, hidden, or inactive.
---@field bufnr number The unique buffer number.
---@field name  string The buffer name.
---@field swapname string The swapfile name.
---@field scratch boolean Whether the buffer is a scratch buffer.
---@field opts BufOpts The options for each buffer.
---@field lines string[] The raw lines of the file currently loaded into the buffer.
---@field loaded boolean Whether the buffer currently has file contents loaded.
---@field syntax_ctx table|nil Syntax engine context and caches for this buffer.
---@field refcount number The number of windows referencing this buffer.
---
---@field signs table[] The signs present on this buffer, indexed by group name -> id.
---@field signs_byln table[] The signs present on this buffer, indexed by line number.
---@field signs_nextid number[] The next sign ID for a given group name. "" for global.


--- Creates a new Buffer.
---@param listed boolean Whether to use the buffer in buffer lists.
---@param scratch boolean Whether the buffer is a scratch buffer, never saved.
---@param loaded boolean|nil Whether this buffer should start loaded.
function Buffer:new(listed, scratch, loaded)
    local is_loaded = (loaded ~= false)
    local obj = setmetatable({
        scratch = scratch or false,
        bufnr = curr_bufno,
        opts = {
            buflisted = listed or false,
            modified  = false
        },
        state = "hidden",
        lines = is_loaded and { "" } or {},
        loaded = is_loaded,
        refcount = 0,
        signs = {},
        signs_byln = {},
        signs_nextid = { [""] = 1 },
        marks = {},
        _undo = {
            entries = {},
            index = 0,
            pending = nil,
            depth = 0,
            restoring = false,
            seq = 0,
            last_changed_line = nil,
            line_undo_anchor = {},
        },
    }, Buffer)

    buffers[curr_bufno] = obj
    BufAttach.ensure_buffer(obj.bufnr)

    curr_bufno = curr_bufno + 1

    return obj
end

function Buffer:Load(read_contents)
    local was_loaded = self.loaded == true
    self.syntax_ctx = nil
    self.loaded = true

    if read_contents then
        local name = self.name or ""
        local ctx = { bufnr = self.bufnr, bufname = name }

        LOG_DEBUG("Buffer.Load bufnr=%d name=%s", self.bufnr, tostring(name))

        local did_cmd = false
        if name ~= "" then
            local matched = AutoCmd.Run("BufReadCmd", ctx)
            if matched and matched > 0 then
                LOG_DEBUG("BufReadCmd matched bufnr=%d name=%s", self.bufnr, tostring(name))
                did_cmd = true
            end
        end

        if not did_cmd then
            local resolved = VimFs.abspath(name)
            if name ~= "" and fs.exists(resolved) then
                LOG_DEBUG("BufRead path=%s bufnr=%d", tostring(resolved), self.bufnr)
                AutoCmd.Run("BufReadPre", ctx)
                local h = fs.open(resolved, "r")
                if h then
                    local s = h.readAll() or ""
                    h.close()
                    self.lines = {}
                    local i = 1
                    for l in (s .. "\n"):gmatch("([^\r\n]*)\r?\n") do
                        self.lines[i] = l
                        i = i + 1
                    end
                else
                    -- Treat unreadable entries (e.g., directories) as empty but continue.
                    LOG_DEBUG("BufRead open failed (dir=%s) path=%s", tostring(fs.isDir(resolved)), tostring(resolved))
                    self.lines = { "" }
                end
                if fs.isReadOnly(resolved) then
                    self.opts.readonly = true
                end
                AutoCmd.Run("BufRead", ctx)
                AutoCmd.Run("BufReadPost", ctx)
            else
                LOG_DEBUG("BufNewFile bufnr=%d name=%s", self.bufnr, tostring(name))
                self.lines = { "" }
                AutoCmd.Run("BufNewFile", ctx)
            end
        end

        if was_loaded then
            BufAttach.notify_reload(self.bufnr)
        end
    end

    self:undo_clear()
end

function Buffer:is_loaded()
    return self.loaded == true
end

function Buffer:ensure_loaded(read_contents)
    if self:is_loaded() then
        return true
    end
    self:Load(read_contents ~= false)
    return self:is_loaded()
end

function Buffer:line_count(load_if_unloaded)
    if load_if_unloaded then
        self:ensure_loaded(true)
    end
    if not self:is_loaded() then
        return 0
    end
    return #self.lines
end

function Buffer:lines_ref(load_if_unloaded)
    if load_if_unloaded then
        self:ensure_loaded(true)
    end
    return self.lines
end

function Buffer:get_line(line_nr, load_if_unloaded)
    local lines = self:lines_ref(load_if_unloaded)
    return lines[line_nr]
end

function Buffer:str_len(s)
    return Utf8.len(s or "")
end

function Buffer:str_sub(s, start_col1, end_col1)
    return Utf8.sub(s or "", start_col1, end_col1)
end

function Buffer:str_char_at(s, col1)
    return Utf8.char_at(s or "", col1)
end

function Buffer:str_codepoint_at(s, col1)
    return Utf8.codepoint_at(s or "", col1)
end

function Buffer:str_byte_index(s, col1, allow_eol)
    return Utf8.byte_index(s or "", col1, allow_eol)
end

function Buffer:str_col_from_byte(s, byte_idx, allow_eol)
    return Utf8.col_from_byte(s or "", byte_idx, allow_eol)
end

function Buffer:str_each_codepoint(s, visitor)
    return Utf8.each_codepoint(s or "", visitor)
end

function Buffer:_ensure_undo_state()
    self._undo = self._undo or {
        entries = {},
        index = 0,
        pending = nil,
        depth = 0,
        restoring = false,
        seq = 0,
        last_changed_line = nil,
        line_undo_anchor = {},
    }
    return self._undo
end

function Buffer:undo_clear()
    local st = self:_ensure_undo_state()
    st.entries = {}
    st.index = 0
    st.pending = nil
    st.depth = 0
    st.seq = 0
    st.last_changed_line = nil
    st.line_undo_anchor = {}
    st.join_next = nil
    st.after_undo = nil
end

function Buffer:undo_begin(win)
    local st = self:_ensure_undo_state()
    if st.restoring then
        return
    end

    st.depth = st.depth + 1
    if st.depth > 1 then
        return
    end

    local limit = _undo_limit(self)
    if limit < 0 then
        st.entries = {}
        st.index = 0
        st.pending = nil
        st.last_changed_line = nil
        st.line_undo_anchor = {}
        return
    end

    local target_win = win or _buffer_window(self)
    local before_cursor = nil
    if target_win then
        before_cursor = { target_win.cursorx, target_win.cursory }
    end

    st.pending = {
        before_lines = _copy_lines(self.lines),
        before_modified = self.opts.modified == true,
        before_cursor = before_cursor,
        changed = false,
    }
end

function Buffer:undo_mark_changed()
    local st = self:_ensure_undo_state()
    if st.restoring then
        return
    end
    if st.pending then
        st.pending.changed = true
    end
end

function Buffer:undo_break_line_chain()
    local st = self:_ensure_undo_state()
    st.last_changed_line = nil
end

function Buffer:_undo_note_single_line_change(line_nr, old_line)
    local st = self:_ensure_undo_state()
    if st.restoring then
        return
    end
    local ln = math.max(1, math.floor(tonumber(line_nr) or 1))
    if st.last_changed_line ~= ln then
        st.line_undo_anchor[ln] = tostring(old_line or "")
    end
    st.last_changed_line = ln
end

function Buffer:undo_end(win)
    local st = self:_ensure_undo_state()
    if st.restoring then
        return
    end
    if st.depth == 0 then
        return
    end

    st.depth = st.depth - 1
    if st.depth > 0 then
        return
    end

    local pending = st.pending
    st.pending = nil
    if not pending or not pending.changed then
        return
    end

    local before_lines = pending.before_lines
    local after_modified = self.opts.modified == true
    local changed_start, before_end, after_end = _line_diff_bounds(before_lines, self.lines)
    if not changed_start and pending.before_modified == after_modified then
        return
    end

    for i = #st.entries, st.index + 1, -1 do
        st.entries[i] = nil
    end

    local target_win = win or _buffer_window(self)
    local after_cursor = nil
    if target_win then
        after_cursor = { target_win.cursorx, target_win.cursory }
    end

    if st.join_next and st.index > 0 then
        st.join_next = nil
        st.after_undo = nil
        local prev = st.entries[st.index]
        local jstart, jbefore_end, jafter_end = _line_diff_bounds(prev.before_lines, self.lines)
        prev.after_modified = after_modified
        prev.after_cursor = after_cursor
        prev.changed_start = jstart
        prev.changed_end = jstart and math.max(jbefore_end, jafter_end)
        if jstart then
            prev.before_count = jbefore_end - jstart + 1
            prev.after_chunk = _copy_lines(self.lines, jstart, jafter_end)
        else
            prev.before_count = 0
            prev.after_chunk = {}
        end
        return
    end

    st.join_next = nil
    st.after_undo = nil
    st.seq = st.seq + 1
    st.index = st.index + 1
    local entry = {
        id = st.seq,
        before_lines = before_lines,
        before_modified = pending.before_modified,
        after_modified = after_modified,
        before_cursor = pending.before_cursor,
        after_cursor = after_cursor,
        changed_start = changed_start,
        changed_end = changed_start and math.max(before_end, after_end) or nil,
    }
    if changed_start then
        entry.before_count = before_end - changed_start + 1
        entry.after_chunk = _copy_lines(self.lines, changed_start, after_end)
    else
        entry.before_count = 0
        entry.after_chunk = {}
    end
    st.entries[st.index] = entry

    local limit = _undo_limit(self)
    if limit < 0 then
        st.entries = {}
        st.index = 0
        return
    end
    while #st.entries > limit do
        table.remove(st.entries, 1)
        st.index = st.index - 1
    end
    if st.index < 0 then
        st.index = 0
    end
end

function Buffer:undojoin()
    local st = self:_ensure_undo_state()
    if st.after_undo then
        return false
    end
    st.join_next = true
    return true
end

function Buffer:_undo_apply(lines, modified, cursor, win, noauto)
    local old_lines = _copy_lines(self.lines)
    self.lines = _copy_lines(lines)
    if #self.lines == 0 then
        self.lines = { "" }
    end
    self.opts.modified = modified == true

    Sign = Sign or loadModule("lib.sign")
    Sign.on_lines_changed(self, 1, #old_lines, #self.lines)

    _notify_full_replace(self, old_lines, self.lines)
    Syntax.ParseLinetypes(self, 1)
    _request_full_redraw()
    _run_textchanged(self, noauto)

    local target_win = win or _buffer_window(self)
    if target_win and cursor then
        local new_y = math.max(1, math.min(cursor[2], #self.lines))
        local max_x = self:str_len(self.lines[new_y] or "") + 1
        local new_x = math.max(1, math.min(cursor[1], max_x))
        if type(target_win.cursorSet) == "function" then
            target_win:cursorSet(new_x, new_y)
        else
            target_win.cursorx = new_x
            target_win.cursory = new_y
        end
    end

    for _, candidate in pairs(windows) do
        if candidate.buffer == self then
            candidate.need_redraw = true
        end
    end
    what_redraw["windows"] = true
    need_redraw = true
end

function Buffer:_undo_jump_to(target, win, noauto)
    local st = self:_ensure_undo_state()
    if target < 0 or target > #st.entries then
        return false
    end
    if target == st.index then
        return true
    end

    local entry
    local lines
    local modified
    local cursor

    if target < st.index then
        entry = st.entries[target + 1]
        lines = entry.before_lines
        modified = entry.before_modified
        cursor = entry.before_cursor
    else
        entry = st.entries[target]
        lines = _undo_entry_after_lines(entry)
        modified = entry.after_modified
        cursor = entry.after_cursor
    end

    st.restoring = true
    local ok, err = pcall(self._undo_apply, self, lines, modified, cursor, win, noauto)
    st.restoring = false
    if not ok then
        error(err)
    end

    st.index = target
    st.last_changed_line = nil
    st.line_undo_anchor = {}
    st.after_undo = true
    return true
end

function Buffer:undo_change(win, change_id, noauto)
    local st = self:_ensure_undo_state()
    local target_id = math.floor(tonumber(change_id) or -1)
    if target_id < 0 then
        return false
    end
    if target_id == 0 then
        return self:_undo_jump_to(0, win, noauto)
    end

    local target = nil
    for i = 1, #st.entries do
        if st.entries[i].id == target_id then
            target = i
            break
        end
    end
    if target == nil then
        return false
    end
    return self:_undo_jump_to(target, win, noauto)
end

function Buffer:undo(win, count, noauto)
    local st = self:_ensure_undo_state()
    if st.index == 0 then
        return false
    end

    local steps = math.max(1, math.floor(tonumber(count) or 1))
    if steps > st.index then
        steps = st.index
    end
    local target = st.index - steps
    return self:_undo_jump_to(target, win, noauto)
end

function Buffer:redo(win, count, noauto)
    local st = self:_ensure_undo_state()
    if st.index >= #st.entries then
        return false
    end

    local steps = math.max(1, math.floor(tonumber(count) or 1))
    local max_forward = #st.entries - st.index
    if steps > max_forward then
        steps = max_forward
    end
    local target = st.index + steps
    return self:_undo_jump_to(target, win, noauto)
end

function Buffer:undo_line(win, noauto)
    local st = self:_ensure_undo_state()
    local target_win = win or _buffer_window(self)
    local line_count = #self.lines
    if line_count < 1 then
        return false
    end

    local target_line = st.last_changed_line
    if not target_line or target_line < 1 or target_line > line_count then
        target_line = target_win and target_win.cursory or 1
    end
    if target_line < 1 then
        target_line = 1
    elseif target_line > line_count then
        target_line = line_count
    end

    local target_text = st.line_undo_anchor[target_line]
    local at_tip = (st.index > 0 and st.index == #st.entries)
    if at_tip and target_text ~= nil then
        local old_line = self.lines[target_line] or ""
        local new_line = tostring(target_text)
        local start_byte = _bytes_before_row(self.lines, target_line - 1)

        self.lines[target_line] = new_line
        self.opts.modified = true

        if target_win then
            if type(target_win.cursorSet) == "function" then
                target_win:cursorSet(1, target_line)
            else
                target_win.cursorx = 1
                target_win.cursory = target_line
            end
        end

        _notify_buf_lines(self, {
            firstline = target_line - 1,
            lastline = target_line,
            new_lastline = target_line,
            byte_count = #old_line,
            deleted_text = old_line,
            bytes = {
                start_row = target_line - 1,
                start_col = 0,
                start_byte = start_byte,
                old_end_row = 0,
                old_end_col = #old_line,
                old_end_byte = #old_line,
                new_end_row = 0,
                new_end_col = #new_line,
                new_end_byte = #new_line,
            },
        })
        _run_textchanged(self, noauto)

        local entry = st.entries[st.index]
        entry.after_modified = true
        if target_win then
            entry.after_cursor = { target_win.cursorx, target_win.cursory }
        end
        local changed_start, before_end, after_end = _line_diff_bounds(entry.before_lines, self.lines)
        entry.changed_start = changed_start
        entry.changed_end = changed_start and math.max(before_end, after_end) or nil
        if changed_start then
            entry.before_count = before_end - changed_start + 1
            entry.after_chunk = _copy_lines(self.lines, changed_start, after_end)
        else
            entry.before_count = 0
            entry.after_chunk = {}
        end

        st.last_changed_line = target_line
        st.line_undo_anchor[target_line] = new_line
        return true
    end

    local replacement = target_text
    if replacement == nil then
        replacement = self.lines[target_line] or ""
    end

    self:undo_begin(target_win)
    self:set_line(target_line, replacement, true, noauto)
    self:undo_mark_changed()
    self.opts.modified = true
    if target_win then
        if type(target_win.cursorSet) == "function" then
            target_win:cursorSet(1, target_line)
        else
            target_win.cursorx = 1
            target_win.cursory = target_line
        end
    end
    self:undo_end(target_win)

    return true
end

function Buffer:line_len(line_nr, load_if_unloaded)
    local line = self:get_line(line_nr, load_if_unloaded) or ""
    return Utf8.len(line)
end

function Buffer:line_sub(line_nr, start_col1, end_col1, load_if_unloaded)
    local line = self:get_line(line_nr, load_if_unloaded) or ""
    return Utf8.sub(line, start_col1, end_col1)
end

function Buffer:line_char_at(line_nr, col1, load_if_unloaded)
    local line = self:get_line(line_nr, load_if_unloaded) or ""
    return Utf8.char_at(line, col1)
end

function Buffer:line_codepoint_at(line_nr, col1, load_if_unloaded)
    local line = self:get_line(line_nr, load_if_unloaded) or ""
    return Utf8.codepoint_at(line, col1)
end

function Buffer:line_byte_index(line_nr, col1, load_if_unloaded, allow_eol)
    local line = self:get_line(line_nr, load_if_unloaded) or ""
    return Utf8.byte_index(line, col1, allow_eol)
end

function Buffer:line_col_from_byte(line_nr, byte_idx, load_if_unloaded, allow_eol)
    local line = self:get_line(line_nr, load_if_unloaded) or ""
    return Utf8.col_from_byte(line, byte_idx, allow_eol)
end

function Buffer:set_line(line_nr, text, load_if_unloaded, noauto)
    local lines = self:lines_ref(load_if_unloaded)
    self:undo_begin()
    local ln = math.max(1, math.floor(tonumber(line_nr) or 1))
    local old_line = lines[ln] or ""
    self:_undo_note_single_line_change(ln, old_line)
    local start_byte = _bytes_before_row(lines, ln - 1)
    local new_line = tostring(text or "")
    lines[ln] = new_line
    self:undo_mark_changed()
    self.opts.modified = true
    _notify_buf_lines(self, {
        firstline = ln - 1,
        lastline = ln,
        new_lastline = ln,
        byte_count = #old_line,
        deleted_text = old_line,
        bytes = {
            start_row = ln - 1,
            start_col = 0,
            start_byte = start_byte,
            old_end_row = 0,
            old_end_col = #old_line,
            old_end_byte = #old_line,
            new_end_row = 0,
            new_end_col = #new_line,
            new_end_byte = #new_line,
        },
    })
    _run_textchanged(self, noauto)
    self:undo_end()
end

function Buffer:insert_line(index, item, load_if_unloaded, noauto)
    local lines = self:lines_ref(load_if_unloaded)
    self:undo_begin()
    self:undo_break_line_chain()
    local idx = math.max(1, math.floor(tonumber(index) or (#lines + 1)))
    local new_line = tostring(item or "")
    local start_byte = _bytes_before_row(lines, idx - 1)
    table.insert(lines, idx, new_line)
    self:undo_mark_changed()
    self.opts.modified = true
    _notify_buf_lines(self, {
        firstline = idx - 1,
        lastline = idx - 1,
        new_lastline = idx,
        byte_count = 0,
        deleted_text = "",
        bytes = {
            start_row = idx - 1,
            start_col = 0,
            start_byte = start_byte,
            old_end_row = 0,
            old_end_col = 0,
            old_end_byte = 0,
            new_end_row = 0,
            new_end_col = #new_line,
            new_end_byte = #new_line,
        },
    })
    _run_textchanged(self, noauto)
    self:undo_end()
end

function Buffer:splice_line(line_nr, start_col1, end_col1, replacement, load_if_unloaded)
    local line = self:get_line(line_nr, load_if_unloaded) or ""
    local s = math.max(1, math.floor(tonumber(start_col1) or 1))
    local e = math.floor(tonumber(end_col1) or (s - 1))
    local prefix = Utf8.sub(line, 1, s - 1)
    local removed = (e >= s) and Utf8.sub(line, s, e) or ""
    local suffix = Utf8.sub(line, math.max(s, e + 1))
    local new_line = prefix .. tostring(replacement or "") .. suffix
    self:set_line(line_nr, new_line, load_if_unloaded)
    return new_line, removed
end

function Buffer:remove_lines(start1, end1, opts, noauto)
    opts = opts or {}
    self.loaded = true

    local line_count = #self.lines

    local s = start1 or 1
    local e = end1 or s

    if s < 1 then s = 1 end
    if e > line_count then e = line_count end

    if e < 1 or s > line_count or s > e then
        return {}
    end

    self:undo_begin()
    self:undo_break_line_chain()
    local was_empty = (line_count == 1 and self.lines[1] == "")
    local start_byte = _bytes_before_row(self.lines, s - 1)

    local removed = {}
    for i = s, e do
        removed[#removed + 1] = self.lines[i]
    end

    local k_remove = e - s + 1
    for _ = 1, k_remove do
        table.remove(self.lines, s)
    end
    self:undo_mark_changed()

    if #self.lines == 0 then
        if not was_empty and not opts.silent_no_lines then
            ExMsg.echo("--No lines in buffer--")
        end
    end

    if not opts.skip_sign_adjust then
        Sign = Sign or loadModule("lib.sign")
        Sign.on_lines_changed(self, s, k_remove, 0)
    end

    self.opts.modified = true
    Syntax.ParseLinetypes(self, math.max(1, s - 1))
    _request_full_redraw()

    if not opts.skip_buf_attach_notify then
        local old_byte = _bytes_of_lines(removed)
        _notify_buf_lines(self, {
            firstline = s - 1,
            lastline = e,
            new_lastline = s - 1,
            byte_count = old_byte,
            deleted_text = table.concat(removed, "\n"),
            bytes = {
                start_row = s - 1,
                start_col = 0,
                start_byte = start_byte,
                old_end_row = (#removed > 0) and (#removed - 1) or 0,
                old_end_col = (#removed > 0) and #(removed[#removed] or "") or 0,
                old_end_byte = old_byte,
                new_end_row = 0,
                new_end_col = 0,
                new_end_byte = 0,
            },
        })
    end
    
    _run_textchanged(self, noauto)
    self:undo_end()

    return removed
end

function Buffer:set_lines(start0, stop0, strict_indexing, replacement)
    self.loaded = true
    local line_count = #self.lines

    -- Normalize negatives relative to end+1, remaining 0-based for now
    local s = start0 >= 0 and start0 or (line_count + 1 + start0)
    local e = stop0 >= 0 and stop0 or (line_count + 1 + stop0)

    -- Handle strict vs clamp, start/end relation
    if strict_indexing then
        if s < 0 or s > line_count or e < 0 or e > line_count then
            error(("nvim_buf_set_lines: index out of bounds (s=%d,e=%d,count=%d)")
                :format(s, e, line_count))
        end
        if s > e then
            error(("nvim_buf_set_lines: start > end (s=%d,e=%d) with strict_indexing")
                :format(s, e))
        end
    else
        s = math.max(0, math.min(s, line_count))
        e = math.max(0, math.min(e, line_count))
        if s > e then
            s = e
        end
    end

    self:undo_begin()
    self:undo_break_line_chain()
    -- Convert to Lua 1-based for table ops
    local start1 = s + 1
    local k_remove = e - s        -- how many to remove
    local m_insert = #replacement -- how many to insert
    local removed_lines = (k_remove > 0) and _slice_lines(self.lines, start1, start1 + k_remove - 1) or {}
    local inserted_lines = {}
    for i = 1, m_insert do
        inserted_lines[i] = tostring(replacement[i] or "")
    end
    local start_byte = _bytes_before_row(self.lines, s)

    -- 1) Delete k_remove lines from self.lines at start1
    if k_remove > 0 then
        self:remove_lines(start1, start1 + k_remove - 1, {
            allow_empty = true,
            silent_no_lines = true,
            skip_sign_adjust = true,
            skip_buf_attach_notify = true,
        }, true)
    end

    -- 2) Insert m_insert replacement lines at start1
    if m_insert > 0 then
        for i = 1, m_insert do
            table.insert(self.lines, start1 + i - 1, inserted_lines[i])
        end
        self:undo_mark_changed()
    end
    if k_remove > 0 then
        self:undo_mark_changed()
    end

    -- 3) Ensure buffer has at least one (possibly empty) line
    if #self.lines == 0 then
        self.lines = { "" }
    end

    if k_remove > 0 or m_insert > 0 then
        Sign = Sign or loadModule("lib.sign")
        Sign.on_lines_changed(self, start1, k_remove, m_insert)
    end
    
    -- Mark modified (like altering buffer contents)
    self.opts.modified = true

    if k_remove > 0 or m_insert > 0 then
        local old_byte = _bytes_of_lines(removed_lines)
        local new_byte = _bytes_of_lines(inserted_lines)
        _notify_buf_lines(self, {
            firstline = s,
            lastline = e,
            new_lastline = s + m_insert,
            byte_count = old_byte,
            deleted_text = table.concat(removed_lines, "\n"),
            bytes = {
                start_row = s,
                start_col = 0,
                start_byte = start_byte,
                old_end_row = (#removed_lines > 0) and (#removed_lines - 1) or 0,
                old_end_col = (#removed_lines > 0) and #(removed_lines[#removed_lines] or "") or 0,
                old_end_byte = old_byte,
                new_end_row = (#inserted_lines > 0) and (#inserted_lines - 1) or 0,
                new_end_col = (#inserted_lines > 0) and #(inserted_lines[#inserted_lines] or "") or 0,
                new_end_byte = new_byte,
            },
        })
    end

    _run_textchanged(self, false)
    Syntax.ParseLinetypes(self, math.max(1, start1 - 1))
    _request_full_redraw()
    self:undo_end()
end

local function _autowrite_enabled(kind)
    if kind == "autowrite" then
        return options.get("autowrite") or options.get("autowriteall")
    elseif kind == "autowriteall" then
        return options.get("autowriteall")
    end
    return false
end

local function _autowrite_blocked_buftype(buf)
    local bt = options.get("buftype", nil, buf)
    return bt == "nowrite" or bt == "nofile" or bt == "terminal" or bt == "prompt"
end

function Buffer:leave(forceabandon, mustabandon, autowrite_kind)
    local bufhidden = options.get("bufhidden", nil, self)
    local hidden = options.get("hidden")

    if
        not forceabandon
        and self.opts.modified
        and _autowrite_enabled(autowrite_kind)
        and not _autowrite_blocked_buftype(self)
    then
        local status = self:write(false)
        if status ~= true then
            return status
        end
    end

    if bufhidden ~= "" then
        -- If bufhidden is "hidden", then this is ignored
        if bufhidden == "unload" then
            -- Approximate unload semantics: keep the buffer object, but drop
            -- transient parse context and clear loaded contents.
            self.syntax_ctx = nil
            self.lines = {}
            self.loaded = false
            BufAttach.detach(self.bufnr)
        elseif bufhidden == "delete" then
            -- Behave like :bdelete when last window reference is gone.
            self.opts.buflisted = false
            if self.refcount <= 1 then
                BufAttach.detach(self.bufnr)
                buffers[self.bufnr] = nil
            end
        elseif bufhidden == "wipe" then
            if self.refcount <= 1 then
                BufAttach.detach(self.bufnr)
                buffers[self.bufnr] = nil
            end
        else
            error("Unhandled: bufhidden = " .. bufhidden)
        end
    else
        local check = (not hidden and self.refcount <= 1) or mustabandon
        if check and self.opts.modified and not forceabandon then
            return Error(37)
        end
    end

    self.refcount = self.refcount - 1
    return true
end

-- TODO: several options affect write, such as line endings via fileformat
function Buffer:write(force, newname)
    if not options.get("write") then
        return Error(142)
    end

    local name
    if newname and newname ~= "" then
        name = newname
        self.name = newname
    else
        name = self.name
    end

    if not name or name == "" then
        return Error(32)
    end

    local buftype = options.get("buftype", nil, self)
    if buftype ~= "" then
        if buftype == "acwrite" then
            local matched = AutoCmd.Run("BufWriteCmd", {
                bufnr = self.bufnr,
                bufname = name,
            }) or 0
            if matched == 0 then
                return Error(676)
            end
            self.opts.modified = false
            return true
        end
        return Error(382)
    end

    if options.get("readonly", nil, self) and not force then
        return Error(45)
    end

    local path = VimFs.abspath(name)
    local f = fs.open(path, "w")
    if not f then
        return Error(212, name)
    end

    local writesz = 0
    for i = 1, #self.lines - 1 do
        f.write(self.lines[i] .. "\n")
        writesz = writesz + #self.lines[i] + 1
    end
    f.write(self.lines[#self.lines])
    writesz = writesz + #self.lines[#self.lines]

    f.close()

    self.opts.modified = false

    ExMsg.echo("\"" .. self.name .. "\" " .. #self.lines .. "L, " .. writesz .. "B")

    return true
end

setmetatable(Buffer, { __call = function(self, ...) return self:new(...) end })


return Buffer
