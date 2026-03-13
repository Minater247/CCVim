--[[
    Grid-based screen abstraction (Neovim ui.txt protocol).
    This module is the single interface between the core engine and
    any display backend. It does NOT expose a term-compatible surface.

    Exposed as _V.screen. Backends implement: begin_frame, end_frame,
    hl_define, grid_line, grid_cursor_goto, grid_clear, size,
    color_depth, supports_palette, set_palette_slot, get_palette_slot,
    capture_palette, reset, pull_event, start_timer, cancel_timer,
    get_epoch, keys, fs.
]]

local Screen = {}

local _backend = nil

-- hl_id registry
-- hl_id 0 = "default" (cleared/normal), starts from 1
local _hl_next_id = 1
local _hl_by_id   = {}   -- [id] = attrs table
local _hl_cache   = {}   -- fingerprint -> id
local _hl_groups  = {}   -- [name] = hl_id
local _default_colors = {
    foreground = nil,
    background = nil,
    special = nil,
    cterm_foreground = nil,
    cterm_background = nil,
}

-- Current terminal dimensions (kept as direct fields for backward compat
-- with existing code that does screen.width / screen.height).
Screen.width  = 80
Screen.height = 24

-- -------------------------------------------------------------------------
-- Init
-- -------------------------------------------------------------------------

function Screen.init(backend)
    _backend = backend
    local w, h = backend.size()
    Screen.width  = w
    Screen.height = h

    local fg_r, fg_g, fg_b = backend.get_palette_slot(0)
    local bg_r, bg_g, bg_b = backend.get_palette_slot(15)
    Screen.default_colors_set(
        fg_r * 65536 + fg_g * 256 + fg_b,
        bg_r * 65536 + bg_g * 256 + bg_b,
        nil,
        nil,
        nil
    )
end

-- -------------------------------------------------------------------------
-- Sizing
-- -------------------------------------------------------------------------

function Screen.get_size()
    return Screen.width, Screen.height
end

-- -------------------------------------------------------------------------
-- Frame management
-- -------------------------------------------------------------------------

function Screen.begin_frame()
    _backend.begin_frame()
end

function Screen.flush()
    if _backend.flush then
        _backend.flush()
    else
        _backend.end_frame()
    end
end

function Screen.end_frame()
    Screen.flush()
end

-- -------------------------------------------------------------------------
-- Highlight registry
-- -------------------------------------------------------------------------

local function normalize_attrs(attrs)
    attrs = attrs or {}
    local out = {
        foreground = attrs.foreground ~= nil and attrs.foreground or attrs.fg,
        background = attrs.background ~= nil and attrs.background or attrs.bg,
        special = attrs.special,
        reverse = not not attrs.reverse,
        italic = not not attrs.italic,
        bold = not not attrs.bold,
        strikethrough = not not attrs.strikethrough,
        underline = not not attrs.underline,
        undercurl = not not attrs.undercurl,
        underdouble = not not attrs.underdouble,
        underdotted = not not attrs.underdotted,
        underdashed = not not attrs.underdashed,
        altfont = attrs.altfont,
        blend = attrs.blend,
        url = attrs.url,
        cterm_foreground = attrs.cterm_foreground,
        cterm_background = attrs.cterm_background,
        info = attrs.info,
    }
    out.fg = out.foreground
    out.bg = out.background
    return out
end

local function attrs_equal(a, b)
    return (a.foreground or -1) == (b.foreground or -1)
        and (a.background or -1) == (b.background or -1)
        and (a.special or -1) == (b.special or -1)
        and (a.cterm_foreground or -1) == (b.cterm_foreground or -1)
        and (a.cterm_background or -1) == (b.cterm_background or -1)
        and (a.reverse or false) == (b.reverse or false)
        and (a.italic or false) == (b.italic or false)
        and (a.bold or false) == (b.bold or false)
        and (a.strikethrough or false) == (b.strikethrough or false)
        and (a.underline or false) == (b.underline or false)
        and (a.undercurl or false) == (b.undercurl or false)
        and (a.underdouble or false) == (b.underdouble or false)
        and (a.underdotted or false) == (b.underdotted or false)
        and (a.underdashed or false) == (b.underdashed or false)
        and (a.altfont or 0) == (b.altfont or 0)
        and (a.blend or -1) == (b.blend or -1)
        and (a.url or "") == (b.url or "")
end

-- Build a stable string fingerprint for an attrs table.
-- attrs = { fg=int, bg=int, bold=bool, italic=bool, underline=bool,
--           strikethrough=bool, reverse=bool }
local function hl_fingerprint(attrs)
    attrs = normalize_attrs(attrs)
    return table.concat({
        tostring(attrs.foreground or -1),
        tostring(attrs.background or -1),
        tostring(attrs.special or -1),
        tostring(attrs.cterm_foreground or -1),
        tostring(attrs.cterm_background or -1),
        attrs.bold         and "B" or "",
        attrs.italic       and "I" or "",
        attrs.underline    and "U" or "",
        attrs.undercurl    and "C" or "",
        attrs.underdouble  and "D" or "",
        attrs.underdotted  and "O" or "",
        attrs.underdashed  and "A" or "",
        attrs.strikethrough and "S" or "",
        attrs.reverse      and "R" or "",
        attrs.altfont and ("F" .. tostring(attrs.altfont)) or "",
        attrs.blend and ("L" .. tostring(attrs.blend)) or "",
        attrs.url and ("@" .. attrs.url) or "",
    }, ":")
end

--- Register or retrieve an hl_id for the given attrs.
--- Auto-defines if new; notifies backend via hl_define.
---@param attrs table  {fg=0xRRGGBB, bg=0xRRGGBB, bold=bool, ...}
---@return integer  hl_id (>= 1)
function Screen.hl_id_for(attrs)
    attrs = normalize_attrs(attrs)
    if attrs_equal(attrs, _hl_by_id[0]) then
        return 0
    end
    local fp = hl_fingerprint(attrs)
    local id = _hl_cache[fp]
    if id then return id end

    id = _hl_next_id
    _hl_next_id = _hl_next_id + 1
    _hl_by_id[id] = attrs
    _hl_cache[fp] = id
    _backend.hl_define(id, attrs)
    return id
end

function Screen.default_colors_set(rgb_fg, rgb_bg, rgb_sp, cterm_fg, cterm_bg)
    _default_colors.foreground = rgb_fg
    _default_colors.background = rgb_bg
    _default_colors.special = rgb_sp
    _default_colors.cterm_foreground = cterm_fg
    _default_colors.cterm_background = cterm_bg

    _hl_by_id[0] = normalize_attrs({
        foreground = rgb_fg,
        background = rgb_bg,
        special = rgb_sp,
        cterm_foreground = cterm_fg,
        cterm_background = cterm_bg,
    })

    if _backend.default_colors_set then
        _backend.default_colors_set(rgb_fg, rgb_bg, rgb_sp, cterm_fg, cterm_bg)
    end
end

function Screen.default_colors()
    return _default_colors
end

function Screen.hl_attr_define(id, rgb_attr, cterm_attr, info)
    local attrs = normalize_attrs({
        foreground = rgb_attr and rgb_attr.foreground,
        background = rgb_attr and rgb_attr.background,
        special = rgb_attr and rgb_attr.special,
        reverse = rgb_attr and rgb_attr.reverse,
        italic = rgb_attr and rgb_attr.italic,
        bold = rgb_attr and rgb_attr.bold,
        strikethrough = rgb_attr and rgb_attr.strikethrough,
        underline = rgb_attr and rgb_attr.underline,
        undercurl = rgb_attr and rgb_attr.undercurl,
        underdouble = rgb_attr and rgb_attr.underdouble,
        underdotted = rgb_attr and rgb_attr.underdotted,
        underdashed = rgb_attr and rgb_attr.underdashed,
        altfont = rgb_attr and rgb_attr.altfont,
        blend = rgb_attr and rgb_attr.blend,
        url = rgb_attr and rgb_attr.url,
        cterm_foreground = cterm_attr and cterm_attr.foreground,
        cterm_background = cterm_attr and cterm_attr.background,
        info = info,
    })
    Screen.hl_define(id, attrs)
end

--- Define an hl_id explicitly (e.g. imported from Neovim RPC).
function Screen.hl_define(id, attrs)
    attrs = normalize_attrs(attrs)
    _hl_by_id[id] = attrs
    local fp = hl_fingerprint(attrs)
    _hl_cache[fp] = id
    _backend.hl_define(id, attrs)
    if id >= _hl_next_id then
        _hl_next_id = id + 1
    end
end

--- Return the attrs table for a given hl_id.
function Screen.hl_attrs(hl_id)
    return _hl_by_id[hl_id]
end

function Screen.hl_group_set(name, hl_id)
    _hl_groups[name] = hl_id
end

function Screen.hl_group_id(name)
    return _hl_groups[name]
end

-- -------------------------------------------------------------------------
-- Grid events
-- -------------------------------------------------------------------------

--- Emit a line of cells to the grid.
--- grid: integer (1 = global screen)
--- row, col: 0-indexed
--- cells: array of { char, hl_id, repeat_count }
---   hl_id nil = inherit previous cell's hl_id
function Screen.grid_line(grid, row, col, cells, wrap)
    _backend.grid_line(grid, row, col, cells, wrap or false)
end

--- Move the visible cursor.
--- row, col: 0-indexed
function Screen.grid_cursor_goto(grid, row, col)
    _backend.grid_cursor_goto(grid, row, col)
end

--- Fill the entire grid with empty cells (default hl).
function Screen.grid_clear(grid)
    _backend.grid_clear(grid)
end

function Screen.grid_destroy(grid)
    if _backend.grid_destroy then
        _backend.grid_destroy(grid)
    end
end

--- Notify backend of a grid size change.
function Screen.grid_resize(grid, w, h)
    if grid == 1 then
        Screen.width  = w
        Screen.height = h
    end
    if _backend.grid_resize then
        _backend.grid_resize(grid, w, h)
    end
end

function Screen.grid_scroll(grid, top, bot, left, right, rows, cols)
    if _backend.grid_scroll then
        _backend.grid_scroll(grid, top, bot, left, right, rows, cols or 0)
    end
end

-- -------------------------------------------------------------------------
-- Capability API
-- -------------------------------------------------------------------------

--- Returns "0", "16", "256", or "rgb" depending on backend capability.
function Screen.color_depth()
    return _backend.color_depth()
end

--- Returns true if per-slot RGB palette programming is supported.
function Screen.supports_palette()
    return _backend.supports_palette()
end

--- Program a palette slot (0-15) with an RGB value.
--- No-op if supports_palette() is false.
function Screen.set_palette_slot(slot, r, g, b)
    _backend.set_palette_slot(slot, r, g, b)
end

--- Query current RGB of a palette slot (0-15).
function Screen.get_palette_slot(slot)
    return _backend.get_palette_slot(slot)
end

return Screen
