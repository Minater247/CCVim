local api = {}

local VimXpr = loadModule("vim.lib.excmd.vimxpr")
local Buffer = loadModule("vim.layout.buffer")
local Window = loadModule("vim.layout.window")
local Command = loadModule("vim.lib.command")
local Key = loadModule("vim.lib.key")
local Highlight = loadModule("vim.lib.highlight")
local ExMsg = loadModule("vim.lib.excmd.exmsg")
local Runtime = loadModule("vim.lib.excmd.runtime")
local scopes = loadModule("vim.lib.luaapi.scopes")
local AutoCmd = loadModule("vim.lib.autocmd")
local Fn = loadModule("vim.lib.luaapi.fn")
local ScriptSource
local Error = loadModule("vim.lib.error")

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

local function normalize_color_value(val)
    if val == nil or type(val) == "number" or val == "fg" or val == "bg" then
        return val
    end
    if type(val) == "string" then
        local hex = val:match("^#(%x%x%x%x%x%x)$")
        if hex then return tonumber("0x" .. hex) end

        local alias = COLOR_ALIASES[string.lower(val)]
        if alias then
            return rgb_for_palette_index(alias)
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
        tabpages[curtp]:WinSplit(config.win or 0, newwin, false)
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

-- TODO: error handling, detecting vim9
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
    local buf = Buffer(listed, scratch)
    return buf.bufnr
end

function api.nvim_buf_set_lines(buffer, start, end_, strict_indexing, replacement)
    local buf = buf_for_bufnr(buffer)
    assert(buf)

    buf:set_lines(start, end_, strict_indexing, replacement)
end

-- TODO: Translate from string to sequence
function api.nvim_buf_set_keymap(buffer, mode, lhs, rhs, opts)
    opts = opts or {}

    local buf = buf_for_bufnr(buffer)
    assert(buf)

    lhs = Key.strtoseq(lhs)

    if opts.callback then
        ScriptSource = ScriptSource or loadModule("vim.lib.scriptsource")
        local cb = ScriptSource.wrap(nil, opts.callback)
        Command.map_callback(mode, lhs, cb, { buffer = buf })
    else
        rhs = Key.strtoseq(rhs)
        if opts.noremap then
            Command.noremap_keys(mode, lhs, rhs, { buffer = buf })
        else
            Command.remap_keys(mode, lhs, rhs, { buffer = buf })
        end
    end
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
    local RuntimePath = loadModule("vim.lib.runtimepath")
    return RuntimePath.get_search_list()
end

function api.nvim_get_runtime_file(path, all)
    local RuntimePath = loadModule("vim.lib.runtimepath")
    local Filesystem = loadModule("vim.lib.filesystem")

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
    local hl = Highlight.For(name)

    return {
        foreground = colors.packRGB(term.getPaletteColor(hl[1])),
        background = colors.packRGB(term.getPaletteColor(hl[2])),
    }
end

function api.nvim_set_option_value(name, value, opts)
    opts = opts or {}

    local win, buf
    if opts.win then
        win = win_for_id(opts.win)
    else
        win = windows[curwin]
    end
    if opts.buf then
        buf = buffers[opts.buf]
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
    if opts.win then
        win = win_for_id(opts.win)
    else
        win = windows[curwin]
    end
    if opts.buf then
        buf = buffers[opts.buf]
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

    local hl = Highlight.For(name, ns)
    local out = {}
    if hl[1] then
        local r, g, b = term.getPaletteColor(hl[1])
        out.fg = colors.packRGB(r, g, b)
    end
    if hl[2] then
        local r, g, b = term.getPaletteColor(hl[2])
        out.bg = colors.packRGB(r, g, b)
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

function api.nvim_create_autocmd(event, opts)
    opts = opts or {}

    if type(event) == "string" then
        event = { event }
    end

    if opts.pattern then
        if type(opts.pattern) == "string" then
            opts.pattern = { opts.pattern }
        end
    end

    local cb = opts.callback and (ScriptSource or loadModule("vim.lib.scriptsource")).wrap(nil, opts.callback) or nil
    ScriptSource = ScriptSource or loadModule("vim.lib.scriptsource")
    local script_ctx = ScriptSource.CurrentContext()

    return AutoCmd.CreateAutocommand(event, opts.pattern, cb, opts.command, opts.group, opts.once, opts
        .nested, opts.desc, script_ctx)
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
        local wrap = (ScriptSource or loadModule("vim.lib.scriptsource")).wrap
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
                line1 = windows[curwin] and windows[curwin].cursory or 1,
                line2 = windows[curwin] and windows[curwin].cursory or 1,
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

function api.nvim_buf_set_name(bufnr, name)
    local buf = buf_for_bufnr(bufnr)
    assert(buf)

    buf.name = name
end

-- TODO: Proper swap file and load/store semantics
function api.nvim_buf_is_loaded(bufnr)
    local buf = buf_for_bufnr(bufnr)

    return buf.lines ~= nil
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

    return #buf.lines
end

function api.nvim_buf_get_lines(bufnr, start, _end, strict_indexing)
    local buf = buf_for_bufnr(bufnr)
    assert(buf)

    local line_count = #buf.lines

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
        out[#out + 1] = buf.lines[i]
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
