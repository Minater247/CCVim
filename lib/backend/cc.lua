--[[
    ComputerCraft backend for lib/screen.lua.

    All CC-specific APIs (term.*, window.create, colors.*, keys, fs, os.*) are
    confined here. The rest of the program sees only RGB integers and the grid
    protocol defined in lib/screen.lua.

    Slot numbering: 0–15, where slot = math.log2(cc_bitmask).
    CC APIs take bitmasks; this backend translates: bitmask = 2^slot.
]]

local CC = {}

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

-- Live palette: slot → packed RGB (may be reprogrammed by colorschemes)
local _palette = {}
for s = 0, 15 do _palette[s] = DEFAULT_SLOT_RGB[s] end
local _default_fg_rgb = DEFAULT_SLOT_RGB[0]
local _default_bg_rgb = DEFAULT_SLOT_RGB[15]
local _default_sp_rgb = nil
local _grids = {}

-- =========================================================================
-- Color math (OKLAB perceptual distance for RGB → nearest slot mapping)
-- =========================================================================

local OKLAB_CACHE = {}

local function unpack_rgb(rgb)
    local r = math.floor(rgb / 65536) % 256
    local g = math.floor(rgb / 256) % 256
    local b = rgb % 256
    return r, g, b
end

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

local function srgb_linear(c)
    if c <= 0.04045 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function rgb_to_oklab(rgb)
    local cached = OKLAB_CACHE[rgb]
    if cached then return cached[1], cached[2], cached[3] end

    local r8, g8, b8 = unpack_rgb(rgb)
    local r = srgb_linear(r8 / 255)
    local g = srgb_linear(g8 / 255)
    local b = srgb_linear(b8 / 255)

    local l = 0.4122214708*r + 0.5363325363*g + 0.0514459929*b
    local m = 0.2119034982*r + 0.6806995451*g + 0.1073969566*b
    local s = 0.0883024619*r + 0.2817188376*g + 0.6299787005*b

    local l_ = l^(1/3); local m_ = m^(1/3); local s_ = s^(1/3)

    local out = {
        0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_,
        1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_,
        0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_,
    }
    OKLAB_CACHE[rgb] = out
    return out[1], out[2], out[3]
end

local function color_dist(a, b)
    local l1, a1, b1 = rgb_to_oklab(a)
    local l2, a2, b2 = rgb_to_oklab(b)
    local dl, da, db = l1-l2, a1-a2, b1-b2
    return math.sqrt(dl*dl + da*da + db*db)
end

local function xterm256_to_rgb(idx)
    if idx < 0 then
        return DEFAULT_SLOT_RGB[15]
    end
    if idx < 16 then
        return ({
            [0] = 0x000000, [1] = 0x800000, [2] = 0x008000, [3] = 0x808000,
            [4] = 0x000080, [5] = 0x800080, [6] = 0x008080, [7] = 0xC0C0C0,
            [8] = 0x808080, [9] = 0xFF0000, [10] = 0x00FF00, [11] = 0xFFFF00,
            [12] = 0x0000FF, [13] = 0xFF00FF, [14] = 0x00FFFF, [15] = 0xFFFFFF,
        })[idx]
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
    return DEFAULT_SLOT_RGB[15]
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
        local d = color_dist(rgb, _palette[s])
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
-- Palette optimization (k-means over highlight-defined RGB colors)
-- =========================================================================

local _hl_usage = {}        -- [rgb] = cumulative weight
local _hl_weights = {       -- group-name importance weight
    Normal=8, StatusLine=6, StatusLineNC=4, WinSeparator=4, VertSplit=4,
    TabLine=4, TabLineSel=5, NonText=5, EndOfBuffer=5, CursorLine=3,
    CursorLineNr=3, CursorColumn=3, Visual=3, Search=3, IncSearch=3,
    Pmenu=3, PmenuSel=3, Error=4, ErrorMsg=4, WarningMsg=3, Todo=3,
    Comment=2, Constant=2, Identifier=2, Statement=2, PreProc=2,
    Type=2, Special=2, Directory=2, Title=2,
}

local function color_luminance(rgb)
    local r8, g8, b8 = unpack_rgb(rgb)
    local r = r8 / 255
    local g = g8 / 255
    local b = b8 / 255
    return 0.30*r + 0.59*g + 0.11*b
end

local function palette_cost(items, centers)
    local total = 0
    for i = 1, #items do
        local item = items[i]
        local best = math.huge
        for j = 1, #centers do
            local d = color_dist(item.rgb, centers[j])
            if d < best then best = d end
        end
        total = total + best * item.weight
    end
    return total
end

local function seeded_centers(items, wanted)
    local centers = {}
    if #items == 0 then return centers end
    if #items <= wanted then
        for i = 1, #items do centers[i] = items[i].rgb end
        return centers
    end

    local best_cost = math.huge
    for i = 1, #items do
        local rgb = items[i].rgb
        local cost = palette_cost(items, {rgb})
        if cost < best_cost or (cost == best_cost and rgb < (centers[1] or math.huge)) then
            centers[1] = rgb; best_cost = cost
        end
    end
    local selected = {[centers[1]] = true}

    while #centers < wanted do
        local best_rgb, next_cost = nil, math.huge
        for i = 1, #items do
            local rgb = items[i].rgb
            if not selected[rgb] then
                local trial = {}
                for j = 1, #centers do trial[j] = centers[j] end
                trial[#trial+1] = rgb
                local cost = palette_cost(items, trial)
                if cost < next_cost or (cost == next_cost and (best_rgb == nil or rgb < best_rgb)) then
                    best_rgb = rgb; next_cost = cost
                end
            end
        end
        selected[best_rgb] = true
        centers[#centers+1] = best_rgb
    end
    return centers
end

local function refine_centers(items, centers)
    if #items <= #centers then return centers end
    local selected = {}
    for i = 1, #centers do selected[centers[i]] = true end

    local current_cost = palette_cost(items, centers)
    local improved = true
    while improved do
        improved = false
        for i = 1, #centers do
            local old_rgb = centers[i]
            selected[old_rgb] = nil
            for j = 1, #items do
                local candidate = items[j].rgb
                if not selected[candidate] then
                    centers[i] = candidate
                    local cost = palette_cost(items, centers)
                    if cost < current_cost then
                        selected[candidate] = true
                        current_cost = cost
                        improved = true
                        break
                    end
                end
            end
            if improved then break end
            centers[i] = old_rgb
            selected[old_rgb] = true
        end
    end
    return centers
end

local function assign_palette_slots(centers)
    local slot_colors = {}
    local remaining = {}
    for i = 1, #centers do remaining[i] = centers[i] end

    local function take_extreme(want_darkest)
        if #remaining == 0 then return nil end
        local best_idx = 1
        local best_luma = color_luminance(remaining[1])
        for i = 2, #remaining do
            local luma = color_luminance(remaining[i])
            local better = want_darkest and luma < best_luma or luma > best_luma
            if better then best_idx = i; best_luma = luma end
        end
        return table.remove(remaining, best_idx)
    end

    -- Darkest → slot 15 (black), brightest → slot 0 (white)
    slot_colors[15] = take_extreme(true)  or DEFAULT_SLOT_RGB[15]
    slot_colors[0]  = take_extreme(false) or DEFAULT_SLOT_RGB[0]

    for s = 0, 15 do
        if not slot_colors[s] then
            if #remaining == 0 then
                slot_colors[s] = DEFAULT_SLOT_RGB[s]
            else
                local best_idx, best_dist = 1, math.huge
                for j = 1, #remaining do
                    local d = color_dist(DEFAULT_SLOT_RGB[s], remaining[j])
                    if d < best_dist then best_idx = j; best_dist = d end
                end
                slot_colors[s] = table.remove(remaining, best_idx)
            end
        end
    end
    return slot_colors
end

--- Reoptimize the 16-slot palette to best represent the currently-defined
--- highlight colors. Called by the colorscheme commit logic.
--- Returns true if the palette was changed.
function CC.optimize_palette()
    -- Build weighted item list from tracked usage
    local items = {}
    for rgb, weight in pairs(_hl_usage) do
        items[#items+1] = {rgb=rgb, weight=weight}
    end
    table.sort(items, function(a,b)
        return a.weight ~= b.weight and a.weight > b.weight or a.rgb < b.rgb
    end)
    if #items == 0 then return false end

    local centers = seeded_centers(items, 16)
    centers = refine_centers(items, centers)
    local slot_colors = assign_palette_slots(centers)

    local changed = false
    for s = 0, 15 do
        if slot_colors[s] and slot_colors[s] ~= _palette[s] then
            _palette[s] = slot_colors[s]
            changed = true
        end
    end
    if changed then
        invalidate_slot_cache()
        for s = 0, 15 do
            local r, g, b = unpack_rgb(_palette[s])
            term.setPaletteColor(2^s, r/255, g/255, b/255)
        end
    end
    return changed
end

-- =========================================================================
-- Highlight registry (hl_id → {fg_slot, bg_slot})
-- =========================================================================

local _hl = {}   -- [id] = {fg=slot, bg=slot}

function CC.hl_define(id, attrs)
    local fg_rgb = attrs.fg
    local bg_rgb = attrs.bg
    -- Track usage for palette optimization
    if type(fg_rgb) == "number" then
        _hl_usage[fg_rgb] = (_hl_usage[fg_rgb] or 0) + 1
    end
    if type(bg_rgb) == "number" then
        _hl_usage[bg_rgb] = (_hl_usage[bg_rgb] or 0) + 1
    end
    _hl[id] = attrs
end

function CC.default_colors_set(rgb_fg, rgb_bg, rgb_sp, _cterm_fg, _cterm_bg)
    _default_fg_rgb = rgb_fg or _default_fg_rgb
    _default_bg_rgb = rgb_bg or _default_bg_rgb
    _default_sp_rgb = rgb_sp
end

-- =========================================================================
-- Double-buffer state
-- =========================================================================

local _backwin   = nil
local _prevterm  = nil
local _parent    = nil

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
        _backwin.setPaletteColor(2^s, r/255, g/255, b/255)
    end
end

function CC.end_frame()
    term.redirect(_prevterm)
    _backwin.setVisible(true)
end

function CC.flush()
    CC.end_frame()
end

function CC.grid_line(grid, row, col, cells, wrap)
    local state = ensure_grid_state(grid, grid == 1 and term.getSize() or 1, grid == 1 and select(2, term.getSize()) or 1)
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

        for offset = 0, rep - 1 do
            if state.rows[row] and state.rows[row][col + offset] then
                state.rows[row][col + offset] = { ch, last_fg_slot, last_bg_slot }
            end
        end

        if grid == 1 and _backwin then
            _backwin.setCursorPos(cx, cy)
            local text   = string.rep(ch == "" and " " or ch, rep)
            local fg_str = string.rep(SLOT_HEX[last_fg_slot], rep)
            local bg_str = string.rep(SLOT_HEX[last_bg_slot], rep)
            _backwin.blit(text, fg_str, bg_str)
        end

        cx = cx + rep
        i  = i + 1
    end
end

function CC.grid_cursor_goto(grid, row, col)
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
    term.setPaletteColor(2^slot, r/255, g/255, b/255)
end

function CC.get_palette_slot(slot)
    local rgb = _palette[slot]
    return unpack_rgb(rgb)
end

function CC.capture_palette()
    local captured = {}
    for s = 0, 15 do
        local r, g, b = term.getPaletteColor(2^s)
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
                term.setPaletteColor(2^s, c[1]/255, c[2]/255, c[3]/255)
            end
        end
    end
    term.setBackgroundColor(2^15)  -- black
    term.setTextColor(2^0)         -- white
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

CC.keys = keys
CC.fs   = fs

return CC
