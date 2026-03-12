--[[
    Handles text highlighting and color management.
]]

local Highlight = {}

local AliasTable = loadModule("lib.aliastable")
local Error = loadModule("lib.error")
local HL_VERSION = 1

local PALETTE_ORDER = {
    colors.white,
    colors.orange,
    colors.magenta,
    colors.lightBlue,
    colors.yellow,
    colors.lime,
    colors.pink,
    colors.gray,
    colors.lightGray,
    colors.cyan,
    colors.purple,
    colors.blue,
    colors.brown,
    colors.green,
    colors.red,
    colors.black,
}

local function bump_version()
    HL_VERSION = HL_VERSION + 1
end

--- The actual color palette used for the screen terminal.
local palette = {}
for i = 1, #PALETTE_ORDER do
    local slot = PALETTE_ORDER[i]
    palette[slot] = colors.packRGB(term.getPaletteColor(slot))
end

local DEFAULT_SLOT_RGB = {}
for i = 1, #PALETTE_ORDER do
    local slot = PALETTE_ORDER[i]
    DEFAULT_SLOT_RGB[slot] = palette[slot]
end

local ROOT_SLOT_RGB = {}
for i = 1, #PALETTE_ORDER do
    local slot = PALETTE_ORDER[i]
    ROOT_SLOT_RGB[slot] = palette[slot]
end

local IMPORTANT_GROUP_WEIGHTS = {
    Normal = 8,
    StatusLine = 6,
    StatusLineNC = 4,
    WinSeparator = 4,
    VertSplit = 4,
    TabLine = 4,
    TabLineSel = 5,
    NonText = 5,
    EndOfBuffer = 5,
    CursorLine = 3,
    CursorLineNr = 3,
    CursorColumn = 3,
    Visual = 3,
    Search = 3,
    IncSearch = 3,
    Pmenu = 3,
    PmenuSel = 3,
    Error = 4,
    ErrorMsg = 4,
    WarningMsg = 3,
    Todo = 3,
    Comment = 2,
    Constant = 2,
    Identifier = 2,
    Statement = 2,
    PreProc = 2,
    Type = 2,
    Special = 2,
    Directory = 2,
    Title = 2,
}

local function copy_palette(src)
    local out = {}
    for i = 1, #PALETTE_ORDER do
        local slot = PALETTE_ORDER[i]
        out[slot] = src[slot]
    end
    return out
end

--- Calculates the distance between two colors.
---@param color1 number The hexadecimal representation of the first color.
---@param color2 number The hex representation of the second color.
---@return number . The distance between the two colors.
local OKLAB_CACHE = {}

local function srgb_to_linear(channel)
    if channel <= 0.04045 then
        return channel / 12.92
    end
    return ((channel + 0.055) / 1.055) ^ 2.4
end

local function colorToOKLab(rgb)
    local cached = OKLAB_CACHE[rgb]
    if cached then
        return cached[1], cached[2], cached[3]
    end

    local r8, g8, b8 = colors.unpackRGB(rgb)
    local r = srgb_to_linear(r8)
    local g = srgb_to_linear(g8)
    local b = srgb_to_linear(b8)

    local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

    local l_ = l ^ (1 / 3)
    local m_ = m ^ (1 / 3)
    local s_ = s ^ (1 / 3)

    local out = {
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    }
    OKLAB_CACHE[rgb] = out
    return out[1], out[2], out[3]
end

local function colorDistance(color1, color2)
    local l1, a1, b1 = colorToOKLab(color1)
    local l2, a2, b2 = colorToOKLab(color2)

    local dl = l1 - l2
    local da = a1 - a2
    local db = b1 - b2

    return math.sqrt(dl * dl + da * da + db * db)
end

local function colorLuminance(rgb)
    local r, g, b = colors.unpackRGB(rgb)
    return 0.30 * r + 0.59 * g + 0.11 * b
end

local function is_palette_index(val)
    return type(val) == "number" and palette[val] ~= nil
end

local function is_palette_ref(val)
    return type(val) == "table" and type(val.palette) == "number"
end

local function is_rgb_ref(val)
    return type(val) == "table" and type(val.rgb) == "number"
end

local function palette_ref(slot)
    return { palette = slot }
end

local function rgb_ref(rgb)
    return { rgb = rgb }
end

local function raw_color_ref(val)
    if val == nil then
        return nil
    end
    if is_palette_ref(val) or is_rgb_ref(val) then
        return val
    end
    if is_palette_index(val) then
        return palette_ref(val)
    end
    return rgb_ref(val)
end

local function color_value_to_rgb(val)
    if val == nil then
        return nil
    end
    if is_rgb_ref(val) then
        return val.rgb
    end
    if is_palette_ref(val) then
        return palette[val.palette]
    end
    if is_palette_index(val) then
        return palette[val]
    end
    return val
end

local tracked_palette_usage = nil

local function record_palette_usage(rgb)
    rgb = color_value_to_rgb(rgb)
    if tracked_palette_usage == nil or type(rgb) ~= "number" then
        return
    end
    tracked_palette_usage[rgb] = (tracked_palette_usage[rgb] or 0) + 1
end

local function make_group(fg, bg, reverse)
    local group = {}
    if fg ~= nil then
        group[1] = fg
        group._raw_fg = rgb_ref(ROOT_SLOT_RGB[fg])
    end
    if bg ~= nil then
        group[2] = bg
        group._raw_bg = rgb_ref(ROOT_SLOT_RGB[bg])
    end
    if reverse then
        group[3] = -1
    end
    return group
end

-- Highlight groups. Items are {fg, bg}. If fg is -1, it reverses the default colors.
-- Namespaced highlight tables. Index = ns_id + 1.
-- Namespace 0 (index 1) is the global namespace containing the default groups.
local function create_default_namespace()
    local hlgroups = AliasTable()
    hlgroups.SpecialKey = make_group(colors.cyan)
    hlgroups._:link("EndOfBuffer", "NonText")
    hlgroups.NonText = make_group(colors.blue)
    hlgroups.Directory = make_group(colors.cyan)
    hlgroups.ErrorMsg = make_group(colors.red)
    hlgroups.IncSearch = make_group(nil, nil, true)
    hlgroups.Search = make_group(colors.black, colors.yellow)
    hlgroups.MoreMsg = make_group(colors.green)
    hlgroups.LineNr = make_group(colors.lightGray)
    hlgroups.CursorLineNr = make_group(colors.yellow)
    hlgroups.Question = make_group(colors.lime)
    hlgroups.StatusLine = make_group(nil, nil, true)
    hlgroups.StatusLineNC = make_group(nil, colors.gray)
    hlgroups._:link("WinSeparator", "Normal")
    hlgroups._:link("VertSplit", "WinSeparator")
    hlgroups.Title = make_group(colors.magenta)
    hlgroups.Visual = make_group(nil, nil, true)
    hlgroups._:link("VisualNOS", "Visual")
    hlgroups.WarningMsg = make_group(colors.red)
    hlgroups.WildMenu = make_group(colors.black, colors.yellow)
    hlgroups.Folded = make_group(colors.cyan, colors.gray)
    hlgroups.FoldColumn = make_group(colors.cyan, colors.lightGray)
    hlgroups.DiffAdd = make_group(nil, colors.blue)
    hlgroups.DiffChange = make_group(nil, colors.purple)
    hlgroups.DiffDelete = make_group(colors.blue, colors.cyan)
    hlgroups.DiffText = make_group(nil, colors.red)
    hlgroups.SignColumn = make_group(colors.cyan, colors.gray)
    hlgroups._:link("CursorLineSign", "SignColumn")
    hlgroups.SpellBad = make_group(colors.gray, colors.red)
    hlgroups.SpellCap = make_group(colors.gray, colors.blue)
    hlgroups.SpellRare = make_group(colors.gray, colors.magenta)
    hlgroups.SpellLocal = make_group(colors.gray, colors.cyan)
    hlgroups.Pmenu = make_group(nil, colors.magenta)
    hlgroups.PmenuSel = make_group(nil, colors.gray)
    hlgroups.PMenuSbar = make_group(nil, colors.lightGray)
    hlgroups.PmenuThumb = make_group(nil, colors.white)
    hlgroups._:link("Tabline", "StatusLineNC")
    hlgroups._:link("TablineFill", "Tabline")
    hlgroups.CursorColumn = make_group(nil, colors.lightGray)
    hlgroups.CursorLine = make_group(nil, colors.lightGray)
    hlgroups.ColorColumn = make_group(nil, colors.red)
    hlgroups.Cursor = make_group(nil, nil, true)
    hlgroups.lCursor = make_group(nil, nil, true)
    hlgroups.MatchParen = make_group(nil, colors.cyan)
    hlgroups.Comment = make_group(colors.green)
    hlgroups.Constant = make_group(colors.red)
    hlgroups._:link("String", "Constant")
    hlgroups._:link("Character", "Constant")
    hlgroups.Number = make_group(colors.lime)
    hlgroups.Boolean = make_group(colors.blue)
    hlgroups._:link("Float", "Number")
    hlgroups.Identifier = make_group(colors.lightBlue)
    hlgroups.Function = make_group(colors.yellow)
    hlgroups.Statement = make_group(colors.white)
    hlgroups._:link("Conditional", "Statement")
    hlgroups._:link("Repeat", "Statement")
    hlgroups._:link("Label", "Statement")
    hlgroups._:link("Operator", "Statement")
    hlgroups.Keyword = make_group(colors.purple)
    hlgroups._:link("Exception", "Statement")
    hlgroups.PreProc = make_group(colors.pink)
    hlgroups._:link("Include", "PreProc")
    hlgroups._:link("Define", "PreProc")
    hlgroups._:link("Macro", "PreProc")
    hlgroups._:link("PreCondit", "PreProc")
    hlgroups.Type = make_group(colors.lime)
    hlgroups._:link("StorageClass", "Type")
    hlgroups._:link("Structure", "Type")
    hlgroups._:link("Typedef", "Type")
    hlgroups.Special = make_group(colors.orange)
    hlgroups._:link("SpecialChar", "Special")
    hlgroups._:link("Tag", "Special")
    hlgroups._:link("Delimiter", "Normal")
    hlgroups._:link("SpecialComment", "Special")
    hlgroups._:link("Debug", "Special")
    hlgroups.Underlined = make_group(colors.purple)
    hlgroups.Ignore = make_group(colors.black)
    hlgroups.Error = make_group(colors.white, colors.red)
    hlgroups.Todo = make_group(colors.black, colors.yellow)
    hlgroups.Field = make_group(colors.green)
    hlgroups._:link("MsgArea", "Normal")
    hlgroups._:link("MsgSeparator", "StatusLine")
    hlgroups.Normal = make_group(colors.white, colors.black)
    hlgroups.Nil = make_group(colors.blue)
    return hlgroups
end

local hlns = { create_default_namespace() }

-- Convenience accessor (creates namespace table lazily).
local function ns_table(ns)
    ns = ns or 0
    local idx = ns + 1
    local t = hlns[idx]
    if not t then
        t = AliasTable()
        hlns[idx] = t
    end
    return t, ns, idx
end

local ROOT_BACKGROUND = colors.black
local ROOT_FOREGROUND = colors.white

local function resolved_normal_colors(ns)
    local tbl = ns_table(ns)
    local stored = tbl.Normal

    if (not stored or #stored == 0) and ns and ns ~= 0 then
        stored = hlns[1].Normal
    end
    stored = stored or {}

    local fg = stored[1]
    local bg = stored[2]
    if fg == nil then fg = ROOT_FOREGROUND end
    if bg == nil then bg = ROOT_BACKGROUND end

    if stored[3] == -1 then
        fg, bg = bg, fg
    end

    return fg, bg
end

function Highlight.For(name, ns, nodefault)
    -- Fetch the stored (raw) definition without modifying it.
    local tbl = ns_table(ns)
    local stored = tbl[name]

    if (not stored or #stored == 0) and ns and ns ~= 0 then
        -- Fallback to global namespace if missing/cleared in this namespace
        stored = hlns[1][name]
    end
    stored = stored or {}
    local reverse = (stored[3] == -1)
    local fg = stored[1]
    local bg = stored[2]

    if not nodefault then
        if name == "Normal" then
            if fg == nil then fg = ROOT_FOREGROUND end
            if bg == nil then bg = ROOT_BACKGROUND end
        else
            local normal_fg, normal_bg = resolved_normal_colors(ns)
            if fg == nil then fg = normal_fg end
            if bg == nil then bg = normal_bg end
        end
    end

    if reverse then
        fg, bg = bg, fg
    end

    return { fg, bg }
end

function Highlight.SetFor(name, ns)
    local hl = Highlight.For(name, ns)

    term.setTextColor(hl[1])
    term.setBackgroundColor(hl[2])
end

function Highlight.RawFor(name, ns)
    return ns_table(ns)[name]
end

function Highlight.GroupExists(name, ns)
    local tbl = ns_table(ns)
    return tbl[name] ~= nil
end

function Highlight.Link(name, target, ns, force)
    local tbl = ns_table(ns)
    if force then
        if tbl._:hasLinkKey(name) then
            tbl._:unlink(name)
        end
        tbl[name] = nil
    elseif tbl._:hasConcreteKey(name) then
        return Error(414)
    end
    tbl._:link(name, target)
    bump_version()
end

function Highlight.Clear(name, ns)
    local tbl, namespace, idx = ns_table(ns)
    if name == nil then
        if namespace == 0 then
            hlns[idx] = create_default_namespace()
        else
            hlns[idx] = AliasTable()
        end
        bump_version()
        return
    end
    if tbl._:hasLinkKey(name) then tbl._:unlink(name) end
    tbl[name] = {}
    bump_version()
end

function Highlight.HasGroup(name, ns)
    local tbl = ns_table(ns)
    if tbl._:hasKey(name) then return true end
    if ns and ns ~= 0 then
        return hlns[1]._:hasKey(name)
    end
end

function Highlight.ListNames(ns)
    local names = {}
    local seen = {}

    local function collect(tbl)
        for name, _ in pairs(tbl) do
            if type(name) == "string" and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
            end
        end
    end

    if ns and ns ~= 0 and hlns[1] then
        collect(hlns[1])
    end
    collect(ns_table(ns))
    table.sort(names)
    return names
end

function Highlight.ListingSuffix(name, ns)
    local tbl = ns_table(ns)
    if tbl._:hasLinkKey(name) then
        return " links to " .. tostring(tbl._:getLink(name))
    end

    local raw = tbl[name]
    if (raw == nil or #raw == 0) and ns and ns ~= 0 then
        raw = hlns[1][name]
    end

    if raw == nil then
        return ""
    end
    if #raw == 0 then
        return " cleared"
    end
    return ""
end

local function findClosestColor(val)
    if is_palette_ref(val) then
        return val.palette
    end
    if is_rgb_ref(val) then
        val = val.rgb
    elseif is_palette_index(val) then
        return val
    end

    local closest = math.huge
    local colorKey
    for k, v in pairs(palette) do
        local dist = colorDistance(v, val)
        if dist < closest then
            closest = dist
            colorKey = k
        end
    end
    return colorKey
end

function Highlight.SetGroupColor(name, which, val, ns)
    local color = findClosestColor(val)
    local raw = raw_color_ref(val)

    local tbl = ns_table(ns)
    if tbl._:hasLinkKey(name) then
        tbl._:unlink(name)
    end
    local hl = tbl._:hasConcreteKey(name) and tbl[name] or {}
    if which == "fg" then
        hl[1] = color
        hl._raw_fg = raw
        record_palette_usage(raw)
    elseif which == "bg" then
        hl[2] = color
        hl._raw_bg = raw
        record_palette_usage(raw)
    else
        error("Unknown/unhandled color location: " .. which)
    end
    tbl[name] = hl
    bump_version()
end

function Highlight.SetGroupReverse(name, reverse, ns)
    local tbl = ns_table(ns)
    if tbl._:hasLinkKey(name) then
        tbl._:unlink(name)
    end
    local hl = tbl._:hasConcreteKey(name) and tbl[name] or {}
    if reverse then
        hl[3] = -1
    else
        hl[3] = nil
    end
    tbl[name] = hl
    bump_version()
end

-- Follows api from nvim_set_hl
function Highlight.SetHL(ns, name, val)
    if val.link then
        Highlight.Link(name, val.link, ns)
        return
    end

    local tbl = ns_table(ns)
    local newval = {}

    if val.fg == "fg" then
        local hlfor = Highlight.For("Normal")
        if not hlfor[1] then
            error("Normal not defined")
        end
        newval[1] = hlfor[1]
        local normal_raw = Highlight.RawFor("Normal")
        newval._raw_fg = (normal_raw and normal_raw._raw_fg) or raw_color_ref(newval[1])
        record_palette_usage(newval._raw_fg)
    elseif val.fg ~= nil then
        newval[1] = findClosestColor(val.fg)
        newval._raw_fg = raw_color_ref(val.fg)
        record_palette_usage(newval._raw_fg)
    end

    if val.bg == "bg" then
        local hlfor = Highlight.For("Normal")
        if not hlfor[2] then
            error("Normal not defined")
        end
        newval[2] = hlfor[2]
        local normal_raw = Highlight.RawFor("Normal")
        newval._raw_bg = (normal_raw and normal_raw._raw_bg) or raw_color_ref(newval[2])
        record_palette_usage(newval._raw_bg)
    elseif val.bg ~= nil then
        newval[2] = findClosestColor(val.bg)
        newval._raw_bg = raw_color_ref(val.bg)
        record_palette_usage(newval._raw_bg)
    end

    if val.reverse then
        newval[3] = -1
    end

    tbl[name] = newval
    bump_version()
end

function Highlight.GetLink(name, ns)
    local tbl = ns_table(ns)
    local link = tbl._:getLink(name)
    if not link and ns and ns ~= 0 then
        return hlns[1]._:getLink(name)
    end
    return link
end

local function palette_entry_weight(entry)
    return IMPORTANT_GROUP_WEIGHTS[entry.group] or 1
end

local function usage_items(entries)
    local usage = {}
    for i = 1, #entries do
        local entry = entries[i]
        local weight = palette_entry_weight(entry)
        usage[entry.rgb] = (usage[entry.rgb] or 0) + weight
    end

    local items = {}
    for rgb, weight in pairs(usage) do
        items[#items + 1] = { rgb = rgb, weight = weight }
    end
    table.sort(items, function(a, b)
        if a.weight == b.weight then
            return a.rgb < b.rgb
        end
        return a.weight > b.weight
    end)
    return items
end

local function palette_cost(items, centers)
    local total = 0
    for i = 1, #items do
        local item = items[i]
        local best = math.huge
        for j = 1, #centers do
            local dist = colorDistance(item.rgb, centers[j])
            if dist < best then
                best = dist
            end
        end
        total = total + best * item.weight
    end
    return total
end

local function seeded_centers(items, wanted)
    local centers = {}
    if #items == 0 then
        return centers
    end
    if #items <= wanted then
        for i = 1, #items do
            centers[i] = items[i].rgb
        end
        return centers
    end

    local selected = {}
    local best_cost = math.huge
    for i = 1, #items do
        local rgb = items[i].rgb
        local cost = palette_cost(items, { rgb })
        if cost < best_cost or (cost == best_cost and rgb < centers[1]) then
            centers[1] = rgb
            best_cost = cost
        end
    end
    selected[centers[1]] = true

    while #centers < wanted do
        local best_rgb, next_cost = nil, math.huge
        for i = 1, #items do
            local rgb = items[i].rgb
            if not selected[rgb] then
                local trial = {}
                for j = 1, #centers do
                    trial[j] = centers[j]
                end
                trial[#trial + 1] = rgb
                local cost = palette_cost(items, trial)
                if cost < next_cost or (cost == next_cost and rgb < best_rgb) then
                    best_rgb = rgb
                    next_cost = cost
                end
            end
        end
        selected[best_rgb] = true
        centers[#centers + 1] = best_rgb
    end
    return centers
end

local function refine_centers(items, centers)
    if #items <= #centers then
        return centers
    end

    local selected = {}
    for i = 1, #centers do
        selected[centers[i]] = true
    end

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
            if improved then
                break
            end
            centers[i] = old_rgb
            selected[old_rgb] = true
        end
    end

    return centers
end

local function assign_palette_slots(centers)
    local slot_colors = {}
    local remaining = {}
    for i = 1, #centers do
        remaining[i] = centers[i]
    end

    local function take_extreme(want_darkest)
        if #remaining == 0 then
            return nil
        end
        local best_idx = 1
        local best_luma = colorLuminance(remaining[1])
        for i = 2, #remaining do
            local luma = colorLuminance(remaining[i])
            local better = want_darkest and luma < best_luma or luma > best_luma
            if better then
                best_idx = i
                best_luma = luma
            end
        end
        return table.remove(remaining, best_idx)
    end

    slot_colors[colors.black] = take_extreme(true) or DEFAULT_SLOT_RGB[colors.black]
    slot_colors[colors.white] = take_extreme(false) or DEFAULT_SLOT_RGB[colors.white]

    for i = 1, #PALETTE_ORDER do
        local slot = PALETTE_ORDER[i]
        if slot_colors[slot] == nil then
            if #remaining == 0 then
                slot_colors[slot] = DEFAULT_SLOT_RGB[slot]
            else
                local best_idx, best_dist = 1, math.huge
                for j = 1, #remaining do
                    local dist = colorDistance(DEFAULT_SLOT_RGB[slot], remaining[j])
                    if dist < best_dist then
                        best_idx = j
                        best_dist = dist
                    end
                end
                slot_colors[slot] = table.remove(remaining, best_idx)
            end
        end
    end

    return slot_colors
end

local function fallback_palette_entries()
    local entries = {}
    for i = 1, #hlns do
        local tbl = hlns[i]
        if tbl then
            for name, raw in pairs(tbl) do
                if type(name) == "string" and type(raw) == "table" and #raw > 0 then
                    local fg = color_value_to_rgb(raw._raw_fg) or (raw[1] and palette[raw[1]] or nil)
                    local bg = color_value_to_rgb(raw._raw_bg) or (raw[2] and palette[raw[2]] or nil)
                    if fg ~= nil then
                        entries[#entries + 1] = { group = name, role = "fg", rgb = fg }
                    end
                    if bg ~= nil then
                        entries[#entries + 1] = { group = name, role = "bg", rgb = bg }
                    end
                end
            end
        end
    end
    return entries
end

local function remap_namespace(tbl, old_palette)
    for name, raw in pairs(tbl) do
        if type(name) == "string" and type(raw) == "table" and #raw > 0 then
            local fg = raw._raw_fg
            local bg = raw._raw_bg
            if fg == nil and raw[1] ~= nil then
                fg = old_palette[raw[1]]
            end
            if bg == nil and raw[2] ~= nil then
                bg = old_palette[raw[2]]
            end
            if fg ~= nil then
                raw._raw_fg = fg
                raw[1] = findClosestColor(fg)
            end
            if bg ~= nil then
                raw._raw_bg = bg
                raw[2] = findClosestColor(bg)
            end
        end
    end
end

function Highlight.CapturePalette(target)
    target = target or term
    local captured = {}
    for i = 1, #PALETTE_ORDER do
        local slot = PALETTE_ORDER[i]
        captured[slot] = colors.packRGB(target.getPaletteColor(slot))
    end
    return captured
end

function Highlight.GetPalette()
    return copy_palette(palette)
end

function Highlight.BeginPaletteTracking()
    tracked_palette_usage = {}
end

function Highlight.SetPalette(next_palette, target)
    target = target or term
    for i = 1, #PALETTE_ORDER do
        local slot = PALETTE_ORDER[i]
        local r, g, b = colors.unpackRGB(next_palette[slot])
        target.setPaletteColor(slot, r, g, b)
    end
end

function Highlight.ResetPalette(target)
    for i = 1, #PALETTE_ORDER do
        local slot = PALETTE_ORDER[i]
        palette[slot] = ROOT_SLOT_RGB[slot]
    end
    Highlight.SetPalette(palette, target)
end

function Highlight.CancelPaletteTracking()
    tracked_palette_usage = nil
end

function Highlight.CommitPaletteTracking()
    local entries = fallback_palette_entries()
    tracked_palette_usage = nil
    if #entries == 0 then
        return false
    end

    local items = usage_items(entries)
    local centers = seeded_centers(items, #PALETTE_ORDER)
    centers = refine_centers(items, centers)
    local slot_colors = assign_palette_slots(centers)
    local old_palette = copy_palette(palette)

    for i = 1, #PALETTE_ORDER do
        local slot = PALETTE_ORDER[i]
        local rgb = slot_colors[slot]
        palette[slot] = rgb
    end
    Highlight.SetPalette(palette)

    for i = 1, #hlns do
        if hlns[i] then
            remap_namespace(hlns[i], old_palette)
        end
    end

    bump_version()
    return true
end

local HL_ID, ID_NAME, NEXT_HL_ID = {}, {}, 1

function Highlight.IdByName(name)
    local id = HL_ID[name]
    if not id then
        id = NEXT_HL_ID
        NEXT_HL_ID = NEXT_HL_ID + 1
        HL_ID[name], ID_NAME[id] = id, name
    end
    return id
end

function Highlight.NameById(id)
    return ID_NAME[id]
end

function Highlight.Version()
    return HL_VERSION
end

return Highlight
