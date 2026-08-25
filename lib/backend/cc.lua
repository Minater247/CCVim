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
        local ev = { os.pullEvent(filter) }
        if ev[1] == "mouse_scroll" then
            local delta = tonumber(ev[2]) or 0
            if delta > 0 then
                ev[2] = "down"
                return table.unpack(ev)
            end
            if delta < 0 then
                ev[2] = "up"
                return table.unpack(ev)
            end
        else
            return table.unpack(ev)
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

CC.keys = keys
CC.fs   = fs

return CC
