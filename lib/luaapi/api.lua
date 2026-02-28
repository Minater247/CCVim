local api = {}

local VimXpr = loadModule("lib.excmd.vimxpr")
local Buffer = loadModule("layout.buffer")
local Window = loadModule("layout.window")
local Command = loadModule("lib.command")
local Key = loadModule("lib.key")
local Highlight = loadModule("lib.highlight")
local ExMsg = loadModule("lib.excmd.exmsg")
local Runtime = loadModule("lib.excmd.runtime")
local scopes = loadModule("lib.luaapi.scopes")
local AutoCmd = loadModule("lib.autocmd")
local Fn = loadModule("lib.luaapi.fn")
local Decoration = loadModule("lib.decoration")
local ScriptSource
local Error = loadModule("lib.error")
local Utf8 = loadModule("lib.utf8")
local PopupMenu = loadModule("lib.popupmenu")
local Event = loadModule("lib.event")
local BufAttach = loadModule("lib.bufattach")

-- Basic color name lookup for `nvim_set_hl`/`nvim_get_color_by_name`.
-- Uses the terminal palette so aliases match the active colors.
local COLOR_ALIASES = {
    black = colors.black,
    red = colors.red,
    green = colors.green,
    blue = colors.blue,
    yellow = colors.yellow,
    orange = colors.orange,
    brown = colors.brown,
    magenta = colors.magenta,
    purple = colors.purple,
    cyan = colors.cyan,
    white = colors.white,
    gray = colors.gray,
    grey = colors.gray,
    darkgray = colors.gray,
    darkgrey = colors.gray,
    lightgray = colors.lightGray,
    lightgrey = colors.lightGray,
    lightblue = colors.lightBlue,
    lightgreen = colors.lime,
    lime = colors.lime,
    pink = colors.pink,
}

local function rgb_for_palette_index(idx)
    local r, g, b = term.getPaletteColor(idx)
    return colors.packRGB(r, g, b)
end

local function api_color_value(raw_value, palette_value)
    if raw_value ~= nil then
        return raw_value
    end
    if palette_value ~= nil then
        return rgb_for_palette_index(palette_value)
    end
    return nil
end

local function normalize_color_value(val)
    if val == nil or val == "fg" or val == "bg" then
        return val
    end
    if type(val) == "number" then
        -- Preserve numeric values as-is (palette indices and RGB numbers).
        return val
    end
    if type(val) == "string" then
        local hex = val:match("^#(%x%x%x%x%x%x)$")
        if hex then return tonumber("0x" .. hex) end

        local alias = COLOR_ALIASES[string.lower(val)]
        if alias then
            return alias
        end
    end
    return nil
end

-- TODO: MOVE THESE FUNCTIONS TO USE EXPECT_ARGS

-- ========================
-- General Helper Functions
-- ========================
local function expect_args(args, count)
    if #args ~= count then
        error("Expected " .. count .. (count == 1 and " argument" or " arguments"))
    end
    return table.unpack(args)
end

local function win_for_id(winid)
    return (winid ~= 0) and (windows[winid] or error("Invalid window id: " .. winid)) or (windows[curwin])
end

local function buf_for_bufnr(bufid)
    if bufid == 0 then
        return windows[curwin].buffer
    else
        return buffers[bufid]
    end
end

local function request_buffer_redraw(buf, full)
    if not buf then
        return
    end
    local has_attached_window = false
    for _, win in pairs(windows) do
        if win.buffer == buf then
            win.need_redraw = true
            has_attached_window = true
        end
    end
    if full then
        what_redraw["all"] = true
    elseif not has_attached_window then
        what_redraw["windows"] = true
    end
    need_redraw = true
end

local keymap_store = {
    global = {},
    buffer = {},
}

local function keymap_mode_key(mode)
    return tostring(mode or "")
end

local function keymap_bucket(is_buffer, bufnr, mode, create)
    local mode_key = keymap_mode_key(mode)
    if is_buffer then
        local by_buf = keymap_store.buffer
        local per_buf = by_buf[bufnr]
        if not per_buf and create then
            per_buf = {}
            by_buf[bufnr] = per_buf
        end
        if not per_buf then
            return nil
        end
        local bucket = per_buf[mode_key]
        if not bucket and create then
            bucket = { list = {}, by_lhs = {} }
            per_buf[mode_key] = bucket
        end
        return bucket
    end

    local per_mode = keymap_store.global
    local bucket = per_mode[mode_key]
    if not bucket and create then
        bucket = { list = {}, by_lhs = {} }
        per_mode[mode_key] = bucket
    end
    return bucket
end

local function keymap_bool_flag(opts, name, default)
    local v = opts and opts[name]
    if v == nil then
        return default and 1 or 0
    end
    return (v == true or v == 1) and 1 or 0
end

local function record_keymap(is_buffer, bufnr, mode, lhs, rhs, opts)
    opts = opts or {}
    lhs = tostring(lhs or "")
    rhs = tostring(rhs or "")

    local bucket = keymap_bucket(is_buffer, bufnr, mode, true)
    local idx = bucket.by_lhs[lhs]
    local entry = {
        lhs = lhs,
        rhs = rhs,
        mode = keymap_mode_key(mode),
        expr = keymap_bool_flag(opts, "expr", false),
        noremap = keymap_bool_flag(opts, "noremap", false),
        script = keymap_bool_flag(opts, "script", false),
        silent = keymap_bool_flag(opts, "silent", false),
        nowait = keymap_bool_flag(opts, "nowait", false),
        replace_keycodes = keymap_bool_flag(opts, "replace_keycodes", true),
        callback = opts.callback,
        desc = opts.desc,
    }

    if idx then
        bucket.list[idx] = entry
    else
        bucket.list[#bucket.list + 1] = entry
        bucket.by_lhs[lhs] = #bucket.list
    end
end

local function delete_keymap_record(is_buffer, bufnr, mode, lhs)
    local bucket = keymap_bucket(is_buffer, bufnr, mode, false)
    if not bucket then
        return
    end

    lhs = tostring(lhs or "")
    local idx = bucket.by_lhs[lhs]
    if not idx then
        return
    end

    table.remove(bucket.list, idx)
    bucket.by_lhs = {}
    for i = 1, #bucket.list do
        local item = bucket.list[i]
        bucket.by_lhs[item.lhs] = i
    end
end

local function list_keymaps(is_buffer, bufnr, mode)
    local bucket = keymap_bucket(is_buffer, bufnr, mode, false)
    if not bucket then
        return {}
    end

    local out = {}
    for i = 1, #bucket.list do
        local item = bucket.list[i]
        local copy = {}
        for k, v in pairs(item) do
            copy[k] = v
        end
        out[#out + 1] = copy
    end
    return out
end

local feedkeys_queue = {}
local feedkeys_flush_timer = nil
local feedkeys_flushing = false

local NVIM_CMD_MARKER = string.char(128, 253, 104)

local function _run_feedkeys_cmdline(cmdline)
    local state = {
        g = scopes._g,
        s = {},
        v = scopes._v,
        funcs = Runtime._FUNCS,
    }

    local ok, err = Runtime.run(tostring(cmdline or ""), {
        state = state,
        origin = {
            kind = "feedkeys-cmd",
        },
    })
    if not ok and err and err.toString then
        ExMsg.echoerr(err:toString())
    elseif not ok then
        ExMsg.echoerr(tostring(err))
    end
    ExMsg.Finalize()
end

local function _parse_feedkeys_ops(text)
    local ops = {}
    local n = #text
    local i = 1
    local normal_start = 1

    local function push_keys_segment(start_i, stop_i)
        if stop_i < start_i then
            return
        end
        local seq = Key.strtoseq(text:sub(start_i, stop_i))
        if #seq > 0 then
            ops[#ops + 1] = { kind = "keys", seq = seq }
        end
    end

    local function marker_len_at(idx)
        local b1, b2, b3 = string.byte(text, idx, idx + 2)
        if b1 == 128 and b2 == 253 and b3 == 104 then
            return #NVIM_CMD_MARKER
        end
        if idx + 4 <= n then
            local s = text:sub(idx, idx + 4)
            if s:lower() == "<cmd>" then
                return 5
            end
        end
        return nil
    end

    local function cmd_terminator_len_at(idx)
        local b = string.byte(text, idx)
        if b == 13 or b == 10 then
            return 1
        end

        if idx + 3 <= n and text:sub(idx, idx) == "<" then
            local s = text:sub(idx, idx + 3):lower()
            if s == "<cr>" or s == "<nl>" then
                return 4
            end
        end
        return nil
    end

    while i <= n do
        local mlen = marker_len_at(i)
        if not mlen then
            i = i + 1
        else
            push_keys_segment(normal_start, i - 1)

            local cmd_start = i + mlen
            local j = cmd_start
            local tend = nil
            local tlen = nil
            while j <= n do
                local len = cmd_terminator_len_at(j)
                if len then
                    tend = j - 1
                    tlen = len
                    break
                end
                j = j + 1
            end

            if not tend then
                -- Unterminated <Cmd>: keep legacy behavior for the remainder.
                local seq = Key.strtoseq(":" .. text:sub(cmd_start))
                if #seq > 0 then
                    ops[#ops + 1] = { kind = "keys", seq = seq }
                end
                normal_start = n + 1
                i = n + 1
            else
                local cmd_seq = Key.strtoseq(text:sub(cmd_start, tend))
                local cmdline = Key.seqtostr(cmd_seq)
                ops[#ops + 1] = { kind = "cmd", cmd = cmdline }
                i = tend + tlen + 1
                normal_start = i
            end
        end
    end

    push_keys_segment(normal_start, n)

    return ops
end

local function enqueue_feedkeys(ops, prepend)
    if #ops == 0 then
        return
    end

    if prepend then
        local merged = {}
        for i = 1, #ops do
            merged[#merged + 1] = ops[i]
        end
        for i = 1, #feedkeys_queue do
            merged[#merged + 1] = feedkeys_queue[i]
        end
        feedkeys_queue = merged
    else
        for i = 1, #ops do
            feedkeys_queue[#feedkeys_queue + 1] = ops[i]
        end
    end
end

local function flush_feedkeys_queue()
    if feedkeys_flushing then
        return
    end
    if #feedkeys_queue == 0 then
        return
    end

    feedkeys_flushing = true
    local lazy_block = options.get("lazyredraw")
    if lazy_block then
        lazyredraw_block = lazyredraw_block + 1
    end
    local queue = feedkeys_queue
    feedkeys_queue = {}
    local ok, err = pcall(function()
        for i = 1, #queue do
            local op = queue[i]
            if op.kind == "keys" then
                for j = 1, #op.seq do
                    if op.noremap then
                        Command._handle_key_with_policy(op.seq[j], Command.POLICY_NOREMAP, true)
                    else
                        Command.HandleKey(op.seq[j])
                    end
                end
            elseif op.kind == "cmd" then
                _run_feedkeys_cmdline(op.cmd)
            end
        end
    end)
    if lazy_block then
        lazyredraw_block = lazyredraw_block - 1
    end
    if not ok then
        feedkeys_flushing = false
        error(err)
    end
    feedkeys_flushing = false
end

local function schedule_feedkeys_flush()
    if feedkeys_flush_timer ~= nil then
        return
    end
    feedkeys_flush_timer = Event.StartTimer(0, function(id)
        if feedkeys_flush_timer == id then
            feedkeys_flush_timer = nil
        end
        flush_feedkeys_queue()
    end)
end

-- ========================
-- Namespace Management
-- ========================
-- Namespace 0 is the global namespace (highlights/etc.). Additional namespaces start at 1.
local ns_name_to_id, ns_id_to_name = {}, {}
local next_ns_id = 1

---Creates or retrieves a namespace id.
-- @param name string Namespace name or empty string for anonymous
-- @return integer Namespace id
function api.nvim_create_namespace(name)
    if type(name) ~= "string" then error("nvim_create_namespace: name must be string", 2) end
    if name ~= "" then
        local existing = ns_name_to_id[name]
        if existing then return existing end
    end
    local id = next_ns_id
    next_ns_id = next_ns_id + 1
    if name ~= "" then
        ns_name_to_id[name] = id
        ns_id_to_name[id] = name
    end
    return id
end

function api.nvim_get_namespaces()
    local out = {}
    for name, id in pairs(ns_name_to_id) do
        out[name] = id
    end
    return out
end

function api.nvim_set_decoration_provider(ns_id, opts)
    if type(ns_id) ~= "number" then
        error("nvim_set_decoration_provider: ns_id must be number", 2)
    end
    if opts ~= nil and type(opts) ~= "table" then
        error("nvim_set_decoration_provider: opts must be table or nil", 2)
    end

    Decoration.set_provider(ns_id, opts)
    what_redraw["windows"] = true
    need_redraw = true
end

-- ========================
-- Tabpage Functions
-- ========================

function api.nvim_get_current_tabpage()
    return curtp
end

function api.nvim_tabpage_list_wins(tp)
    if tp == 0 then tp = curtp end

    local rv = {}
    for k, v in pairs(tabpages[tp].windows) do
        rv[#rv + 1] = v.winnr
    end

    return rv
end

-- ========================
-- Window Functions
-- ========================
function api.nvim_win_get_buf(...)
    local window = expect_args({ ... }, 1)

    return win_for_id(window).buffer.bufnr
end

function api.nvim_win_set_cursor(...)
    local window, pos = expect_args({ ... }, 2)

    win_for_id(window):cursorSet(pos[2] + 1, pos[1])
end

function api.nvim_win_close(...)
    local window, force = expect_args({ ... }, 2)

    local win = win_for_id(window)
    tabpages[win.tabpagenr]:close(win, force)
end

function api.nvim_win_get_cursor(...)
    local window = expect_args({ ... }, 1)

    local win = win_for_id(window)
    return { win.cursory, win.cursorx - 1 }
end

function api.nvim_win_get_number(...)
    local window = expect_args({ ... }, 1)
    local win = win_for_id(window)
    local tp = tabpages[win.tabpagenr]
    if tp and tp.windows then
        for i = 1, #tp.windows do
            if tp.windows[i] == win then
                return i
            end
        end
    end
    return win.winnr
end

function api.nvim_list_wins()
    local rv = {}
    for k in pairs(windows) do
        rv[#rv + 1] = k
    end
    return rv
end

-- TODO: updatw Tabpage:WinSplit to handle things like "left" for split type
-- TODO: Z-indexing, various config fields
function api.nvim_open_win(buffer, enter, config)
    config = config or {}

    local buf = buf_for_bufnr(buffer)
    assert(buf)

    local function cleanup_failed_split_window(win)
        if not win then
            return
        end
        if windows[win.winnr] == win then
            windows[win.winnr] = nil
        end
        local b = win.buffer
        if b and type(b.refcount) == "number" then
            b.refcount = math.max(0, b.refcount - 1)
        end
    end

    local tabp = tabpages[curtp]
    local split_target = config.win or 0

    if not config.relative then
        local probe = tabp:MakeSplitProbe(nil)
        if not tabp:WinSplit(split_target, probe, false, { dry_run = true }) then
            error(Error(36):toString())
        end
    end

    local newwin = Window(buf)

    newwin.style = config.style
    if newwin.style == "minimal" then
        local val = newwin.opts.fillchars and (newwin.opts.fillchars .. ",") or ""
        val = val .. "eob: "
        newwin.opts.fillchars = val
    end

    if config.relative then
        newwin.floatpos = {
            reltype = config.relative,
            y = config.row,
            x = config.col,
            w = config.width,
            h = config.height
        }

        table.insert(tabpages[curtp].windows, newwin)
        newwin.tabpagenr = curtp
    else
        if not tabpages[curtp]:WinSplit(split_target, newwin, false) then
            cleanup_failed_split_window(newwin)
            error(Error(36):toString())
        end
    end

    if config.focusable ~= nil then
        newwin.focusable = config.focusable
    end

    if enter then
        enterWindow(newwin.winnr)
    end

    return newwin.winnr
end

function api.nvim_set_current_win(window)
    local win = windows[window]
    assert(win)

    if win.tabpagenr ~= curtp then
        curtp = win.tabpagenr
    end

    enterWindow(window)

    what_redraw["windows"] = true
    need_redraw = true
end

function api.nvim_get_current_win()
    return curwin
end

function api.nvim_win_is_valid(...)
    local window = expect_args({ ... }, 1)

    return windows[window] ~= nil
end

function api.nvim_win_set_buf(...)
    local window, buffer = expect_args({ ... }, 2)
    local win = win_for_id(window)
    local newbuf = buf_for_bufnr(buffer)
    assert(newbuf)

    local oldbuf = win.buffer
    if oldbuf == newbuf then
        return
    end

    if not newbuf:is_loaded() then
        newbuf:Load(true)
    end

    if oldbuf then
        oldbuf.refcount = math.max(0, (oldbuf.refcount or 1) - 1)
        win.altbuf = oldbuf
    end
    win.buffer = newbuf
    newbuf.refcount = (newbuf.refcount or 0) + 1

    local Syntax = loadModule("lib.syntax")
    Syntax.OnWindowBufferChanged(win)
    scopes.w.current_syntax = nil
    win.need_redraw = true
    what_redraw["windows"] = true
    need_redraw = true
end

function api.nvim_win_call(window, fun)
    window = win_for_id(window).winnr

    local old_curwin = curwin
    curwin = window

    local rv = { fun() }

    curwin = old_curwin

    return table.unpack(rv)
end

function api.nvim_win_set_option(window, name, value)
    options.set(name, value, true, win_for_id(window))
end

function api.nvim_win_get_config(window)
    window = win_for_id(window)

    return {
        relative = window.floatpos and window.floatpos.reltype or "",
        win = window.winnr,
        anchor = "NW", -- TODO: implement other anchors
        width = window.frame and window.frame.width or window.floatpos.w,
        height = window.frame and window.frame.height or window.floatpos.h,
        -- TODO: bufpos
        row = window.floatpos and window.floatpos.y or 1,
        col = window.floatpos and window.floatpos.x or 1,
        focusable = window.focusable,
        external = false,
        style = window.style,
        -- TODO: winborder
    }
end

function api.nvim_win_set_var(...)
    local window, name, value = expect_args({ ... }, 3)
    local win = win_for_id(window)
    if type(name) ~= "string" or name == "" then
        error("nvim_win_set_var: name must be non-empty string")
    end
    scopes.w[win.winnr][name] = value
end

function api.nvim_win_get_var(...)
    local window, name = expect_args({ ... }, 2)
    local win = win_for_id(window)
    if type(name) ~= "string" or name == "" then
        error("nvim_win_get_var: name must be non-empty string")
    end
    local value = scopes.w[win.winnr][name]
    if value == nil then
        error("nvim_win_get_var: Key not found: " .. name)
    end
    return value
end

function api.nvim_win_del_var(...)
    local window, name = expect_args({ ... }, 2)
    local win = win_for_id(window)
    if type(name) ~= "string" or name == "" then
        error("nvim_win_del_var: name must be non-empty string")
    end
    local wscope = scopes.w[win.winnr]
    if wscope[name] == nil then
        error("nvim_win_del_var: Key not found: " .. name)
    end
    wscope[name] = nil
end

function api.nvim_win_get_width(window)
    window = win_for_id(window)

    if window.frame then
        return window.frame.width
    elseif window.floatpos then
        return window.floatpos.w
    else
        error("Window with no frame or floatpos!")
    end
end

function api.nvim_win_set_width(winnr, new_size)
    local window = win_for_id(winnr)

    if window.frame then
        window:resizeWidth(window.frame.width - new_size)
    elseif window.floatpos then
        window.floatpos.w = new_size
    else
        error("Window with no frame or floatpos!")
    end
end

function api.nvim_win_get_option(winnr, name)
    local window = win_for_id(winnr)

    return options.get(name, window, nil, true)
end

function api.nvim_win_get_tabpage(winnr)
    return win_for_id(winnr).tabpagenr
end

-- =================
-- Autocmd Functions
-- =================


-- =================
-- ExCmd Functions
-- =================

function api.nvim_eval(expr)
    local rv = VimXpr.evaluate(expr)
    if Error.IsError(rv) then
        scopes._v.errmsg = rv:toString()
        error(rv:toString())
    end
    return rv
end

-- nvim_call_function(name, args) -> any
-- Calls a Vimscript function (user-defined or builtin). On Vimscript error, updates v:errmsg and
-- raises a Lua error (matching behavior of other API functions in this file).
function api.nvim_call_function(name, args)
    args = args or {}
    if type(name) ~= "string" then error("nvim_call_function: name must be string", 2) end
    if type(args) ~= "table" then error("nvim_call_function: args must be table", 2) end

    -- Call via fn._call which dispatches to Builtins or ExProg user functions.
    local ok, res = xpcall(function()
        return Fn._call(name, table.unpack(args))
    end, function(e)
        scopes._v.errmsg = tostring(e)
        return e
    end)

    if not ok then
        -- Rethrow as Lua error to match API behavior
        error(res)
    end

    return res
end

-- =================
-- Buffer Functions
-- =================

function api.nvim_create_buf(listed, scratch)
    local buf = Buffer(listed, scratch, true)
    return buf.bufnr
end

function api.nvim_buf_set_lines(buffer, start, end_, strict_indexing, replacement)
    local buf = buf_for_bufnr(buffer)
    assert(buf)

    buf:set_lines(start, end_, strict_indexing, replacement)
    request_buffer_redraw(buf, true)
end

function api.nvim_buf_set_keymap(buffer, mode, lhs, rhs, opts)
    opts = opts or {}

    local buf = buf_for_bufnr(buffer)
    assert(buf)

    local lhs_text = tostring(lhs or "")
    local rhs_text = tostring(rhs or "")
    lhs = Key.strtoseq(lhs_text)

    if opts.callback then
        ScriptSource = ScriptSource or loadModule("lib.scriptsource")
        local cb = ScriptSource.wrap(nil, opts.callback)
        Command.map_callback(mode, lhs, cb, { buffer = buf })
    else
        rhs = Key.strtoseq(rhs_text)
        if opts.noremap then
            Command.noremap_keys(mode, lhs, rhs, { buffer = buf })
        else
            Command.remap_keys(mode, lhs, rhs, { buffer = buf })
        end
    end

    record_keymap(true, buf.bufnr, mode, lhs_text, rhs_text, opts)
end

function api.nvim_set_keymap(mode, lhs, rhs, opts)
    opts = opts or {}
    local lhs_text = tostring(lhs or "")
    local rhs_text = tostring(rhs or "")
    lhs = Key.strtoseq(lhs_text)

    if opts.callback then
        ScriptSource = ScriptSource or loadModule("lib.scriptsource")
        local cb = ScriptSource.wrap(nil, opts.callback)
        Command.map_callback(mode, lhs, cb)
    else
        rhs = Key.strtoseq(rhs_text)
        if opts.noremap then
            Command.noremap_keys(mode, lhs, rhs)
        else
            Command.remap_keys(mode, lhs, rhs)
        end
    end

    record_keymap(false, nil, mode, lhs_text, rhs_text, opts)
end

function api.nvim_get_keymap(mode)
    return list_keymaps(false, nil, mode)
end

function api.nvim_buf_get_keymap(buffer, mode)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    return list_keymaps(true, buf.bufnr, mode)
end

function api.nvim_buf_del_keymap(buffer, mode, lhs)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    Command.unmap_keys(mode, Key.strtoseq(lhs), { buffer = buf })
    delete_keymap_record(true, buf.bufnr, mode, lhs)
end

function api.nvim_del_keymap(mode, lhs)
    Command.unmap_keys(mode, Key.strtoseq(lhs))
    delete_keymap_record(false, nil, mode, lhs)
end

function api.nvim_buf_set_text(buffer, start_row, start_col, end_row, end_col, replacement)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    buf:ensure_loaded(true)

    local srow = tonumber(start_row or 0) or 0
    local scol = tonumber(start_col or 0) or 0
    local erow = tonumber(end_row or srow) or srow
    local ecol = tonumber(end_col or scol) or scol

    if srow < 0 then srow = 0 end
    if erow < 0 then erow = 0 end
    if scol < 0 then scol = 0 end
    if ecol < 0 then ecol = 0 end

    local lines = buf:lines_ref(true)
    local line_count = #lines
    if line_count == 0 then
        lines[1] = ""
        line_count = 1
    end

    local sidx = math.min(line_count - 1, srow) + 1
    local eidx = math.min(line_count - 1, erow) + 1
    if sidx > eidx then
        sidx, eidx = eidx, sidx
        scol, ecol = ecol, scol
    end

    local sline = lines[sidx] or ""
    local eline = lines[eidx] or ""
    local prefix = buf:str_sub(sline, 1, scol)
    local suffix = buf:str_sub(eline, ecol + 1)

    local repl = {}
    if type(replacement) == "table" then
        for i = 1, #replacement do
            repl[#repl + 1] = tostring(replacement[i] or "")
        end
    end
    if #repl == 0 then
        repl[1] = ""
    end

    repl[1] = prefix .. repl[1]
    repl[#repl] = repl[#repl] .. suffix

    buf:set_lines(sidx - 1, eidx, false, repl)
    request_buffer_redraw(buf, true)
end

-- TODO: use a window displaying the buffer, if it exists in the current tabpage
function api.nvim_buf_call(buffer, fun)
    local buf = buffers[buffer]
    assert(buf)

    local oldcurbuf = windows[curwin].buffer
    windows[curwin].buffer = buf

    local rv = { fun() }

    windows[curwin].buffer = oldcurbuf

    return table.unpack(rv)
end

function api.nvim_buf_get_option(bufnr, option)
    local buf = buffers[bufnr]
    assert(buf)

    return options.get(option, nil, buf, true)
end

function api.nvim_buf_set_option(bufnr, option, value)
    local buf = buffers[bufnr]
    assert(buf)

    options.set(option, value, true, nil, buf)
end

-- =================
-- File Functions
-- =================

function api.nvim_list_runtime_paths()
    local RuntimePath = loadModule("lib.runtimepath")
    return RuntimePath.get_search_list()
end

function api.nvim_get_runtime_file(path, all)
    local RuntimePath = loadModule("lib.runtimepath")
    local Filesystem = loadModule("lib.filesystem")

    local rtp = RuntimePath.get_search_list()

    local results = {}
    for _, base in ipairs(rtp) do
        local matches = Filesystem.ExpandWildcards(base .. "/" .. path)
        for _, m in ipairs(matches) do
            results[#results + 1] = m
            if not all then
                return results
            end
        end
    end

    return results
end

-- =================
-- Highlighting Functions
-- =================
function api.nvim_get_hl_by_name(name)
    local hl = Highlight.For(name, 0, true)
    local raw = Highlight.RawFor(name) or {}

    return {
        foreground = api_color_value(raw._raw_fg, hl[1]),
        background = api_color_value(raw._raw_bg, hl[2]),
    }
end

function api.nvim_set_option_value(name, value, opts)
    opts = opts or {}

    local win, buf
    if opts.win ~= nil then
        win = win_for_id(opts.win)
    else
        win = windows[curwin]
    end
    if opts.buf ~= nil then
        buf = buf_for_bufnr(opts.buf)
    else
        buf = win.buffer
    end

    return options.set(name, value, opts.scope == "local", win, buf, opts.scope == "global")
end

api.nvim_set_option = api.nvim_set_option_value

-- TODO: opts.filetype
function api.nvim_get_option_value(name, opts)
    opts = opts or {}

    local win, buf
    if opts.win ~= nil then
        win = win_for_id(opts.win)
    else
        win = windows[curwin]
    end
    if opts.buf ~= nil then
        buf = buf_for_bufnr(opts.buf)
    else
        buf = win.buffer
    end

    return options.get(name, win, buf, opts.scope == "local", opts.scope == "global")
end

-- TODO: Craft the full strings if the option is passed
function api.nvim_get_mode()
    if vimmode == "normal" then
        return { mode = "n" }
    elseif vimmode == "insert" then
        return { mode = "i" }
    else
        error("unhandled mode in nvim_get_mode")
    end
end

function api.nvim__redraw(opts)
    opts = opts or {}

    local flush = opts.flush
    if flush == nil then
        flush = true
    else
        flush = not not flush
    end

    local touched_window = false
    local target_buf = nil

    local function mark_window_for_redraw(win)
        win.need_redraw = true
        touched_window = true
    end

    local function mark_windows_for_buffer(buf)
        if not buf then
            return
        end
        for _, win in pairs(windows) do
            if win.buffer == buf then
                mark_window_for_redraw(win)
            end
        end
    end

    local function mark_all_windows_for_redraw()
        for _, win in pairs(windows) do
            mark_window_for_redraw(win)
        end
    end

    if opts.win ~= nil then
        local win = win_for_id(opts.win)
        mark_window_for_redraw(win)
        target_buf = win.buffer
    elseif opts.buf ~= nil then
        target_buf = buf_for_bufnr(opts.buf)
        mark_windows_for_buffer(target_buf)
    end

    if opts.range ~= nil and not touched_window then
        if not target_buf then
            target_buf = windows[curwin].buffer
        end
        mark_windows_for_buffer(target_buf)
    end

    if opts.statusline or opts.statuscolumn or opts.winbar then
        if opts.statusline then
            what_redraw["statusline"] = true
        end
        if opts.statuscolumn then
            what_redraw["statuscolumn"] = true
        end
        if opts.winbar then
            what_redraw["winbar"] = true
        end
        if not touched_window then
            mark_all_windows_for_redraw()
        end
    end

    if opts.cursor then
        what_redraw["cursor"] = true
        if not touched_window then
            mark_window_for_redraw(windows[curwin])
        end
    end

    if opts.valid ~= nil and not touched_window then
        what_redraw["windows"] = true
    end

    if opts.tabline then
        what_redraw["tabline"] = true
    elseif not touched_window and opts.range == nil and opts.valid == nil then
        what_redraw["windows"] = true
    end

    need_redraw = true
    lazyredraw_force = true

    if flush and not Decoration.is_redraw_active() then
        local tab = tabpages[curtp]
        if tab and type(tab.render) == "function" then
            need_redraw = false
            tab:render()
            what_redraw = {}
            lazyredraw_force = false
        end
    end
end

-- =================
-- Exec Functions
-- =================

-- Captures non-error Ex output by monkey-patching ExMsg briefly.
-- Returns: ok:boolean (pcall success), ran_ok:boolean|nil, err_obj:any, output:string, last_err:string|nil, thrown:any
-- Where:
--   ok == true  => pcall succeeded, ran_ok is first return from Runtime.run, err_obj is second
--   ok == false => Lua error thrown; ran_ok is the error message, err_obj=nil, thrown carries the thrown value
local function with_capture(run_fn)
    -- Begin structured capture (no monkey-patching)
    local cap = ExMsg.StartCapture()
    local thrown = nil
    local ok, r1, r2 = xpcall(run_fn, function(e)
        thrown = e
        return e
    end)
    local output, last_err = ExMsg.EndCapture(cap)
    -- Maintain return contract: ok, ran_ok, err_obj, output, last_err, thrown
    return ok, r1, r2, output, last_err, thrown
end

-- Internal unified executor.
-- Creates a fresh s: for each call, shares GLOBAL.g between calls.
local function exec_script(src, opts)
    opts = opts or {}
    local state = {
        g = scopes._g, -- shared between calls (g:)
        s = {},        -- fresh per "source" call (s:)
        v = scopes._v,
        funcs = Runtime._FUNCS,
        frames = {},
        commands = {},
    }

    local function run()
        if opts.output then
            -- Suppress user-facing message output while still capturing it.
            ExMsg.PushUISuppress()
        end
        local ok, r1, r2 = pcall(Runtime.run, src, { state = state, ctrl = Runtime._CURRENT_CTRL })
        if opts.output then
            ExMsg.PopUISuppress()
        end
        if not ok then
            error(r1)
        end
        return r1, r2
    end

    local ok, ran_ok, err_obj, output, last_err, thrown = with_capture(run)

    -- pcall failed (Lua exception):
    if not ok then
        local emsg = tostring(thrown or last_err or "E15: Invalid expression")
        if scopes then scopes._v.errmsg = emsg else state.v.errmsg = emsg end
        return false, output, scopes._v.errmsg or state.v.errmsg
    end

    -- Runner signaled error:
    if not ran_ok then
        LOG_DEBUG("not ran_ok: " .. src)
        -- Derive a meaningful error message in priority order
        local emsg = last_err
            or err_obj:toString()
            or (err_obj and tostring(err_obj))
            or scopes._v.errmsg
            or state.v.errmsg
            or "INTERNAL ERROR: UNKNOWN"
        LOG_DEBUG("\treason: " .. emsg)
        if scopes then scopes._v.errmsg = emsg else state.v.errmsg = emsg end
        return false, output, scopes._v.errmsg or state.v.errmsg
    end

    -- Success
    return true, (opts.output and output or ""), nil
end

-- nvim_exec(src, output:boolean) -> string
function api.nvim_exec(src, output)
    local ok, out, err = exec_script(src, { output = not not output })
    if not ok then
        -- Match API contract: "fails and updates v:errmsg" (we raise an error)
        error(err or "Execution failed")
    end
    return out or ""
end

-- nvim_exec2(src, {output?:boolean}) -> { output?: string }
function api.nvim_exec2(src, opts)
    opts = opts or {}
    local ok, out, err = exec_script(src, { output = not not opts.output })
    return opts.output and { output = out } or { output = nil }
end

local function as_list(x)
    if x == nil then return {} end
    if type(x) == "table" then return x end
    return { x }
end

function api.nvim_exec_autocmds(events, opts)
    opts = opts or {}

    -- Normalize events to a list
    local evs = as_list(events)
    if #evs == 0 then
        error("Invalid 'event'")
    end

    -- pattern and buffer are mutually exclusive (NVim API)
    local has_pattern = opts.pattern ~= nil
    local has_buffer  = opts.buffer ~= nil
    if has_pattern and has_buffer then
        error("Both pattern and buffer used (not allowed)")
    end

    -- Normalize pattern(s). Default per API is "*".
    local patterns
    if has_buffer then
        -- When {buffer} is given, ignore pattern entirely and select buffer-local autocmds.
        patterns = { false } -- sentinel meaning: don't set ctx.pattern
    else
        local p = opts.pattern
        if p == nil then
            patterns = { "*" }
        else
            patterns = as_list(p)
        end
    end

    -- Build the fixed part of ctx
    local base_ctx = {}
    if opts.group ~= nil then base_ctx.group = opts.group end
    if opts.buffer ~= nil then base_ctx.bufnr = opts.buffer end
    -- NOTE: We do NOT force bufname: for buffer-local execution <buffer=N> matching
    -- doesn't need it. If you want <afile>/<amatch>-like values for callbacks,
    -- you could resolve bufnr -> name here and set base_ctx.bufname.
    if opts.data ~= nil then base_ctx.data = opts.data end

    -- Execute. We intentionally ignore opts.modeline (by request).
    for _, ev in ipairs(evs) do
        for _, pat in ipairs(patterns) do
            local ctx = {}
            for k, v in pairs(base_ctx) do ctx[k] = v end
            if pat then
                ctx.pattern = pat -- becomes match_ctx.pattern_target in Autocmd.Run
                ctx.bufname = ctx.bufname or pat
            end
            AutoCmd.Run(ev, ctx)
        end
    end
end

-- temp: TODO: check semantics
api.nvim_command = api.nvim_exec2

-- TODO: namespaces
function api.nvim_get_hl(ns_id, opts)
    opts = opts or {}
    local ns = ns_id or 0
    local name = opts.name
    if not name and opts.id then
        name = Highlight.NameById(opts.id)
        if not name then return {} end
    end
    if not name then error("nvim_get_hl: pass opts.name or opts.id", 2) end

    if not Highlight.HasGroup(name, ns) then
        if opts.create == false then
            return {}
        end
        Highlight.Clear(name, ns)
    end

    Highlight.IdByName(name) -- still global for now

    local link = Highlight.GetLink(name, ns)
    if link and (opts.link == nil or opts.link) then
        return { link = link }
    end

    local hl = Highlight.For(name, ns, true)
    local raw = Highlight.RawFor(name, ns) or {}
    local out = {}
    local fg = api_color_value(raw._raw_fg, hl[1])
    if fg ~= nil then
        out.fg = fg
    end
    local bg = api_color_value(raw._raw_bg, hl[2])
    if bg ~= nil then
        out.bg = bg
    end
    return out
end

function api.nvim_get_color_by_name(name)
    if type(name) ~= "string" then return -1 end

    local hex = name:match("^#(%x%x%x%x%x%x)$")
    if hex then return tonumber("0x" .. hex) end

    local alias = COLOR_ALIASES[string.lower(name)]
    if alias then
        return rgb_for_palette_index(alias)
    end

    return -1
end

function api.nvim_get_color_map()
    local map = {}
    for k, idx in pairs(COLOR_ALIASES) do
        map[k] = rgb_for_palette_index(idx)
    end
    return map
end

function api.nvim_set_hl(ns_id, name, val)
    if type(name) ~= "string" then error("nvim_set_hl: name must be string", 2) end

    local ns = ns_id or 0
    val = val or {}

    if val.default and Highlight.HasGroup(name, ns) then
        return
    end

    local hlval = {
        fg = normalize_color_value(val.fg),
        bg = normalize_color_value(val.bg),
        link = val.link,
        reverse = val.reverse or val.standout,
    }

    Highlight.SetHL(ns, name, hlval)
end

local created_augroup_names = {}
function api.nvim_create_augroup(name, opts)
    opts = opts or {}

    local clear = true
    if opts.clear ~= nil then
        clear = opts.clear
    end

    local id = AutoCmd.CreateAugroup(name, clear)
    -- Track for possible reverse lookup (not strictly needed now that autocmd has helper)
    local seen = false
    for _, n in ipairs(created_augroup_names) do
        if n == name then
            seen = true; break
        end
    end
    if not seen then created_augroup_names[#created_augroup_names + 1] = name end
    return id
end

local function _split_autocmd_pattern_csv(raw)
    if type(raw) ~= "string" then
        return { raw }
    end

    local out = {}
    local piece = {}
    local i = 1
    while i <= #raw do
        local ch = raw:sub(i, i)
        if ch == "\\" and i < #raw then
            local nxt = raw:sub(i + 1, i + 1)
            if nxt == "," then
                piece[#piece + 1] = ","
                i = i + 2
            else
                piece[#piece + 1] = ch
                i = i + 1
            end
        elseif ch == "," then
            local pat = table.concat(piece)
            if pat ~= "" then
                out[#out + 1] = pat
            end
            piece = {}
            i = i + 1
        else
            piece[#piece + 1] = ch
            i = i + 1
        end
    end

    local tail = table.concat(piece)
    if tail ~= "" then
        out[#out + 1] = tail
    end
    return out
end

function api.nvim_create_autocmd(event, opts)
    opts = opts or {}

    if type(event) == "string" then
        event = { event }
    end

    local patterns = opts.pattern
    if opts.buffer ~= nil then
        if patterns ~= nil then
            error("nvim_create_autocmd: cannot use both 'pattern' and 'buffer'")
        end
        local bufnr = opts.buffer
        if bufnr == 0 then
            bufnr = windows[curwin].buffer.bufnr
        end
        patterns = { ("<buffer=%d>"):format(bufnr) }
    elseif patterns then
        if type(patterns) == "string" then
            patterns = _split_autocmd_pattern_csv(patterns)
        elseif type(patterns) == "table" then
            local expanded = {}
            for _, p in ipairs(patterns) do
                if type(p) == "string" then
                    local parts = _split_autocmd_pattern_csv(p)
                    for i = 1, #parts do
                        expanded[#expanded + 1] = parts[i]
                    end
                else
                    expanded[#expanded + 1] = p
                end
            end
            patterns = expanded
        end
    end

    ScriptSource = ScriptSource or loadModule("lib.scriptsource")
    local cb = opts.callback and ScriptSource.wrap(nil, opts.callback)
    local script_ctx = ScriptSource.CurrentContext()

    return AutoCmd.CreateAutocommand(event, patterns, cb, opts.command, opts.group, opts.once, opts
        .nested, opts.desc, script_ctx)
end

function api.nvim_get_autocmds(opts)
    opts = opts or {}
    return AutoCmd.GetAutocommands(opts)
end

function api.nvim_del_autocmd(id)
    if type(id) ~= "number" then
        error("nvim_del_autocmd: id must be number", 2)
    end
    local ok = AutoCmd.RemoveById(id)
    if not ok then
        error("nvim_del_autocmd: no such autocmd id " .. tostring(id))
    end
end

function api.nvim_clear_autocmds(opts)
    opts = opts or {}
    local events = opts.event
    if type(events) == "string" then
        events = { events }
    end

    local patterns = opts.pattern
    if type(patterns) == "string" then
        patterns = { patterns }
    end

    if opts.buffer ~= nil then
        if patterns ~= nil then
            error("nvim_clear_autocmds: cannot use both 'pattern' and 'buffer'")
        end
        local bufnr = opts.buffer
        if bufnr == 0 then
            bufnr = windows[curwin].buffer.bufnr
        end
        patterns = { ("<buffer=%d>"):format(bufnr) }
    end

    AutoCmd.RemoveAutocommands(opts.group, events, patterns)
end

-- Delete an augroup by its numeric id (mirrors :augroup! behavior, but by id).
-- Returns true on success. Raises an error if the id is invalid.
function api.nvim_del_augroup_by_id(id)
    if type(id) ~= "number" then error("nvim_del_augroup_by_id: id must be number", 2) end
    local ok, err, warn = AutoCmd.DeleteAugroupById(id)
    if not ok then
        error(err:toString())
    end
    if warn then LOG_DEBUG(warn) end
    return true
end

-- ========================
-- User Command Functions (minimal subset for nvim-tree usage)
-- ========================
local _user_commands = {}

---Create a (global) user command.
-- Minimal implementation supporting: force, nargs ("?", "1"/1), bang, desc, complete (ignored), bar (ignored).
-- @param name string Command name (must start with uppercase letter)
-- @param command string|function Ex command string or Lua callback
-- @param opts table Attributes (subset)
function api.nvim_create_user_command(name, command, opts)
    opts = opts or {}

    if type(name) ~= "string" or not name:match("^[A-Z]") then
        error("nvim_create_user_command: name must start with an uppercase letter", 2)
    end
    if command == nil then
        error("nvim_create_user_command: missing command", 2)
    end
    if type(opts) ~= "table" then
        error("nvim_create_user_command: opts must be table", 2)
    end

    local lname = name:lower()

    -- Handle replacement / force
    if _user_commands[lname] and opts.force == false then
        error(":" .. name .. " already exists (add { force = true } to override)")
    end

    if type(command) == "function" then
        local wrap = (ScriptSource or loadModule("lib.scriptsource")).wrap
        command = wrap(nil, command)
    end

    _user_commands[lname] = { name = name, command = command, opts = opts }
    Runtime.RegisterUserCommand(name, {
        handler = function(info)
            local def = _user_commands[lname]
            if not def then return end

            local nargs_spec = def.opts.nargs
            local argc = #(info.fargs or {})
            if type(nargs_spec) == "number" then
                if argc ~= nargs_spec then error(":" .. def.name .. " expects exactly " .. nargs_spec .. " arg(s)") end
            elseif type(nargs_spec) == "string" then
                if nargs_spec == "?" then
                    if argc > 1 then error(":" .. def.name .. " expects 0 or 1 arg") end
                elseif nargs_spec == "1" then
                    if argc ~= 1 then error(":" .. def.name .. " expects exactly 1 arg") end
                elseif nargs_spec == "+" then
                    if argc == 0 then error(":" .. def.name .. " expects at least 1 arg") end
                elseif nargs_spec == "0" then
                    if argc ~= 0 then error(":" .. def.name .. " expects no args") end
                end
            end

            local cmdopts = {
                name = def.name,
                args = info._ccvim.raw_args or "",
                fargs = info.fargs or {},
                nargs = def.opts.nargs,
                bang = info.bang or false,
                line1 = windows[curwin].cursory,
                line2 = windows[curwin].cursory,
                range = 0,
                reg = nil,
                mods = "",
                smods = {},
            }

            if type(def.command) == "function" then
                return def.command(cmdopts)
            elseif type(def.command) == "string" then
                api.nvim_exec(def.command, false)
            end
        end,
    })
end

function api.nvim_get_current_buf()
    return windows[curwin].buffer.bufnr
end

function api.nvim_get_current_line()
    local win = windows[curwin]
    return win.buffer:get_line(win.cursory, true) or ""
end

function api.nvim_set_current_buf(buffer)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    api.nvim_win_set_buf(0, buf.bufnr)
end

function api.nvim_buf_get_name(bufnr)
    local buf = buf_for_bufnr(bufnr)
    assert(buf)

    return buf.name or ""
end

function api.nvim_list_bufs()
    local bufs = {}
    for _, v in pairs(buffers) do
        bufs[#bufs + 1] = v.bufnr
    end
    return bufs
end

function api.nvim_buf_is_valid(bufnr)
    return buf_for_bufnr(bufnr) ~= nil -- TODO: wrong semantics, this is not what valid means!
end

function api.nvim_buf_set_var(buffer, name, value)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    if type(name) ~= "string" or name == "" then
        error("nvim_buf_set_var: name must be non-empty string")
    end
    scopes.b[buf.bufnr][name] = value
end

function api.nvim_buf_get_var(buffer, name)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    if type(name) ~= "string" or name == "" then
        error("nvim_buf_get_var: name must be non-empty string")
    end
    local value = scopes.b[buf.bufnr][name]
    if value == nil then
        error("nvim_buf_get_var: Key not found: " .. name)
    end
    return value
end

function api.nvim_buf_del_var(buffer, name)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    if type(name) ~= "string" or name == "" then
        error("nvim_buf_del_var: name must be non-empty string")
    end
    local bscope = scopes.b[buf.bufnr]
    if bscope[name] == nil then
        error("nvim_buf_del_var: Key not found: " .. name)
    end
    bscope[name] = nil
end

function api.nvim_buf_set_name(bufnr, name)
    local buf = buf_for_bufnr(bufnr)
    assert(buf)

    buf.name = name
    request_buffer_redraw(buf, false)
end

-- TODO: Proper swap file and load/store semantics
function api.nvim_buf_is_loaded(bufnr)
    local buf = buf_for_bufnr(bufnr)
    if not buf then
        return false
    end
    return buf:is_loaded()
end

function api.nvim_buf_delete(buffer, opts)
    opts = opts or {}
    local buf = buf_for_bufnr(buffer)
    assert(buf)

    local force = not not opts.force
    local unload = not not opts.unload

    if (buf.opts and buf.opts.modified) and not force then
        error("nvim_buf_delete: buffer has unsaved changes (use force=true)")
    end

    local function normalize_altbuf(alt)
        if type(alt) == "number" then
            return buffers[alt]
        elseif type(alt) == "table" then
            return alt
        end
    end

    local function pick_replacement(prefer_win)
        local alt = normalize_altbuf(prefer_win and prefer_win.altbuf)
        if alt and alt ~= buf and buffers[alt.bufnr] then
            return alt
        end

        local ids = {}
        for id, _ in pairs(buffers) do
            ids[#ids + 1] = id
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local candidate = buffers[id]
            if candidate and candidate ~= buf then
                return candidate
            end
        end

        local created = Buffer(true, false, true)
        created.name = ""
        return created
    end

    for _, win in pairs(windows) do
        if win.buffer == buf then
            local replacement = pick_replacement(win)
            if replacement ~= buf then
                buf.refcount = math.max(0, (buf.refcount or 1) - 1)
                win.buffer = replacement
                replacement.refcount = (replacement.refcount or 0) + 1
                if win.altbuf == buf or win.altbuf == buf.bufnr then
                    win.altbuf = nil
                end
                local Syntax = loadModule("lib.syntax")
                Syntax.OnWindowBufferChanged(win)
                win.need_redraw = true
            end
        elseif win.altbuf == buf or win.altbuf == buf.bufnr then
            win.altbuf = nil
        end
    end

    BufAttach.detach(buf.bufnr)
    scopes._b_by_buf[buf.bufnr] = nil

    if unload then
        buf.lines = {}
        buf.loaded = false
        buf.syntax_ctx = nil
        buf.state = "hidden"
    else
        buffers[buf.bufnr] = nil
    end

    what_redraw["windows"] = true
    need_redraw = true
end

-- TODO: set up proper RPC handling for send_buffer
function api.nvim_buf_attach(buffer, send_buffer, opts)
    local bufnr = tonumber(buffer)
    if not bufnr then
        return false
    end

    local buf
    if bufnr == 0 then
        buf = windows[curwin].buffer
    else
        buf = buffers[bufnr]
    end
    if not buf then
        return false
    end
    if not buf:is_loaded() then
        return false
    end

    if opts == nil then
        opts = {}
    end
    if type(opts) ~= "table" then
        return false
    end

    local callback_keys = { "on_lines", "on_bytes", "on_changedtick", "on_detach", "on_reload" }
    for i = 1, #callback_keys do
        local key = callback_keys[i]
        local cb = opts[key]
        if cb ~= nil and type(cb) ~= "function" then
            return false
        end
    end

    ScriptSource = ScriptSource or loadModule("lib.scriptsource")
    local listener = {
        on_lines = opts.on_lines and ScriptSource.wrap(nil, opts.on_lines),
        on_bytes = opts.on_bytes and ScriptSource.wrap(nil, opts.on_bytes),
        on_changedtick = opts.on_changedtick and ScriptSource.wrap(nil, opts.on_changedtick),
        on_detach = opts.on_detach and ScriptSource.wrap(nil, opts.on_detach),
        on_reload = opts.on_reload and ScriptSource.wrap(nil, opts.on_reload),
        utf_sizes = opts.utf_sizes == true,
        preview = opts.preview == true,
    }

    local ok = BufAttach.attach(buf.bufnr, listener)
    if not ok then
        return false
    end

    return true
end

function api.nvim_buf_detach(buffer)
    local bufnr = tonumber(buffer)
    if not bufnr then
        return false
    end

    local buf
    if bufnr == 0 then
        buf = windows[curwin].buffer
    else
        buf = buffers[bufnr]
    end
    if not buf then
        return false
    end

    return BufAttach.detach(buf.bufnr)
end

function api.nvim_buf_get_changedtick(buffer)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    return BufAttach.get_changedtick(buf.bufnr)
end

function api.nvim_buf_clear_namespace(buffer, ns_id, line_start, line_end)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    buf._extmarks = buf._extmarks or {}

    if ns_id == -1 then
        buf._extmarks = {}
        Decoration.clear_ephemeral_namespace(buf.bufnr, ns_id, line_start, line_end)
        return
    end

    if not buf._extmarks[ns_id] then
        Decoration.clear_ephemeral_namespace(buf.bufnr, ns_id, line_start, line_end)
        return
    end

    local ns_marks = buf._extmarks[ns_id]
    if line_start == nil then line_start = 0 end
    if line_end == nil then line_end = -1 end

    if line_start == 0 and line_end == -1 then
        buf._extmarks[ns_id] = {}
        Decoration.clear_ephemeral_namespace(buf.bufnr, ns_id, line_start, line_end)
        return
    end

    for id, mark in pairs(ns_marks) do
        local lnum = mark.line or 0
        local in_range = lnum >= line_start and (line_end < 0 or lnum < line_end)
        if in_range then
            ns_marks[id] = nil
        end
    end
    Decoration.clear_ephemeral_namespace(buf.bufnr, ns_id, line_start, line_end)
end

local function _extmark_pos_from_arg(arg)
    if type(arg) == "table" then
        local line = tonumber(arg[1] or 0) or 0
        local col = tonumber(arg[2] or 0) or 0
        return line, col
    end
    if type(arg) == "number" then
        return arg, 0
    end
    return 0, 0
end

local function _extmark_in_range(mark, start_line, start_col, end_line, end_col)
    local line = mark.line or 0
    local col = mark.col or 0

    if line < start_line or line > end_line then
        return false
    end
    if line == start_line and col < start_col then
        return false
    end
    if line == end_line then
        if end_col >= 0 and col > end_col then
            return false
        end
    end
    return true
end

function api.nvim_buf_get_extmarks(buffer, ns_id, start, _end, opts)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    opts = opts or {}
    buf._extmarks = buf._extmarks or {}

    local start_line, start_col = _extmark_pos_from_arg(start)
    local end_line, end_col = _extmark_pos_from_arg(_end)
    if end_line < start_line or (end_line == start_line and end_col >= 0 and end_col < start_col) then
        start_line, end_line = end_line, start_line
        start_col, end_col = end_col, start_col
    end

    local items = {}

    Decoration.iter_extmarks(buf, function(mark_ns, id, mark)
        if ns_id == -1 or mark_ns == ns_id then
            if _extmark_in_range(mark, start_line, start_col, end_line, end_col) then
                items[#items + 1] = { id = id, mark = mark }
            end
        end
    end)

    table.sort(items, function(a, b)
        local la = a.mark.line or 0
        local lb = b.mark.line or 0
        if la ~= lb then
            return la < lb
        end
        local ca = a.mark.col or 0
        local cb = b.mark.col or 0
        if ca ~= cb then
            return ca < cb
        end
        return a.id < b.id
    end)

    if opts.limit and tonumber(opts.limit) and tonumber(opts.limit) >= 0 then
        local lim = tonumber(opts.limit)
        while #items > lim do
            items[#items] = nil
        end
    end

    local out = {}
    for i = 1, #items do
        local id = items[i].id
        local mark = items[i].mark
        local entry = { id, mark.line or 0, mark.col or 0 }
        if opts.details then
            local details = {}
            for k, v in pairs(mark.opts or {}) do
                details[k] = v
            end
            entry[4] = details
        end
        out[#out + 1] = entry
    end
    return out
end

function api.nvim_buf_set_extmark(buffer, ns_id, line, col, opts)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    opts = opts or {}
    buf._extmarks = buf._extmarks or {}
    buf._extmarks[ns_id] = buf._extmarks[ns_id] or {}

    local ns_marks = buf._extmarks[ns_id]
    buf._next_extmark_id = buf._next_extmark_id or {}
    local id = opts.id
    if not id then
        local nextid = buf._next_extmark_id[ns_id] or 1
        id = nextid
        buf._next_extmark_id[ns_id] = nextid + 1
    end

    local mark = {
        line = line,
        col = col,
        opts = opts,
    }
    local stored_ephemeral = false
    if opts.ephemeral then
        stored_ephemeral = Decoration.add_ephemeral_extmark(buf.bufnr, ns_id, id, mark)
    end

    if not stored_ephemeral then
        ns_marks[id] = mark
        if opts.sign_text ~= nil or opts.line_hl_group ~= nil or opts.number_hl_group ~= nil then
            request_buffer_redraw(buf, false)
        end
    end
    return id
end

function api.nvim_buf_del_extmark(buffer, ns_id, id)
    local buf = buf_for_bufnr(buffer)
    assert(buf)
    buf._extmarks = buf._extmarks or {}

    local removed = false
    local ns_marks = buf._extmarks[ns_id]
    local removed_mark = nil
    if ns_marks and ns_marks[id] ~= nil then
        removed_mark = ns_marks[id]
        ns_marks[id] = nil
        removed = true
    end

    if Decoration.del_ephemeral_extmark(buf.bufnr, ns_id, id) then
        removed = true
    end

    local ropts = removed_mark and removed_mark.opts
    if ropts and (ropts.sign_text ~= nil or ropts.line_hl_group ~= nil or ropts.number_hl_group ~= nil) then
        request_buffer_redraw(buf, false)
    end

    return removed
end

function api.nvim_buf_add_highlight(buffer, ns_id, hl_group, line, col_start, col_end)
    local buf = buf_for_bufnr(buffer)
    assert(buf)

    if ns_id == 0 then
        ns_id = api.nvim_create_namespace("")
    end

    if hl_group == "" then
        return ns_id
    end

    local opts = { hl_group = hl_group }
    if col_end ~= nil then
        opts.end_col = col_end
    end

    -- ignore extmark id return value; callers expect ns_id.
    api.nvim_buf_set_extmark(buffer, ns_id, line, col_start, opts)
    return ns_id
end

function api.nvim_strwidth(text)
    return Utf8.len(text)
end

function api.nvim_echo(chunks, history, opts)
    local parts = {}
    if type(chunks) == "table" then
        for i = 1, #chunks do
            local item = chunks[i]
            if type(item) == "table" then
                parts[#parts + 1] = tostring(item[1] or "")
            else
                parts[#parts + 1] = tostring(item)
            end
        end
    else
        parts[#parts + 1] = tostring(chunks or "")
    end
    ExMsg.echo(table.concat(parts))
end

function api.nvim_list_tabpages()
    local out = {}
    for tabnr, _ in pairs(tabpages) do
        out[#out + 1] = tabnr
    end
    table.sort(out)
    return out
end

function api.nvim_win_get_height(window)
    local win = win_for_id(window)
    if win.frame then
        return win.frame.height
    end
    return (win.floatpos and win.floatpos.h) or screen.height
end

function api.nvim_win_set_config(window, config)
    local win = win_for_id(window)
    config = config or {}
    win.floatpos = win.floatpos or {
        reltype = "",
        y = 0,
        x = 0,
        w = screen.width,
        h = screen.height,
    }

    if config.relative ~= nil then win.floatpos.reltype = config.relative end
    if config.row ~= nil then win.floatpos.y = config.row end
    if config.col ~= nil then win.floatpos.x = config.col end
    if config.width ~= nil then win.floatpos.w = config.width end
    if config.height ~= nil then win.floatpos.h = config.height end
end

function api.nvim_replace_termcodes(str, from_part, do_lt, special)
    return Key.replace_termcodes(str, do_lt, special)
end

function api.nvim_feedkeys(keys, mode, escape_ks)
    local ops = _parse_feedkeys_ops(tostring(keys or ""))
    mode = tostring(mode or "")
    local remap = true
    if mode:find("n", 1, true) ~= nil then
        remap = false
    end
    if mode:find("m", 1, true) ~= nil then
        remap = true
    end
    for i = 1, #ops do
        if ops[i].kind == "keys" then
            ops[i].noremap = not remap
        end
    end
    local prepend = mode:find("i", 1, true) ~= nil
    local immediate = mode:find("x", 1, true) ~= nil

    enqueue_feedkeys(ops, prepend)

    if immediate or not prepend then
        if feedkeys_flush_timer ~= nil then
            Event.CancelTimer(feedkeys_flush_timer)
            feedkeys_flush_timer = nil
        end
        flush_feedkeys_queue()
    else
        schedule_feedkeys_flush()
    end
end

function api.nvim_select_popupmenu_item(item, insert, finish, opts)
    PopupMenu.select(item, insert, finish)
end

function api.nvim__complete_set(_index, _opts)
    -- TODO: Preview/info popup for builtin completion.
    return {}
end

function api.nvim_win_hide(window)
    local win = win_for_id(window)
    if not win then
        return
    end
    return api.nvim_win_close(win.winnr, true)
end

function api.nvim_get_vvar(name)
    if type(name) ~= "string" or name == "" then
        error("nvim_get_vvar: name must be non-empty string")
    end
    return scopes._v[name]
end

function api.nvim_set_vvar(name, value)
    if type(name) ~= "string" or name == "" then
        error("nvim_set_vvar: name must be non-empty string")
    end
    scopes._v[name] = value
end

function api.nvim_command(command)
    local line = tostring(command or "")
    if line == "" then
        return
    end
    local rv = api.nvim_exec2(line, { output = false })
    return rv.output or ""
end

local _term_next_chan_id = 1
local _term_channels = {}

function api.nvim_open_term(buffer, opts)
    local bufnr = (buffer == 0) and windows[curwin].buffer.bufnr or buffer
    local buf = buf_for_bufnr(bufnr)
    assert(buf)

    local chan = _term_next_chan_id
    _term_next_chan_id = _term_next_chan_id + 1
    _term_channels[chan] = { bufnr = buf.bufnr, on_input = opts and opts.on_input }
    return chan
end

function api.nvim_chan_send(chan, data)
    local entry = _term_channels[chan]
    if not entry then
        return 0
    end
    local buf = buffers[entry.bufnr]
    if not buf then
        return 0
    end
    local text = tostring(data or "")
    buf:ensure_loaded(true)
    local buflines = buf:lines_ref(true)
    if #buflines == 1 and buflines[1] == "" then
        buflines[1] = nil
    end
    for line in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
        buflines[#buflines + 1] = line
    end
    if #buflines == 0 then
        buflines[1] = ""
    end
    what_redraw["all"] = true
    need_redraw = true
    return #text
end

-- TODO: returning non-shell, non-error output if `output` is true
function api.nvim_cmd(cmd, opts)
    opts = opts or {}
    local name = tostring((cmd and (cmd.cmd or cmd.command)) or "")
    if name == "" then
        error("nvim_cmd: missing command")
    end
    local head = name .. ((cmd and cmd.bang) and "!" or "")

    local argstr = ""
    if cmd and cmd.args ~= nil then
        if type(cmd.args) == "table" then
            argstr = table.concat(cmd.args, " ")
        else
            argstr = tostring(cmd.args)
        end
    end

    local script = (argstr ~= "") and (head .. " " .. argstr) or head
    local rv = api.nvim_exec2(script, { output = not not opts.output })
    if opts.output then
        return rv.output or ""
    end
    return ""
end

function api.nvim_get_option(name)
    return options.get(name, windows[curwin], windows[curwin].buffer)
end

function api.nvim_buf_line_count(bufnr)
    local buf = buf_for_bufnr(bufnr)
    assert(buf)

    return buf:line_count(false)
end

function api.nvim_buf_get_lines(bufnr, start, _end, strict_indexing)
    local buf = buf_for_bufnr(bufnr)
    assert(buf)

    local line_count = buf:line_count(false)

    -- Normalize negatives relative to end+1 (0-based)
    local s = start >= 0 and start or (line_count + 1 + start)
    local e = _end >= 0 and _end or (line_count + 1 + _end)

    if strict_indexing then
        if s < 0 or s > line_count or e < 0 or e > line_count then
            error("Index out of bounds")
        end
    else
        s = math.max(0, math.min(s, line_count))
        e = math.max(0, math.min(e, line_count))
    end

    if s >= e then
        return {}
    end

    local start1 = s + 1
    local end1 = e

    local out = {}
    for i = start1, end1 do
        out[#out + 1] = buf:get_line(i, false)
    end

    return out
end

-- Attach a metatable that logs missing api keys for easier diagnostics.
-- Accessing an unknown member logs and returns a function that throws when called.
return setmetatable(api, {
    __index = function(_, k)
        LOG_INTERNAL("missing", "vim.api.%s not implemented", tostring(k))
        error("vim.api." .. tostring(k) .. " not implemented")
    end
})
