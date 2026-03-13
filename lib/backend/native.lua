--[[
    Native Lua backend for lib/screen.lua.

    Renders directly to a real ANSI terminal via io.write / ANSI escape codes.
    Filesystem uses LuaFileSystem (lfs) + io.open.
    Input uses raw-mode stdin with ANSI escape sequence parsing and
    xterm SGR (1006) extended mouse protocol.

    This backend does NOT implement or emulate any ComputerCraft API.
    It is a different implementation of the same backend interface over
    standard Lua and OS primitives.
]]

local Native = {}
local uv = require("luv")
local Utf8

-- =========================================================================
-- Helpers
-- =========================================================================

local function write(s) io.write(s) end
local function flush() io.flush() end

local function esc(s) return "\27[" .. s end
local function unpack_rgb(rgb)
    return math.floor(rgb / 65536) % 256, math.floor(rgb / 256) % 256, rgb % 256
end

local function epoch_ms()
    return math.floor(uv.hrtime() / 1000000)
end

-- =========================================================================
-- Terminal size
-- =========================================================================

local function detect_size()
    -- Try stty
    local handle = io.popen("stty size 2>/dev/null", "r")
    if handle then
        local out = handle:read("*l")
        handle:close()
        if out then
            local h, w = out:match("(%d+)%s+(%d+)")
            if w and h then return tonumber(w), tonumber(h) end
        end
    end
    -- Fallback
    return 80, 24
end

-- =========================================================================
-- Color depth detection
-- =========================================================================

local _color_depth = nil

local function detect_color_depth()
    local ct = os.getenv("COLORTERM") or ""
    if ct == "truecolor" or ct == "24bit" then return "rgb" end

    local handle = io.popen("tput colors 2>/dev/null", "r")
    if handle then
        local out = handle:read("*l")
        handle:close()
        local colors = tonumber(out)
        if colors then
            if colors >= 256 then return "256" end
            if colors >= 8 then return "16" end
            if colors > 0 then return "0" end
        end
    end

    local term_env = os.getenv("TERM") or ""
    if term_env:find("256color") then return "256" end
    if term_env ~= "" and term_env ~= "dumb" and term_env ~= "vt100" then
        return "16"
    end
    return "0"
end

-- =========================================================================
-- ANSI 16-color mapping (slot 0-15 → ANSI SGR codes)
-- The default RGB values below match the CC default palette so that
-- a native terminal without truecolor shows visually similar colors
-- to CraftOS-PC. These are also the colors returned by get_palette_slot.
-- =========================================================================

-- Standard ANSI 16 colors: indices 0-7 are standard, 8-15 are bright.
-- We map CC slots to nearest ANSI color by hue/brightness.
local SLOT_TO_ANSI_FG = {
    [0]  = 97,   -- white       → bright white
    [1]  = 33,   -- orange      → yellow (closest ANSI)
    [2]  = 95,   -- magenta     → bright magenta
    [3]  = 94,   -- lightBlue   → bright blue
    [4]  = 93,   -- yellow      → bright yellow
    [5]  = 92,   -- lime        → bright green
    [6]  = 35,   -- pink        → magenta
    [7]  = 90,   -- gray        → dark gray (bright black)
    [8]  = 37,   -- lightGray   → white
    [9]  = 36,   -- cyan        → cyan
    [10] = 35,   -- purple      → magenta
    [11] = 34,   -- blue        → blue
    [12] = 33,   -- brown       → yellow
    [13] = 32,   -- green       → green
    [14] = 31,   -- red         → red
    [15] = 30,   -- black       → black
}
local SLOT_TO_ANSI_BG = {}
for s, fg in pairs(SLOT_TO_ANSI_FG) do
    SLOT_TO_ANSI_BG[s] = fg + 10  -- bg codes = fg + 10
end

-- xterm 256 palette RGB values (first 16 entries, rest follow xterm spec)
-- We only need 0-15 for 16-color fallback and a compact cube for 256-color.
local XTERM256_STANDARD = {
    -- xterm 0-15
    0x000000, 0x800000, 0x008000, 0x808000,
    0x000080, 0x800080, 0x008080, 0xC0C0C0,
    0x808080, 0xFF0000, 0x00FF00, 0xFFFF00,
    0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
}

local function rgb_dist_sq(a, b)
    local dr = ((a>>16)&0xFF) - ((b>>16)&0xFF)
    local dg = ((a>>8 )&0xFF) - ((b>>8 )&0xFF)
    local db = ( a     &0xFF) - ( b     &0xFF)
    return dr*dr + dg*dg + db*db
end

local function xterm256_to_rgb(idx)
    if idx < 0 then
        return 0
    end
    if idx < 16 then
        return XTERM256_STANDARD[idx + 1]
    end
    if idx < 232 then
        local cube = idx - 16
        local r = math.floor(cube / 36)
        local g = math.floor((cube % 36) / 6)
        local b = cube % 6
        local function v(n)
            if n == 0 then return 0 end
            return 55 + n * 40
        end
        return v(r) * 65536 + v(g) * 256 + v(b)
    end
    if idx < 256 then
        local v = 8 + (idx - 232) * 10
        return v * 65536 + v * 256 + v
    end
    return 0
end

local function rgb_to_xterm256(rgb)
    -- Check standard 16
    local best_idx, best_dist = 0, math.huge
    for i, c in ipairs(XTERM256_STANDARD) do
        local d = rgb_dist_sq(rgb, c)
        if d < best_dist then best_idx = i-1; best_dist = d end
    end
    -- Check 6x6x6 color cube (indices 16-231)
    local function cube_entry(r, g, b)
        local function v(n)
            if n == 0 then return 0 end
            return 55 + n * 40
        end
        return v(r)*65536 + v(g)*256 + v(b)
    end
    for r = 0, 5 do
        for g = 0, 5 do
            for b = 0, 5 do
                local c = cube_entry(r, g, b)
                local d = rgb_dist_sq(rgb, c)
                if d < best_dist then
                    best_idx = 16 + r*36 + g*6 + b
                    best_dist = d
                end
            end
        end
    end
    -- Check grayscale ramp (indices 232-255)
    for i = 0, 23 do
        local v = 8 + i * 10
        local c = v*65536 + v*256 + v
        local d = rgb_dist_sq(rgb, c)
        if d < best_dist then best_idx = 232 + i; best_dist = d end
    end
    return best_idx
end

-- Default palette (slot → {r,g,b} for get_palette_slot / capture_palette)
local NATIVE_PALETTE = {
    [0]  = {0xF0, 0xF0, 0xF0},  -- white
    [1]  = {0xF2, 0xB2, 0x33},  -- orange
    [2]  = {0xE5, 0x7F, 0xD8},  -- magenta
    [3]  = {0x99, 0xB2, 0xF2},  -- lightBlue
    [4]  = {0xDE, 0xDE, 0x6C},  -- yellow
    [5]  = {0x7F, 0xCC, 0x19},  -- lime
    [6]  = {0xF2, 0xB2, 0xCC},  -- pink
    [7]  = {0x4C, 0x4C, 0x4C},  -- gray
    [8]  = {0x99, 0x99, 0x99},  -- lightGray
    [9]  = {0x4C, 0x99, 0xB2},  -- cyan
    [10] = {0xB2, 0x66, 0xE5},  -- purple
    [11] = {0x33, 0x66, 0xCC},  -- blue
    [12] = {0x7F, 0x66, 0x4C},  -- brown
    [13] = {0x57, 0xA6, 0x4E},  -- green
    [14] = {0xCC, 0x4C, 0x4C},  -- red
    [15] = {0x11, 0x11, 0x11},  -- black
}

-- =========================================================================
-- Framebuffer (internal cell grid for diff-render)
-- =========================================================================

local _w, _h = 80, 24
local _cur_fg_hl = nil  -- last emitted fg string fragment
local _cur_bg_hl = nil  -- last emitted bg string fragment
local _default_fg_rgb = 0xF0F0F0
local _default_bg_rgb = 0x111111
local _default_sp_rgb = nil
local _default_fg_cterm = nil
local _default_bg_cterm = nil

-- Two cell grids: current (what should be displayed) and back (what is).
-- Each cell: { char, fg_token_or_nil, bg_token_or_nil }
-- nil means "use terminal default"
local _grid_current = {}  -- [row][col] = {ch, fg, bg}
local _grid_back    = {}  -- same, what was actually rendered last frame

local function make_empty_cell() return {" ", nil, nil} end

local function grid_alloc(w, h)
    local g = {}
    for r = 0, h - 1 do
        g[r] = {}
        for c = 0, w - 1 do g[r][c] = make_empty_cell() end
    end
    return g
end

local _cursor_row, _cursor_col = 0, 0

-- =========================================================================
-- SGR emission helpers
-- =========================================================================

local function emit_move(row, col)
    write(esc((row+1) .. ";" .. (col+1) .. "H"))
end

local function emit_sgr_reset()
    write(esc("0m"))
    _cur_fg_hl = nil
    _cur_bg_hl = nil
end

local function cterm_token(idx)
    return -idx - 1
end

local function cterm_index_from_token(token)
    return -token - 1
end

local function default_fg_token()
    local depth = Native.color_depth()
    if depth == "rgb" then
        return _default_fg_rgb
    end
    if depth == "256" or depth == "16" then
        if _default_fg_cterm ~= nil then
            return cterm_token(_default_fg_cterm)
        end
        return nil
    end
    return nil
end

local function default_bg_token()
    local depth = Native.color_depth()
    if depth == "rgb" then
        return _default_bg_rgb
    end
    if depth == "256" or depth == "16" then
        if _default_bg_cterm ~= nil then
            return cterm_token(_default_bg_cterm)
        end
        return nil
    end
    return nil
end

local function attrs_to_tokens(attrs)
    local depth = Native.color_depth()
    if depth == "rgb" then
        return attrs.foreground or _default_fg_rgb, attrs.background or _default_bg_rgb
    end

    if depth == "256" or depth == "16" then
        local fg = attrs.cterm_foreground
        local bg = attrs.cterm_background
        if fg ~= nil then fg = cterm_token(fg) else fg = default_fg_token() end
        if bg ~= nil then bg = cterm_token(bg) else bg = default_bg_token() end
        return fg, bg
    end

    return nil, nil
end

local function emit_fg(token)
    local depth = Native.color_depth()
    if token == nil then
        write(esc("39m"))
    elseif token >= 0 then
        local r = (token>>16)&0xFF
        local g = (token>>8 )&0xFF
        local b =  token     &0xFF
        write(esc("38;2;"..r..";"..g..";"..b.."m"))
    elseif depth == "256" then
        write(esc("38;5;"..cterm_index_from_token(token).."m"))
    elseif depth == "16" then
        local idx = cterm_index_from_token(token)
        if idx < 16 then
            write(esc(SLOT_TO_ANSI_FG[idx].."m"))
        else
            local rgb = xterm256_to_rgb(idx)
            local best_s, best_d = 0, math.huge
            for s = 0, 15 do
                local p = NATIVE_PALETTE[s]
                local pc = p[1]*65536 + p[2]*256 + p[3]
                local d = rgb_dist_sq(rgb, pc)
                if d < best_d then best_s = s; best_d = d end
            end
            write(esc(SLOT_TO_ANSI_FG[best_s].."m"))
        end
    else
        write(esc("39m"))
    end
end

local function emit_bg(token)
    local depth = Native.color_depth()
    if token == nil then
        write(esc("49m"))
    elseif token >= 0 then
        local r = (token>>16)&0xFF
        local g = (token>>8 )&0xFF
        local b =  token     &0xFF
        write(esc("48;2;"..r..";"..g..";"..b.."m"))
    elseif depth == "256" then
        write(esc("48;5;"..cterm_index_from_token(token).."m"))
    elseif depth == "16" then
        local idx = cterm_index_from_token(token)
        if idx < 16 then
            write(esc(SLOT_TO_ANSI_BG[idx].."m"))
        else
            local rgb = xterm256_to_rgb(idx)
            local best_s, best_d = 0, math.huge
            for s = 0, 15 do
                local p = NATIVE_PALETTE[s]
                local pc = p[1]*65536 + p[2]*256 + p[3]
                local d = rgb_dist_sq(rgb, pc)
                if d < best_d then best_s = s; best_d = d end
            end
            write(esc(SLOT_TO_ANSI_BG[best_s].."m"))
        end
    else
        write(esc("49m"))
    end
end

-- =========================================================================
-- Highlight registry
-- =========================================================================

local _hl = {}  -- [id] = attrs

function Native.hl_define(id, attrs)
    _hl[id] = attrs
end

-- =========================================================================
-- Backend interface
-- =========================================================================

function Native.begin_frame()
    -- Snapshot current → back for diffing in end_frame
    -- (We'll do this lazily: just keep _grid_current as working buffer)
end

function Native.end_frame()
    write(esc("?25l"))  -- hide cursor during render

    local last_fg_token = nil
    local last_bg_token = nil
    emit_sgr_reset()

    for r = 0, _h - 1 do
        local row_cur = _grid_current[r]
        local row_back = _grid_back and _grid_back[r]
        if row_cur then
            for c = 0, _w - 1 do
                local cell = row_cur[c]
                if cell then
                    local bcell = row_back and row_back[c]
                    local changed = not bcell
                        or cell[1] ~= bcell[1]
                        or cell[2] ~= bcell[2]
                        or cell[3] ~= bcell[3]
                    if changed then
                        emit_move(r, c)
                        local fg = cell[2]
                        local bg = cell[3]
                        if fg ~= last_fg_token then
                            emit_fg(fg)
                            last_fg_token = fg
                        end
                        if bg ~= last_bg_token then
                            emit_bg(bg)
                            last_bg_token = bg
                        end
                        write(cell[1])
                    end
                end
            end
        end
    end

    -- Copy current → back
    _grid_back = {}
    for r = 0, _h - 1 do
        _grid_back[r] = {}
        local row = _grid_current[r]
        if row then
            for c = 0, _w - 1 do
                local cell = row[c]
                _grid_back[r][c] = cell and {cell[1], cell[2], cell[3]} or make_empty_cell()
            end
        end
    end

    -- Move actual cursor
    emit_move(_cursor_row, _cursor_col)
    emit_sgr_reset()
    write(esc("?25h"))  -- show cursor
    flush()
end

function Native.flush()
    Native.end_frame()
end

function Native.default_colors_set(rgb_fg, rgb_bg, rgb_sp, _cterm_fg, _cterm_bg)
    _default_fg_rgb = rgb_fg or _default_fg_rgb
    _default_bg_rgb = rgb_bg or _default_bg_rgb
    _default_sp_rgb = rgb_sp
    _default_fg_cterm = _cterm_fg
    _default_bg_cterm = _cterm_bg
end

function Native.normalize_codepoint(cp)
    return Utf8.char_for_codepoint(cp), false
end

function Native.on_load_module_ready(scope)
    Utf8 = scope.loadModule("lib.utf8")
end

function Native.grid_line(grid, row, col, cells, wrap)
    if not _grid_current[row] then return end
    local cx = col
    local last_fg = default_fg_token()
    local last_bg = default_bg_token()

    for _, cell in ipairs(cells) do
        local ch     = cell[1]
        local hl_id  = cell[2]
        local rep    = cell[3] or 1
        local swap   = cell[4] == true

        if hl_id ~= nil then
            if hl_id == 0 then
                last_fg = default_fg_token()
                last_bg = default_bg_token()
            else
                local last_attrs = _hl[hl_id]
                if last_attrs then
                    last_fg, last_bg = attrs_to_tokens(last_attrs)
                    if last_attrs.reverse then
                        last_fg, last_bg = last_bg, last_fg
                    end
                end
            end
        end

        local cell_fg = last_fg
        local cell_bg = last_bg
        if swap then
            cell_fg, cell_bg = cell_bg, cell_fg
        end

        for _ = 1, rep do
            if cx >= 0 and cx < _w then
                local slot = _grid_current[row]
                if slot then
                    slot[cx] = {ch == "" and " " or ch, cell_fg, cell_bg}
                end
            end
            cx = cx + 1
        end
    end
end

function Native.grid_cursor_goto(grid, row, col)
    _cursor_row = row
    _cursor_col = col
end

function Native.grid_clear(grid)
    _grid_current = grid_alloc(_w, _h)
    _grid_back    = nil
    write(esc("2J") .. esc("H"))
    flush()
end

function Native.grid_resize(grid, w, h)
    _w = w; _h = h
    _grid_current = grid_alloc(w, h)
    _grid_back    = nil
end

function Native.grid_destroy(grid)
    if grid == 1 then
        Native.grid_clear(grid)
    end
end

function Native.grid_scroll(grid, top, bot, left, right, rows, cols)
    cols = cols or 0
    if rows == 0 and cols == 0 then
        return
    end

    local snapshot = {}
    for row = top, bot - 1 do
        snapshot[row] = {}
        for col = left, right - 1 do
            local cell = _grid_current[row] and _grid_current[row][col] or make_empty_cell()
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
                _grid_current[row][col] = { cell[1], cell[2], cell[3] }
            else
                _grid_current[row][col] = make_empty_cell()
            end
        end
    end
end

function Native.size()
    _w, _h = detect_size()
    return _w, _h
end

function Native.color_depth()
    if not _color_depth then
        _color_depth = detect_color_depth()
    end
    return _color_depth
end

function Native.supports_palette()
    return false
end

function Native.set_palette_slot(slot, r, g, b)
    -- no-op on standard terminals
end

function Native.get_palette_slot(slot)
    local p = NATIVE_PALETTE[slot] or {0,0,0}
    return p[1], p[2], p[3]
end

function Native.capture_palette()
    local out = {}
    for s = 0, 15 do
        local p = NATIVE_PALETTE[s]
        out[s] = {p[1], p[2], p[3]}
    end
    return out
end

function Native.reset(original_palette)
    write(esc("0m") .. esc("2J") .. esc("H"))
    flush()
    os.execute("stty sane 2>/dev/null")
end

-- =========================================================================
-- Input (raw mode + ANSI key/mouse parsing)
-- =========================================================================

-- Timer queue: {id=int, fire_at=epoch_ms}
local _timers      = {}
local _next_timer_id = 1

function Native.start_timer(t)
    local id = _next_timer_id
    _next_timer_id = _next_timer_id + 1
    local fire_at = epoch_ms() + math.floor(t * 1000)
    _timers[#_timers + 1] = {id = id, fire_at = fire_at}
    return id
end

function Native.cancel_timer(id)
    for i = #_timers, 1, -1 do
        if _timers[i].id == id then
            table.remove(_timers, i)
            return
        end
    end
end

function Native.get_epoch()
    return epoch_ms()
end

-- Key name table matching CC's keys.* constants
-- Values are the CC scan codes (kept identical for cross-backend compat).
Native.keys = {
    one=2,   two=3,   three=4, four=5,  five=6,   six=7,   seven=8, eight=9,
    nine=10, zero=11, minus=12, equals=13, backspace=14, tab=15,
    q=16, w=17, e=18, r=19, t=20, y=21, u=22, i=23, o=24, p=25,
    leftBracket=26, rightBracket=27, enter=28, leftCtrl=29,
    a=30, s=31, d=32, f=33, g=34, h=35, j=36, k=37, l=38,
    semicolon=39, apostrophe=40, grave=41, leftShift=42, backslash=43,
    z=44, x=45, c=46, v=47, b=48, n=49, m=50,
    comma=51, period=52, slash=53, rightShift=54, multiply=55,
    leftAlt=56, space=57, capsLock=58,
    f1=59, f2=60, f3=61, f4=62, f5=63, f6=64, f7=65, f8=66, f9=67,
    f10=68, numLock=69, scrollLock=70,
    numPad7=71, numPad8=72, numPad9=73, numPadSubtract=74,
    numPad4=75, numPad5=76, numPad6=77, numPadAdd=78,
    numPad1=79, numPad2=80, numPad3=81, numPad0=82, numPadDecimal=83,
    f11=87, f12=88,
    f13=100, f14=101, f15=102,
    numPadEqual=141, at=145, colon=146, underscore=147,
    numPadEnter=156, rightCtrl=157, numPadComma=179, numPadDivide=181,
    rightAlt=184, numPadPageUp=201, numPadPageDown=209,
    numPadEnd=207, numPadHome=199, numPadUp=200, numPadDown=208,
    numPadLeft=203, numPadRight=205, numPadInsert=210, numPadDelete=211,
    up=200, down=208, left=203, right=205,
    home=199, ["end"]=207, pageUp=201, pageDown=209,
    insert=210, delete=211,
    pause=197,
}

-- Reverse map: char → key name (for printable keys)
local _char_to_key = {}
for kn, _ in pairs(Native.keys) do
    if #kn == 1 then _char_to_key[kn] = kn end
end
-- Digits
for _, d in ipairs({"one","two","three","four","five","six","seven","eight","nine","zero"}) do
    local digits = {"1","2","3","4","5","6","7","8","9","0"}
    local idx = ({one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,zero=10})[d]
    _char_to_key[digits[idx]] = d
end

-- ANSI escape → {key_name, shift, ctrl}
local ANSI_KEYS = {
    ["[A"]  = {"up",       false, false},
    ["[B"]  = {"down",     false, false},
    ["[C"]  = {"right",    false, false},
    ["[D"]  = {"left",     false, false},
    ["[H"]  = {"home",     false, false},
    ["[F"]  = {"end",      false, false},
    ["[2~"] = {"insert",   false, false},
    ["[3~"] = {"delete",   false, false},
    ["[5~"] = {"pageUp",   false, false},
    ["[6~"] = {"pageDown", false, false},
    ["OP"]  = {"f1",  false, false},
    ["OQ"]  = {"f2",  false, false},
    ["OR"]  = {"f3",  false, false},
    ["OS"]  = {"f4",  false, false},
    ["[15~"]= {"f5",  false, false},
    ["[17~"]= {"f6",  false, false},
    ["[18~"]= {"f7",  false, false},
    ["[19~"]= {"f8",  false, false},
    ["[20~"]= {"f9",  false, false},
    ["[21~"]= {"f10", false, false},
    ["[23~"]= {"f11", false, false},
    ["[24~"]= {"f12", false, false},
    -- Shifted arrows
    ["[1;2A"] = {"up",    true, false},
    ["[1;2B"] = {"down",  true, false},
    ["[1;2C"] = {"right", true, false},
    ["[1;2D"] = {"left",  true, false},
    -- Ctrl+arrows
    ["[1;5A"] = {"up",    false, true},
    ["[1;5B"] = {"down",  false, true},
    ["[1;5C"] = {"right", false, true},
    ["[1;5D"] = {"left",  false, true},
}

local _stdin_tty = nil
local _stdin_buffer = {}
local _stdin_buffer_len = 0
local _stdin_error = nil
local _stdin_eof = false

local function push_stdin_chunk(chunk)
    if chunk ~= "" then
        _stdin_buffer[#_stdin_buffer + 1] = chunk
        _stdin_buffer_len = _stdin_buffer_len + #chunk
    end
end

local function pop_stdin_char()
    if _stdin_buffer_len == 0 then
        return nil
    end

    local chunk = _stdin_buffer[1]
    local ch = chunk:sub(1, 1)
    if #chunk == 1 then
        table.remove(_stdin_buffer, 1)
    else
        _stdin_buffer[1] = chunk:sub(2)
    end
    _stdin_buffer_len = _stdin_buffer_len - 1
    return ch
end

local function ensure_stdin_reader()
    if _stdin_tty then
        return
    end

    _stdin_tty = assert(uv.new_tty(0, true))
    assert(uv.read_start(_stdin_tty, function(err, chunk)
        if err then
            _stdin_error = err
            return
        end
        if chunk == nil then
            _stdin_eof = true
            return
        end
        push_stdin_chunk(chunk)
    end))
end

local function close_stdin_reader()
    if not _stdin_tty then
        return
    end

    uv.read_stop(_stdin_tty)
    uv.close(_stdin_tty)
    _stdin_tty = nil
    _stdin_buffer = {}
    _stdin_buffer_len = 0
    _stdin_error = nil
    _stdin_eof = false
end

local function wait_for_activity(timeout_ms)
    local timer = nil
    if timeout_ms ~= nil then
        timer = assert(uv.new_timer())
        assert(timer:start(timeout_ms, 0, function() end))
    end
    uv.run("once")
    if timer then
        timer:stop()
        uv.close(timer)
    end
end

local function read_input_char(timeout_ms)
    local ch = pop_stdin_char()
    if ch then
        return ch
    end

    if _stdin_error then
        error(_stdin_error)
    end
    if _stdin_eof then
        return nil
    end

    wait_for_activity(timeout_ms)

    if _stdin_error then
        error(_stdin_error)
    end
    return pop_stdin_char()
end

local _raw_mode_active = false

local function set_raw_mode(on)
    if on then
        os.execute("stty raw -echo 2>/dev/null")
        -- Enable SGR mouse reporting
        write("\27[?1000h\27[?1006h\27[?1003h")
        flush()
        ensure_stdin_reader()
        _raw_mode_active = true
    else
        write("\27[?1000l\27[?1006l\27[?1003l")
        flush()
        os.execute("stty sane 2>/dev/null")
        close_stdin_reader()
        _raw_mode_active = false
    end
end

-- Parse a complete escape sequence starting after the initial ESC.
-- `c` is the char immediately after ESC.
-- Returns an event table or nil.
local function parse_escape(c)
    if c == "[" or c == "O" then
        -- Read more bytes to complete the sequence (heuristic: up to 16)
        local seq = c
        for _ = 1, 16 do
            local nc = read_input_char(5)
            if not nc then break end
            seq = seq .. nc
            -- Terminator: letter (not digit, not ';', not '[')
            local last = nc:byte()
            if (last >= 64 and last <= 126) and last ~= 59 then
                break
            end
        end

        -- SGR mouse: \27[<btn;x;yM or \27[<btn;x;ym
        if seq:sub(1,2) == "[<" then
            local btn_s, x_s, y_s, final = seq:match("%[<(%d+);(%d+);(%d+)([Mm])")
            if btn_s then
                local btn = tonumber(btn_s)
                local x   = tonumber(x_s)
                local y   = tonumber(y_s)
                local released = (final == "m")
                local scroll_dir = nil
                if btn == 64 then scroll_dir = "up"
                elseif btn == 65 then scroll_dir = "down"
                elseif btn == 66 then scroll_dir = "left"
                elseif btn == 67 then scroll_dir = "right" end

                if scroll_dir then
                    return {"mouse_scroll", scroll_dir, x, y}
                elseif released then
                    return {"mouse_up", (btn & 3) + 1, x, y}
                elseif btn & 32 ~= 0 then
                    return {"mouse_drag", (btn & 3) + 1, x, y}
                else
                    return {"mouse_click", (btn & 3) + 1, x, y}
                end
            end
        end

        -- Known escape sequences
        local mapped = ANSI_KEYS[seq]
        if mapped then
            return {"key", mapped[1], mapped[2], mapped[3]}
        end

        -- term_resize: \27[8;rows;colst (some terminals send this)
        local rows, cols = seq:match("%[8;(%d+);(%d+)t")
        if rows then
            return {"term_resize", tonumber(cols), tonumber(rows)}
        end

        return nil  -- unknown sequence, discard
    elseif c then
        -- Alt+key: return as key event with alt flag (not modeled in CC compat,
        -- but pass through for completeness)
        return nil
    end
    return nil
end

local function next_timer_timeout_ms(now)
    local wait_ms = nil
    for i = 1, #_timers do
        local delta = _timers[i].fire_at - now
        if delta <= 0 then
            return 0
        end
        if wait_ms == nil or delta < wait_ms then
            wait_ms = delta
        end
    end
    return wait_ms
end

function Native.pull_event(filter)
    if not _raw_mode_active then
        set_raw_mode(true)
        _grid_current = grid_alloc(_w, _h)
    end

    while true do
        -- Check software timers first
        local now = Native.get_epoch()
        for i = #_timers, 1, -1 do
            local t = _timers[i]
            if now >= t.fire_at then
                table.remove(_timers, i)
                local ev = {"timer", t.id}
                if not filter or filter == "timer" then
                    return table.unpack(ev)
                end
            end
        end

        local c = read_input_char(next_timer_timeout_ms(now))
        if not c then
            if _stdin_eof and _stdin_buffer_len == 0 then
                return "terminate"
            end
        else
            local ev = nil

            if c == "\27" then
                -- ESC sequence: peek at next char with a brief read
                local nc = read_input_char(25)
                if nc then
                    ev = parse_escape(nc)
                else
                    ev = {"key", "escape", false, false}
                end
            elseif c == "\r" or c == "\n" then
                ev = {"key", "enter", false, false}
            elseif c == "\127" or c == "\8" then
                ev = {"key", "backspace", false, false}
            elseif c == "\t" then
                ev = {"key", "tab", false, false}
            elseif c:byte() >= 1 and c:byte() <= 26 then
                -- Ctrl+letter
                local letter = string.char(c:byte() + 96)
                ev = {"key", letter, false, true}
            elseif c:byte() >= 32 and c:byte() < 127 then
                -- Printable ASCII
                local kn = _char_to_key[c]
                if filter == "char" then
                    return "char", c
                end
                if kn then
                    ev = {"key", kn, false, false}
                end
            end

            if ev then
                if not filter or filter == ev[1] then
                    return table.unpack(ev)
                end
            end
        end
    end
end

-- =========================================================================
-- Filesystem (LFS + io.open wrapper matching CC fs API)
-- =========================================================================

local _lfs_ok, lfs = pcall(require, "lfs")
if not _lfs_ok then lfs = nil end

-- Path utilities
local function path_join(...)
    local parts = {...}
    local result = parts[1] or ""
    for i = 2, #parts do
        local p = parts[i]
        if p:sub(1,1) == "/" then
            result = p
        elseif result == "" or result:sub(-1) == "/" then
            result = result .. p
        else
            result = result .. "/" .. p
        end
    end
    return result
end

local function path_normalize(p)
    -- Collapse // and ./ and handle ../
    local parts = {}
    for seg in p:gmatch("[^/]+") do
        if seg == ".." then
            if #parts > 0 then parts[#parts] = nil end
        elseif seg ~= "." then
            parts[#parts+1] = seg
        end
    end
    local result = table.concat(parts, "/")
    if p:sub(1,1) == "/" then result = "/" .. result end
    return result ~= "" and result or "."
end

local FS = {}

function FS.combine(a, b)
    if b == nil then return a end
    return path_normalize(path_join(a, b))
end

function FS.exists(path)
    if lfs then
        return lfs.attributes(path) ~= nil
    end
    local f = io.open(path, "r")
    if f then f:close(); return true end
    return false
end

function FS.isDir(path)
    if lfs then
        return lfs.attributes(path, "mode") == "directory"
    end
    -- Fallback: try to open as dir (unreliable without lfs)
    return false
end

function FS.list(path)
    local entries = {}
    if lfs then
        for name in lfs.dir(path) do
            if name ~= "." and name ~= ".." then
                entries[#entries+1] = name
            end
        end
        table.sort(entries)
    end
    return entries
end

function FS.makeDir(path)
    if lfs then
        lfs.mkdir(path)
    else
        os.execute("mkdir -p " .. path)
    end
end

function FS.delete(path)
    if lfs then
        if lfs.attributes(path, "mode") == "directory" then
            for name in lfs.dir(path) do
                if name ~= "." and name ~= ".." then
                    FS.delete(path .. "/" .. name)
                end
            end
            lfs.rmdir(path)
        else
            os.remove(path)
        end
    else
        os.remove(path)
    end
end

function FS.move(from, to)
    os.rename(from, to)
end

function FS.copy(from, to)
    local inf = io.open(from, "rb")
    if not inf then return end
    local outf = io.open(to, "wb")
    if not outf then inf:close(); return end
    local chunk = inf:read(4096)
    while chunk do
        outf:write(chunk)
        chunk = inf:read(4096)
    end
    inf:close()
    outf:close()
end

function FS.getSize(path)
    if lfs then
        return lfs.attributes(path, "size") or 0
    end
    local f = io.open(path, "rb")
    if not f then return 0 end
    local size = f:seek("end") or 0
    f:close()
    return size
end

function FS.getFreeSpace(path)
    -- Best-effort; no portable pure-Lua way to get this
    local handle = io.popen("df -k " .. path .. " 2>/dev/null | tail -1 | awk '{print $4}'", "r")
    if handle then
        local out = handle:read("*l")
        handle:close()
        if out then return (tonumber(out) or 0) * 1024 end
    end
    return 0
end

function FS.open(path, mode)
    -- Map CC modes: "r"=read text, "rb"=read binary, "w"=write text,
    -- "wb"=write binary, "a"=append text
    local lua_mode = mode
    if mode == "r" then lua_mode = "r"
    elseif mode == "w" then lua_mode = "w"
    elseif mode == "a" then lua_mode = "a"
    elseif mode == "rb" then lua_mode = "rb"
    elseif mode == "wb" then lua_mode = "wb"
    end

    local f = io.open(path, lua_mode)
    if not f then return nil end

    local is_read = (mode == "r" or mode == "rb")
    local is_binary = (mode == "rb" or mode == "wb")

    local handle = {}
    if is_read then
        function handle.read(n)
            if n then return f:read(n) end
            return f:read("*l")
        end
        function handle.readLine(withNewline)
            local line = f:read("*l")
            if line == nil then return nil end
            if withNewline then return line .. "\n" end
            return line
        end
        function handle.readAll()
            return f:read("*a")
        end
    else
        function handle.write(s)
            f:write(s)
        end
        function handle.writeLine(s)
            f:write(s .. "\n")
        end
        function handle.flush()
            f:flush()
        end
    end
    function handle.close()
        f:close()
    end
    function handle.seek(...)
        return f:seek(...)
    end
    return handle
end

Native.fs = FS

return Native
