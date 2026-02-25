local Buffer = {}
Buffer.__index = Buffer -- Share the instance methods

local Error = loadModule("lib.error")
local ExMsg = loadModule("lib.excmd.exmsg")
local AutoCmd = loadModule("lib.autocmd")
local VimFs = loadModule("lib.luaapi.fs")
local Syntax = loadModule("lib.syntax")
local Utf8 = loadModule("lib.utf8")
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
    }, Buffer)

    buffers[curr_bufno] = obj

    curr_bufno = curr_bufno + 1

    return obj
end

function Buffer:Load(read_contents)
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
    end
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
    lines[line_nr] = tostring(text or "")
    self.opts.modified = true
    _run_textchanged(self, noauto)
end

function Buffer:insert_line(index, item, load_if_unloaded, noauto)
    local lines = self:lines_ref(load_if_unloaded)
    table.insert(lines, index, item)
    self.opts.modified = true
    _run_textchanged(self, noauto)
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

    local was_empty = (line_count == 1 and self.lines[1] == "")

    local removed = {}
    for i = s, e do
        removed[#removed + 1] = self.lines[i]
    end

    local k_remove = e - s + 1
    for _ = 1, k_remove do
        table.remove(self.lines, s)
    end

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
    
    _run_textchanged(self, noauto)

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

    -- Convert to Lua 1-based for table ops
    local start1 = s + 1
    local k_remove = e - s        -- how many to remove
    local m_insert = #replacement -- how many to insert

    -- 1) Delete k_remove lines from self.lines at start1
    if k_remove > 0 then
        self:remove_lines(start1, start1 + k_remove - 1, {
            allow_empty = true,
            silent_no_lines = true,
            skip_sign_adjust = true,
        }, true)
    end

    -- 2) Insert m_insert replacement lines at start1
    if m_insert > 0 then
        for i = 1, m_insert do
            table.insert(self.lines, start1 + i - 1, replacement[i])
        end
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
    _run_textchanged(self, false)
    Syntax.ParseLinetypes(self, math.max(1, start1 - 1))
    _request_full_redraw()
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

    if not forceabandon and self.opts.modified and _autowrite_enabled(autowrite_kind) and not _autowrite_blocked_buftype(self) then
        local status = self:write(false)
        if status ~= true then
            return status
        end
    end

    if bufhidden ~= "" then
        if bufhidden == "hide" then
            -- Keep buffer loaded and listed regardless of global 'hidden'.
        elseif bufhidden == "unload" then
            -- Approximate unload semantics: keep the buffer object, but drop
            -- transient parse context and clear loaded contents.
            self.syntax_ctx = nil
            self.lines = {}
            self.loaded = false
        elseif bufhidden == "delete" then
            -- Behave like :bdelete when last window reference is gone.
            self.opts.buflisted = false
            if self.refcount <= 1 then
                buffers[self.bufnr] = nil
            end
        elseif bufhidden == "wipe" then
            if self.refcount <= 1 then
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
