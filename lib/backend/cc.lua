--[[
    ComputerCraft backend for lib/screen.lua.

    All CC-specific APIs (term.*, window.create, colors.*, keys, fs, os.*) are
    confined here. The rest of the program sees only RGB integers and the grid
    protocol defined in lib/screen.lua.

    Slot numbering: 0–15.
    Palette APIs use the engine's color ids for each slot, read from the
    `colors.*` table at startup. Text/background color APIs also use those ids.
]]

local CC = {}
CC.kind = "cc"
local cc_shell = shell
local cc_term = term
local cc_window = window
local cc_os = select(1, os)
local cc_io = io
local cc_fs = fs
local stdin_counter = 0
local cc_pull_event_raw = cc_os.pullEventRaw
local cc_global_table = _ENV
local cc_host_globals
local dispatch_process_event
local Utf8
local Color
local RuntimeScope

local UTF_REPLACEMENTS = {
    [0x2713] = { char = "v" },
    [0x2714] = { char = "v" },
    [0x2611] = { char = "v" },
    [0x2715] = { char = "x" },
    [0x2717] = { char = "x" },
    [0x2718] = { char = "x" },
    [0x00D7] = { char = "x" },
    [0x2191] = { char = "\x18" },
    [0x2193] = { char = "\x19" },
    [0x2190] = { char = "\x1b" },
    [0x2192] = { char = "\x1a" },
    [0xE0B0] = { char = string.char(0x94) },
    [0xE0B2] = { char = string.char(0x97), swap = true },
    [0xE0B4] = { char = string.char(0x84) },
    [0xE0B6] = { char = string.char(0x88) },
    [0xE0B8] = { char = string.char(0x87), swap = true },
    [0xE0BA] = { char = string.char(0x8B), swap = true },
    [0x2518] = { char = "/" },
    [0x2500] = { char = "-" },
    [0x2514] = { char = "\\" },
    [0x2502] = { char = "|" },
    [0x2510] = { char = "\\" },
    [0x250C] = { char = "/" },
    [0x2019] = { char = "'" },
    [0x201C] = { char = "\"" },
    [0x25CF] = { char = string.char(0x07) },
}

-- =========================================================================
-- Default CC palette (factory RGB for each slot 0-15)
-- =========================================================================

local DEFAULT_SLOT_RGB = {
    [0]  = 0xF0F0F0,  -- white
    [1]  = 0xF2B233,  -- orange
    [2]  = 0xE57FD8,  -- magenta
    [3]  = 0x99B2F2,  -- lightBlue
    [4]  = 0xDEDE6C,  -- yellow
    [5]  = 0x7FCC19,  -- lime
    [6]  = 0xF2B2CC,  -- pink
    [7]  = 0x4C4C4C,  -- gray
    [8]  = 0x999999,  -- lightGray
    [9]  = 0x4C99B2,  -- cyan
    [10] = 0xB266E5,  -- purple
    [11] = 0x3366CC,  -- blue
    [12] = 0x7F664C,  -- brown
    [13] = 0x57A64E,  -- green
    [14] = 0xCC4C4C,  -- red
    [15] = 0x111111,  -- black
}

local SLOT_COLOR = {
    [0]  = colors.white,
    [1]  = colors.orange,
    [2]  = colors.magenta,
    [3]  = colors.lightBlue,
    [4]  = colors.yellow,
    [5]  = colors.lime,
    [6]  = colors.pink,
    [7]  = colors.gray,
    [8]  = colors.lightGray,
    [9]  = colors.cyan,
    [10] = colors.purple,
    [11] = colors.blue,
    [12] = colors.brown,
    [13] = colors.green,
    [14] = colors.red,
    [15] = colors.black,
}

local function pack_rgb(r, g, b)
    return r * 65536 + g * 256 + b
end

local function unpack_rgb(rgb)
    if Color then
        return Color.unpack(rgb)
    end
    return math.floor(rgb / 65536) % 256, math.floor(rgb / 256) % 256, rgb % 256
end

local function current_term_slot_rgb(slot)
    local r, g, b = term.getPaletteColor(SLOT_COLOR[slot])
    return pack_rgb(
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5)
    )
end

-- Live palette: slot → packed RGB (may be reprogrammed by colorschemes)
local _palette = {}
for s = 0, 15 do _palette[s] = current_term_slot_rgb(s) end
local _default_fg_rgb = _palette[0]
local _default_bg_rgb = _palette[15]
local _grids = {}

-- =========================================================================
-- Color math (OKLAB perceptual distance for RGB → nearest slot mapping)
-- =========================================================================

local function ensure_grid_state(grid, w, h)
    local state = _grids[grid]
    if state and state.w == w and state.h == h then
        return state
    end
    state = { w = w, h = h, rows = {} }
    for row = 0, h - 1 do
        state.rows[row] = {}
        for col = 0, w - 1 do
            state.rows[row][col] = { " ", nil, nil }
        end
    end
    _grids[grid] = state
    return state
end

function CC.normalize_codepoint(cp)
    if cp >= 32 and cp <= 127 then
        return Utf8.char_for_codepoint(cp), false
    end

    local replacement = UTF_REPLACEMENTS[cp]
    if replacement then
        return replacement.char, replacement.swap == true
    end

    RuntimeScope.LOG_DEBUG("UNKNOWN CC CODEPOINT: 0x%X", cp)
    return "?", false
end

function CC.on_load_module_ready(scope)
    RuntimeScope = scope
    Utf8 = scope.loadModule("lib.utf8")
    Color = scope.loadModule("lib.color")
end

function CC.set_host_globals(globals)
    cc_host_globals = globals
end

local function shell_path_to_abs(path)
    path = tostring(path or "")
    if path == "" then
        return "/"
    end
    if path:sub(1, 1) ~= "/" then
        return "/" .. path
    end
    return path
end

local function xterm256_to_rgb(idx)
    return Color.xterm256(idx, DEFAULT_SLOT_RGB[15])
end

-- =========================================================================
-- RGB → nearest slot (cached; invalidated when palette changes)
-- =========================================================================

local _slot_cache = {}

local function invalidate_slot_cache() _slot_cache = {} end

local function rgb_to_slot(rgb)
    local cached = _slot_cache[rgb]
    if cached then return cached end

    local best_slot, best_dist = 0, math.huge
    for s = 0, 15 do
        local d = Color.distance(rgb, _palette[s])
        if d < best_dist then
            best_dist = d
            best_slot = s
        end
    end
    _slot_cache[rgb] = best_slot
    return best_slot
end

-- Hex char for a slot 0-15
local SLOT_HEX = {}
for s = 0, 15 do SLOT_HEX[s] = string.format("%x", s) end

-- =========================================================================
-- Highlight registry (hl_id → {fg_slot, bg_slot})
-- =========================================================================

local _hl = {}   -- [id] = {fg=slot, bg=slot}

function CC.hl_define(id, attrs)
    _hl[id] = attrs
end

function CC.default_colors_set(rgb_fg, rgb_bg, _rgb_sp, _cterm_fg, _cterm_bg)
    _default_fg_rgb = rgb_fg or _default_fg_rgb
    _default_bg_rgb = rgb_bg or _default_bg_rgb
end

-- =========================================================================
-- Double-buffer state
-- =========================================================================

local _backwin   = nil
local _prevterm  = nil
local _parent    = nil

local function render_row_range(state, row, left, right)
    if not _backwin or row < 0 or row >= state.h then
        return
    end
    if right <= left then
        return
    end

    local text = {}
    local fg = {}
    local bg = {}
    for col = left, right - 1 do
        local cell = state.rows[row][col]
        local ch = cell[1]
        local fg_slot = cell[2]
        local bg_slot = cell[3]
        text[#text + 1] = ch == "" and " " or ch
        fg[#fg + 1] = SLOT_HEX[fg_slot or rgb_to_slot(_default_fg_rgb)]
        bg[#bg + 1] = SLOT_HEX[bg_slot or rgb_to_slot(_default_bg_rgb)]
    end
    _backwin.setCursorPos(left + 1, row + 1)
    _backwin.blit(table.concat(text), table.concat(fg), table.concat(bg))
end

-- =========================================================================
-- Backend interface
-- =========================================================================

function CC.begin_frame()
    local parent = term.current()
    local w, h = term.getSize()
    ensure_grid_state(1, w, h)
    if _parent ~= parent or not _backwin then
        _parent = parent
        _backwin = window.create(parent, 1, 1, w, h, false)
    elseif _backwin.reposition then
        _backwin.reposition(1, 1, w, h)
    end
    _backwin.setVisible(false)
    _prevterm = term.redirect(_backwin)
    -- Apply current palette to the back buffer
    for s = 0, 15 do
        local r, g, b = unpack_rgb(_palette[s])
        _backwin.setPaletteColor(SLOT_COLOR[s], r/255, g/255, b/255)
    end
end

function CC.end_frame()
    term.redirect(_prevterm)
    _backwin.setVisible(true)
end

function CC.flush()
    CC.end_frame()
end

function CC.grid_line(grid, row, col, cells, _wrap)
    local width = grid == 1 and term.getSize() or 1
    local height = grid == 1 and select(2, term.getSize()) or 1
    local state = ensure_grid_state(grid, width, height)
    local cx = col + 1
    local cy = row + 1
    local last_fg_slot = rgb_to_slot(_default_fg_rgb)
    local last_bg_slot = rgb_to_slot(_default_bg_rgb)

    local i = 1
    while i <= #cells do
        local cell = cells[i]
        local ch     = cell[1]
        local hl_id  = cell[2]
        local rep    = cell[3] or 1
        local swap   = cell[4] == true

        if hl_id ~= nil then
            if hl_id == 0 then
                last_fg_slot = rgb_to_slot(_default_fg_rgb)
                last_bg_slot = rgb_to_slot(_default_bg_rgb)
            else
                local attrs = _hl[hl_id]
                if attrs then
                    local fg = attrs.foreground
                    local bg = attrs.background
                    if fg == nil and attrs.cterm_foreground ~= nil then
                        fg = xterm256_to_rgb(attrs.cterm_foreground)
                    end
                    if bg == nil and attrs.cterm_background ~= nil then
                        bg = xterm256_to_rgb(attrs.cterm_background)
                    end
                    if fg == nil then fg = _default_fg_rgb end
                    if bg == nil then bg = _default_bg_rgb end
                    if attrs.reverse then fg, bg = bg, fg end
                    last_fg_slot = rgb_to_slot(fg)
                    last_bg_slot = rgb_to_slot(bg)
                end
            end
        end

        local cell_fg_slot = last_fg_slot
        local cell_bg_slot = last_bg_slot
        if swap then
            cell_fg_slot, cell_bg_slot = cell_bg_slot, cell_fg_slot
        end

        for offset = 0, rep - 1 do
            if state.rows[row] and state.rows[row][col + offset] then
                state.rows[row][col + offset] = { ch, cell_fg_slot, cell_bg_slot }
            end
        end

        if grid == 1 and _backwin then
            _backwin.setCursorPos(cx, cy)
            local text   = string.rep(ch == "" and " " or ch, rep)
            local fg_str = string.rep(SLOT_HEX[cell_fg_slot], rep)
            local bg_str = string.rep(SLOT_HEX[cell_bg_slot], rep)
            _backwin.blit(text, fg_str, bg_str)
        end

        cx = cx + rep
        i  = i + 1
    end
end

function CC.grid_cursor_goto(_grid, row, col)
    term.setCursorPos(col + 1, row + 1)
end

function CC.grid_clear(grid)
    local w, h = term.getSize()
    ensure_grid_state(grid, w, h)
    for row = 0, h - 1 do
        for col = 0, w - 1 do
            _grids[grid].rows[row][col] = { " ", nil, nil }
        end
    end
    if grid == 1 and _backwin then
        _backwin.clear()
    elseif grid == 1 then
        term.clear()
    end
end

function CC.grid_destroy(grid)
    _grids[grid] = nil
end

function CC.size()
    return term.getSize()
end

function CC.color_depth()
    return "16"
end

function CC.supports_palette()
    return true
end

function CC.grid_resize(grid, w, h)
    ensure_grid_state(grid, w, h)
    if grid == 1 and _backwin and _backwin.reposition then
        _backwin.reposition(1, 1, w, h)
    end
end

function CC.grid_scroll(grid, top, bot, left, right, rows, cols)
    cols = cols or 0
    local state = _grids[grid]
    if not state or (rows == 0 and cols == 0) then
        return
    end

    local snapshot = {}
    for row = top, bot - 1 do
        snapshot[row] = {}
        for col = left, right - 1 do
            local cell = state.rows[row][col]
            snapshot[row][col] = { cell[1], cell[2], cell[3] }
        end
    end

    for row = top, bot - 1 do
        for col = left, right - 1 do
            local src_row = row + rows
            local src_col = col + cols
            local in_bounds = src_row >= top and src_row < bot and src_col >= left and src_col < right
            if in_bounds then
                local cell = snapshot[src_row][src_col]
                state.rows[row][col] = { cell[1], cell[2], cell[3] }
            else
                state.rows[row][col] = { " ", nil, nil }
            end
        end
    end

    if grid == 1 and _backwin then
        for row = top, bot - 1 do
            render_row_range(state, row, left, right)
        end
    end
end

function CC.set_palette_slot(slot, r, g, b)
    _palette[slot] = (r * 65536) + (g * 256) + b
    invalidate_slot_cache()
    term.setPaletteColor(SLOT_COLOR[slot], r/255, g/255, b/255)
end

function CC.get_palette_slot(slot)
    local rgb = _palette[slot]
    return unpack_rgb(rgb)
end

function CC.capture_palette()
    local captured = {}
    for s = 0, 15 do
        local r, g, b = term.getPaletteColor(SLOT_COLOR[s])
        -- CC returns 0-1 floats
        captured[s] = {
            math.floor(r * 255 + 0.5),
            math.floor(g * 255 + 0.5),
            math.floor(b * 255 + 0.5),
        }
    end
    return captured
end

function CC.reset(original_palette)
    if original_palette then
        for s = 0, 15 do
            local c = original_palette[s]
            if c then
                term.setPaletteColor(SLOT_COLOR[s], c[1]/255, c[2]/255, c[3]/255)
            end
        end
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

function CC.pull_event(filter)
    while true do
        local ev = table.pack(cc_pull_event_raw())
        if dispatch_process_event then
            dispatch_process_event(ev)
        end
        if ev[1] == "terminate" then
            error("Terminated", 0)
        end
        local matches = filter == nil or filter == ev[1]
        if ev[1] == "mouse_scroll" then
            local delta = tonumber(ev[2]) or 0
            if delta > 0 then
                ev[2] = "down"
                if matches then
                    return table.unpack(ev, 1, ev.n)
                end
            end
            if delta < 0 then
                ev[2] = "up"
                if matches then
                    return table.unpack(ev, 1, ev.n)
                end
            end
        elseif matches then
            return table.unpack(ev, 1, ev.n)
        end
    end
end

function CC.start_timer(t)
    return os.startTimer(t)
end

function CC.cancel_timer(id)
    os.cancelTimer(id)
end

function CC.get_epoch()
    return os.epoch("utc")
end

function CC.cwd()
    return shell_path_to_abs(shell.dir())
end

function CC.chdir(path)
    local dir = tostring(path)
    if dir == "/" then
        shell.setDir("")
        return
    end
    shell.setDir(dir:sub(2))
end

function CC.resolve_path(path)
    return shell_path_to_abs(shell.resolve(path))
end

function CC.running_program()
    return shell.getRunningProgram()
end

function CC.list_commands()
    local commands = cc_shell.programs(false)
    for name in pairs(cc_shell.aliases()) do
        commands[#commands + 1] = name
    end
    local out, seen = {}, {}
    for i = 1, #commands do
        local name = tostring(commands[i])
        if name ~= "" and not seen[name] then
            seen[name] = true
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

function CC.list_locales()
    return {}
end

function CC.list_users()
    return {}
end

local next_process_pid = 0

local function process_event()
    return RuntimeScope.loadModule("lib.event")
end

local function fake_userdata()
    return RuntimeScope.loadModule("lib.luaapi.fakeuserdata")
end

local function copy_globals(source)
    local copy = {}
    for name, value in pairs(source) do
        copy[name] = value
    end
    copy._G = copy
    copy._ENV = copy
    setmetatable(copy, getmetatable(source))
    return copy
end

local function process_globals()
    if not cc_host_globals then
        cc_host_globals = copy_globals(cc_global_table)
    end
    local env = setmetatable({}, { __index = cc_host_globals })
    env._G = env
    env._ENV = env

    local child_os = {}
    local base_os = cc_host_globals.os or cc_os
    for name, value in pairs(base_os) do
        child_os[name] = value
    end
    setmetatable(child_os, { __index = base_os })

    local function pull_event(raw, filter)
        local event = table.pack(coroutine.yield(filter))
        if event[1] == "terminate" and not raw then
            error("Terminated", 0)
        end
        return table.unpack(event, 1, event.n)
    end

    child_os.pullEvent = function(filter)
        return pull_event(false, filter)
    end
    child_os.pullEventRaw = function(filter)
        return pull_event(true, filter)
    end
    child_os.sleep = function(timeout)
        if timeout ~= nil and type(timeout) ~= "number" then
            error("bad argument #1 (number expected, got " .. type(timeout) .. ")", 2)
        end
        timeout = timeout or 0
        local timer = cc_os.startTimer(timeout)
        repeat
            local _, timer_id = child_os.pullEvent("timer")
        until timer_id == timer
    end

    env.os = child_os
    env.sleep = child_os.sleep
    return env
end

local pipe_methods = {}

function pipe_methods:read_start(callback)
    local state = fake_userdata().state(self)
    if state._closed then return nil, "EINVAL: pipe is closing" end
    state._read_callback = callback
    state._reading = true
    return 0
end

function pipe_methods:read_stop()
    local state = fake_userdata().state(self)
    state._reading = false
    return 0
end

function pipe_methods:write(data, callback)
    local state = fake_userdata().state(self)
    if state._closed then return nil, "EPIPE: pipe is closing" end
    if type(data) == "table" then
        for i = 1, #data do
            state._write[#state._write + 1] = tostring(data[i])
        end
    else
        state._write[#state._write + 1] = tostring(data or "")
    end
    if callback then callback(nil) end
    return 0
end

function pipe_methods:shutdown(callback)
    local state = fake_userdata().state(self)
    state._shutdown = true
    if callback then callback(nil) end
    return 0
end

function pipe_methods:close(callback)
    local state = fake_userdata().state(self)
    state._closed = true
    state._reading = false
    if callback then callback() end
end

function pipe_methods:is_active()
    local state = fake_userdata().state(self)
    return state._reading and not state._closed
end

function pipe_methods:is_closing()
    return fake_userdata().state(self)._closed
end

function CC.new_pipe(_ipc)
    return fake_userdata().new("uv_pipe_t", {
        _closed = false,
        _reading = false,
        _shutdown = false,
        _write = {},
    }, pipe_methods)
end

local process_methods = {}
local processes = {}

local function emit_pipe(pipe, data)
    if pipe == nil then return end
    local state = fake_userdata().state(pipe)
    if not state or state._closed or not state._reading then return end
    if data ~= nil and data ~= "" then
        state._read_callback(nil, data)
    end
    if not state._closed and state._reading then
        state._read_callback(nil, nil)
    end
end

local function prepare_input(input)
    if input == nil or not cc_io or not cc_io.input then
        return cc_io and cc_io.input and cc_io.input() or nil
    end

    if type(input) == "table" then
        input = table.concat(input, "\n") .. "\n"
    end
    input = tostring(input)
    if cc_io.tmpfile then
        local file = assert(cc_io.tmpfile())
        file:write(input)
        file:seek("set", 0)
        return file
    end

    stdin_counter = stdin_counter + 1
    cc_fs.makeDir("/tmp")
    local path = "/tmp/ccvim-stdin-" .. tostring(cc_os.epoch("utc")) .. "-" .. stdin_counter
    local writer = assert(cc_io.open(path, "w"))
    writer:write(input)
    writer:close()
    local file = assert(cc_io.open(path, "r"))
    return file, path
end

local function capture_terminal()
    local parent = cc_term.current()
    local width, height = parent.getSize()
    local capture = cc_window.create(parent, 1, 1, width, height, false)
    local history = {}
    local capture_scroll = capture.scroll
    capture.scroll = function(amount)
        amount = math.max(0, math.min(height, amount))
        for y = 1, amount do
            history[#history + 1] = capture.getLine(y):gsub("%s+$", "")
        end
        return capture_scroll(amount)
    end
    local function output()
        local lines = {}
        for i = 1, #history do lines[i] = history[i] end
        for y = 1, height do
            lines[#lines + 1] = capture.getLine(y):gsub("%s+$", "")
        end
        while #lines > 0 and lines[#lines] == "" do
            lines[#lines] = nil
        end
        return table.concat(lines, "\n")
    end
    return capture, output
end

local function restore_global(name, value)
    rawset(cc_global_table, name, value)
end

local function resume_in_context(state, event)
    local editor_term = cc_term.current()
    local editor_dir = cc_shell.dir()
    local editor_input = cc_io and cc_io.input and cc_io.input() or nil
    local editor_output = cc_io and cc_io.output and cc_io.output() or nil
    local editor_global = rawget(cc_global_table, "_G")
    local editor_os = rawget(cc_global_table, "os")
    local editor_sleep = rawget(cc_global_table, "sleep")

    rawset(cc_global_table, "_G", state._globals)
    rawset(cc_global_table, "os", state._globals.os)
    rawset(cc_global_table, "sleep", state._globals.sleep)

    local setup_ok, setup_err = pcall(function()
        cc_shell.setDir(state._cwd)
        cc_term.redirect(state._term)
        if cc_io and cc_io.input and state._input then cc_io.input(state._input) end
        if cc_io and cc_io.output and state._output then cc_io.output(state._output) end
    end)

    local resumed
    if setup_ok then
        if event then
            resumed = table.pack(coroutine.resume(state._coroutine, table.unpack(event, 1, event.n)))
        else
            resumed = table.pack(coroutine.resume(state._coroutine))
        end
        state._term = cc_term.current()
        state._cwd = cc_shell.dir()
        if cc_io and cc_io.input then state._input = cc_io.input() end
        if cc_io and cc_io.output then state._output = cc_io.output() end
    else
        resumed = table.pack(false, setup_err)
    end

    if cc_io and cc_io.input and editor_input then pcall(cc_io.input, editor_input) end
    if cc_io and cc_io.output and editor_output then pcall(cc_io.output, editor_output) end
    pcall(cc_term.redirect, editor_term)
    pcall(cc_shell.setDir, editor_dir)
    restore_global("_G", editor_global)
    restore_global("os", editor_os)
    restore_global("sleep", editor_sleep)
    return resumed
end

local function finish_process(state, ran, runtime_error, signal)
    if state._finished then return end
    state._finished = true
    state._active = false
    state._signal = signal or 0
    processes[state._pid] = nil

    if state._input_owned and state._input then pcall(state._input.close, state._input) end
    if state._input_path then pcall(cc_fs.delete, state._input_path) end

    local result = {
        code = runtime_error and 1 or (ran == false and 1 or 0),
        signal = state._signal,
        stdout = state._capture_output(),
        stderr = runtime_error and tostring(runtime_error) or "",
    }
    state._result = result

    local stdio = state._stdio or {}
    emit_pipe(stdio[2], result.stdout)
    emit_pipe(stdio[3], result.stderr)
    if state._on_exit then state._on_exit(result.code, result.signal) end
end

local function resume_process(state, event)
    if not state._active or state._finished then return end
    local resumed = resume_in_context(state, event)
    if not resumed[1] then
        local message = tostring(resumed[2])
        if debug and debug.traceback then
            message = debug.traceback(state._coroutine, message)
        end
        finish_process(state, nil, message, 0)
    elseif coroutine.status(state._coroutine) == "dead" then
        finish_process(state, resumed[2], nil, 0)
    else
        state._filter = resumed[2]
    end
end

local function create_process(command, opts, on_exit)
    opts = opts or {}
    next_process_pid = next_process_pid + 1
    local capture, output = capture_terminal()
    local initial_input, input_path = prepare_input(opts.input)
    local state = {
        _pid = next_process_pid,
        _active = true,
        _closed = false,
        _on_exit = on_exit,
        _stdio = opts.stdio,
        _globals = process_globals(),
        _cwd = opts.cwd and tostring(opts.cwd):gsub("^/", "") or cc_shell.dir(),
        _term = capture,
        _capture_output = output,
        _input = initial_input,
        _input_owned = opts.input ~= nil,
        _input_path = input_path,
        _output = cc_io and cc_io.output and cc_io.output() or nil,
    }
    state._coroutine = coroutine.create(function()
        if type(command) == "string" then
            return cc_shell.run(command)
        end
        return cc_shell.execute(command[1], table.unpack(command, 2))
    end)
    processes[state._pid] = state
    return state
end

dispatch_process_event = function(event)
    local ready
    for _, state in pairs(processes) do
        if state._active and not state._timer and (state._filter == nil or state._filter == event[1]) then
            ready = ready or {}
            ready[#ready + 1] = state
        end
    end
    if not ready then return end
    for i = 1, #ready do
        resume_process(ready[i], event)
    end
end

function process_methods:close(callback)
    local state = fake_userdata().state(self)
    state._closed = true
    if not state._active then processes[state._pid] = nil end
    if callback then callback() end
end

function process_methods:is_active()
    local state = fake_userdata().state(self)
    return state._active and not state._closed
end

function process_methods:is_closing()
    return fake_userdata().state(self)._closed
end

function process_methods:kill(signal)
    local state = fake_userdata().state(self)
    if state._closed or not state._active then return nil, "ESRCH: no such process" end
    local killed = tonumber(signal) or 15
    if state._timer then
        process_event().CancelTimer(state._timer)
        state._timer = nil
    end
    finish_process(state, true, nil, killed)
    return 0
end

function CC.spawn(path, opts, on_exit)
    opts = opts or {}
    if type(path) ~= "string" or path == "" then
        return nil, "EINVAL: empty process path"
    end
    if type(on_exit) ~= "function" then
        return nil, "EINVAL: exit callback required"
    end

    local command = { path }
    for i = 1, #(opts.args or {}) do
        command[#command + 1] = tostring(opts.args[i])
    end
    local state = create_process(command, opts, on_exit)
    local handle = fake_userdata().new("uv_process_t", state, process_methods)
    state._timer = process_event().StartTimer(0, function()
        state._timer = nil
        if state._closed or state._finished then return end
        resume_process(state)
    end)
    return handle, state._pid
end

function CC.system(command, opts)
    opts = opts or {}
    if (type(command) ~= "string" and type(command) ~= "table") or #command == 0 then
        return { code = 1, signal = 0, stdout = "", stderr = "empty command" }
    end

    local state = create_process(command, opts)
    resume_process(state)
    while state._active do
        local event = table.pack(CC.pull_event())
        if RuntimeScope then
            local Event = process_event()
            if Event and Event.ProcessEvent then
                Event.ProcessEvent(event)
            end
        end
    end
    return state._result
end

CC.keys = keys
CC.fs   = fs

return CC
