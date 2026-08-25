--[[
    Handles text highlighting and palette management.
]]

local Highlight = {}

local AliasTable = loadModule("lib.aliastable")
local Error = loadModule("lib.error")
local Color = loadModule("lib.color")

local HL_VERSION = 1

local ROOT_SLOT_RGB = {}
for slot = 0, 15 do
    local r, g, b = screen.get_palette_slot(slot)
    ROOT_SLOT_RGB[slot] = r * 65536 + g * 256 + b
end

local palette = {}
for slot = 0, 15 do
    palette[slot] = ROOT_SLOT_RGB[slot]
end

local ROOT_FOREGROUND = ROOT_SLOT_RGB[0]
local ROOT_BACKGROUND = ROOT_SLOT_RGB[15]

local RGB = {
    white = 0xF0F0F0,
    orange = 0xF2B233,
    magenta = 0xE57FD8,
    lightBlue = 0x99B2F2,
    yellow = 0xDEDE6C,
    lime = 0x7FCC19,
    pink = 0xF2B2CC,
    gray = 0x4C4C4C,
    lightGray = 0x999999,
    cyan = 0x4C99B2,
    purple = 0xB266E5,
    blue = 0x3366CC,
    brown = 0x7F664C,
    green = 0x57A64E,
    red = 0xCC4C4C,
    black = 0x111111,
}

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

local tracked_palette_usage = nil

local HL_ID, ID_NAME, NEXT_HL_ID = {}, {}, 1
local RESOLVED_ID_CACHE = {}

local function bump_version()
    HL_VERSION = HL_VERSION + 1
    RESOLVED_ID_CACHE = {}
end

local function copy_palette(src)
    local out = {}
    for slot = 0, 15 do
        out[slot] = src[slot]
    end
    return out
end

local pack_rgb = Color.pack
local unpack_rgb = Color.unpack

local function slot_from_palette_mask(mask)
    if type(mask) ~= "number" or mask <= 0 then
        return nil
    end

    local slot = 0
    local value = mask
    while value > 1 and value % 2 == 0 do
        value = value / 2
        slot = slot + 1
    end
    if value == 1 and slot <= 15 then
        return slot
    end
end

local function is_palette_ref(val)
    return type(val) == "table" and type(val.palette) == "number"
end

local function is_rgb_ref(val)
    return type(val) == "table" and type(val.rgb) == "number"
end

local function raw_color_ref(val)
    if val == nil then
        return nil
    end
    if is_rgb_ref(val) or is_palette_ref(val) then
        return val
    end

    local slot = slot_from_palette_mask(val)
    if slot ~= nil then
        return { palette = val }
    end
    return { rgb = val }
end

local function color_value_to_rgb(val)
    if val == nil then
        return nil
    end
    if is_rgb_ref(val) then
        return val.rgb
    end
    if is_palette_ref(val) then
        local slot = slot_from_palette_mask(val.palette)
        return slot and palette[slot]
    end

    local slot = slot_from_palette_mask(val)
    if slot ~= nil then
        return palette[slot]
    end
    return val
end

local function record_palette_usage(val)
    if tracked_palette_usage == nil then
        return
    end

    local rgb = color_value_to_rgb(val)
    if rgb == nil then
        return
    end
    tracked_palette_usage[rgb] = (tracked_palette_usage[rgb] or 0) + 1
end

local function invalidate_blit_cache()
    local ok, ScreenDraw = pcall(loadModule, "lib.screendraw")
    if ok and type(ScreenDraw) == "table" and ScreenDraw.invalidate_blit_cache then
        ScreenDraw.invalidate_blit_cache()
    end
end

local function make_group(fg, bg, reverse)
    local group = {}
    if fg ~= nil then
        group[1] = fg
        group._raw_fg = { rgb = fg }
    end
    if bg ~= nil then
        group[2] = bg
        group._raw_bg = { rgb = bg }
    end
    if reverse then
        group[3] = -1
    end
    return group
end

local function create_default_namespace()
    local hlgroups = AliasTable()
    hlgroups.SpecialKey = make_group(RGB.cyan)
    hlgroups._:link("EndOfBuffer", "NonText")
    hlgroups.NonText = make_group(RGB.blue)
    hlgroups.Directory = make_group(RGB.cyan)
    hlgroups.ErrorMsg = make_group(RGB.red)
    hlgroups.IncSearch = make_group(nil, nil, true)
    hlgroups.Search = make_group(RGB.black, RGB.yellow)
    hlgroups.MoreMsg = make_group(RGB.green)
    hlgroups.LineNr = make_group(RGB.lightGray)
    hlgroups.CursorLineNr = make_group(RGB.yellow)
    hlgroups.Question = make_group(RGB.lime)
    hlgroups.StatusLine = make_group(nil, nil, true)
    hlgroups.StatusLineNC = make_group(nil, RGB.gray)
    hlgroups._:link("WinSeparator", "Normal")
    hlgroups._:link("VertSplit", "WinSeparator")
    hlgroups.Title = make_group(RGB.magenta)
    hlgroups.Visual = make_group(nil, nil, true)
    hlgroups._:link("VisualNOS", "Visual")
    hlgroups.WarningMsg = make_group(RGB.red)
    hlgroups.WildMenu = make_group(RGB.black, RGB.yellow)
    hlgroups.Folded = make_group(RGB.cyan, RGB.gray)
    hlgroups.FoldColumn = make_group(RGB.cyan, RGB.lightGray)
    hlgroups.DiffAdd = make_group(nil, RGB.blue)
    hlgroups.DiffChange = make_group(nil, RGB.purple)
    hlgroups.DiffDelete = make_group(RGB.blue, RGB.cyan)
    hlgroups.DiffText = make_group(nil, RGB.red)
    hlgroups.SignColumn = make_group(RGB.cyan, RGB.gray)
    hlgroups._:link("CursorLineSign", "SignColumn")
    hlgroups.SpellBad = make_group(RGB.gray, RGB.red)
    hlgroups.SpellCap = make_group(RGB.gray, RGB.blue)
    hlgroups.SpellRare = make_group(RGB.gray, RGB.magenta)
    hlgroups.SpellLocal = make_group(RGB.gray, RGB.cyan)
    hlgroups.Pmenu = make_group(nil, RGB.magenta)
    hlgroups.PmenuSel = make_group(nil, RGB.gray)
    hlgroups.PMenuSbar = make_group(nil, RGB.lightGray)
    hlgroups.PmenuThumb = make_group(nil, RGB.white)
    hlgroups._:link("Tabline", "StatusLineNC")
    hlgroups._:link("TablineFill", "Tabline")
    hlgroups.CursorColumn = make_group(nil, RGB.lightGray)
    hlgroups.CursorLine = make_group(nil, RGB.lightGray)
    hlgroups.ColorColumn = make_group(nil, RGB.red)
    hlgroups.Cursor = make_group(nil, nil, true)
    hlgroups.lCursor = make_group(nil, nil, true)
    hlgroups.MatchParen = make_group(nil, RGB.cyan)
    hlgroups.Comment = make_group(RGB.green)
    hlgroups.Constant = make_group(RGB.red)
    hlgroups._:link("String", "Constant")
    hlgroups._:link("Character", "Constant")
    hlgroups.Number = make_group(RGB.lime)
    hlgroups.Boolean = make_group(RGB.blue)
    hlgroups._:link("Float", "Number")
    hlgroups.Identifier = make_group(RGB.lightBlue)
    hlgroups.Function = make_group(RGB.yellow)
    hlgroups.Statement = make_group(RGB.white)
    hlgroups._:link("Conditional", "Statement")
    hlgroups._:link("Repeat", "Statement")
    hlgroups._:link("Label", "Statement")
    hlgroups._:link("Operator", "Statement")
    hlgroups.Keyword = make_group(RGB.purple)
    hlgroups._:link("Exception", "Statement")
    hlgroups.PreProc = make_group(RGB.pink)
    hlgroups._:link("Include", "PreProc")
    hlgroups._:link("Define", "PreProc")
    hlgroups._:link("Macro", "PreProc")
    hlgroups._:link("PreCondit", "PreProc")
    hlgroups.Type = make_group(RGB.lime)
    hlgroups._:link("StorageClass", "Type")
    hlgroups._:link("Structure", "Type")
    hlgroups._:link("Typedef", "Type")
    hlgroups.Special = make_group(RGB.orange)
    hlgroups._:link("SpecialChar", "Special")
    hlgroups._:link("Tag", "Special")
    hlgroups._:link("Delimiter", "Normal")
    hlgroups._:link("SpecialComment", "Special")
    hlgroups._:link("Debug", "Special")
    hlgroups.Underlined = make_group(RGB.purple)
    hlgroups.Ignore = make_group(RGB.black)
    hlgroups.Error = make_group(RGB.white, RGB.red)
    hlgroups.Todo = make_group(RGB.black, RGB.yellow)
    hlgroups.Field = make_group(RGB.green)
    hlgroups._:link("MsgArea", "Normal")
    hlgroups._:link("MsgSeparator", "StatusLine")
    hlgroups.Normal = make_group(RGB.white, RGB.black)
    hlgroups.Nil = make_group(RGB.blue)
    return hlgroups
end

local hlns = { create_default_namespace() }

local function ns_table(ns)
    ns = ns or 0
    local idx = ns + 1
    local tbl = hlns[idx]
    if not tbl then
        tbl = AliasTable()
        hlns[idx] = tbl
    end
    return tbl, ns, idx
end

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

local function resolved_normal_cterm_colors(ns)
    local tbl = ns_table(ns)
    local stored = tbl.Normal
    if (not stored or #stored == 0) and ns and ns ~= 0 then
        stored = hlns[1].Normal
    end
    stored = stored or {}
    return stored._cterm_fg, stored._cterm_bg
end

local function resolved_group_colors(name, ns, nodefault)
    local tbl = ns_table(ns)
    local stored = tbl[name]
    if (not stored or #stored == 0) and ns and ns ~= 0 then
        stored = hlns[1][name]
    end
    stored = stored or {}

    local fg = stored[1]
    local bg = stored[2]
    local cterm_fg = stored._cterm_fg
    local cterm_bg = stored._cterm_bg

    if not nodefault then
        if name == "Normal" then
            if fg == nil then fg = ROOT_FOREGROUND end
            if bg == nil then bg = ROOT_BACKGROUND end
        else
            local normal_fg, normal_bg = resolved_normal_colors(ns)
            if fg == nil then fg = normal_fg end
            if bg == nil then bg = normal_bg end

            local normal_cterm_fg, normal_cterm_bg = resolved_normal_cterm_colors(ns)
            if cterm_fg == nil then cterm_fg = normal_cterm_fg end
            if cterm_bg == nil then cterm_bg = normal_cterm_bg end
        end
    end

    if stored[3] == -1 then
        fg, bg = bg, fg
        cterm_fg, cterm_bg = cterm_bg, cterm_fg
    end

    return fg, bg, cterm_fg, cterm_bg
end

local function sync_default_colors()
    local fg, bg, cterm_fg, cterm_bg = resolved_group_colors("Normal", 0, false)
    screen.default_colors_set(fg, bg, nil, cterm_fg, cterm_bg)
end

sync_default_colors()

function Highlight.For(name, ns, nodefault)
    local fg, bg = resolved_group_colors(name, ns, nodefault)
    return { fg, bg }
end

function Highlight.AttrsFor(name, ns, nodefault)
    local fg, bg, cterm_fg, cterm_bg = resolved_group_colors(name, ns, nodefault)
    return {
        fg = fg,
        bg = bg,
        cterm_fg = cterm_fg,
        cterm_bg = cterm_bg,
    }
end

function Highlight.GetId(name, ns)
    local namespace = ns or 0
    local cache = RESOLVED_ID_CACHE[namespace]
    if cache then
        local cached = cache[name]
        if cached ~= nil then
            return cached
        end
    else
        cache = {}
        RESOLVED_ID_CACHE[namespace] = cache
    end

    local fg, bg, cterm_fg, cterm_bg = resolved_group_colors(name, ns, false)
    local id = screen.hl_id_for({
        fg = fg,
        bg = bg,
        cterm_foreground = cterm_fg,
        cterm_background = cterm_bg,
    })
    cache[name] = id
    if namespace == 0 then
        screen.hl_group_set(name, id)
    end
    return id
end

function Highlight.SetFor(name, ns)
    return Highlight.GetId(name, ns)
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
    if (ns or 0) == 0 and name == "Normal" then
        sync_default_colors()
    end
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
        if namespace == 0 then
            sync_default_colors()
        end
        return
    end
    if tbl._:hasLinkKey(name) then
        tbl._:unlink(name)
    end
    tbl[name] = {}
    bump_version()
    if namespace == 0 and name == "Normal" then
        sync_default_colors()
    end
end

function Highlight.HasGroup(name, ns)
    local tbl = ns_table(ns)
    if tbl._:hasKey(name) then
        return true
    end
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

function Highlight.SetGroupColor(name, which, val, ns)
    local rgb = color_value_to_rgb(val)
    local raw = raw_color_ref(val)
    local tbl = ns_table(ns)
    if tbl._:hasLinkKey(name) then
        tbl._:unlink(name)
    end
    local hl = tbl._:hasConcreteKey(name) and tbl[name] or {}

    if which == "fg" then
        hl[1] = rgb
        hl._raw_fg = raw
    elseif which == "bg" then
        hl[2] = rgb
        hl._raw_bg = raw
    else
        error("Unknown/unhandled color location: " .. which)
    end

    record_palette_usage(val)
    tbl[name] = hl
    bump_version()
    if (ns or 0) == 0 and name == "Normal" then
        sync_default_colors()
    end
end

function Highlight.SetGroupReverse(name, reverse, ns)
    local tbl = ns_table(ns)
    if tbl._:hasLinkKey(name) then
        tbl._:unlink(name)
    end
    local hl = tbl._:hasConcreteKey(name) and tbl[name] or {}
    hl[3] = reverse and -1 or nil
    tbl[name] = hl
    bump_version()
    if (ns or 0) == 0 and name == "Normal" then
        sync_default_colors()
    end
end

function Highlight.SetHL(ns, name, val)
    if val.link then
        Highlight.Link(name, val.link, ns)
        return
    end

    local tbl = ns_table(ns)
    local newval = {}

    if val.fg == "fg" then
        local normal = Highlight.For("Normal")
        local normal_raw = Highlight.RawFor("Normal")
        newval[1] = normal[1]
        newval._raw_fg = (normal_raw and normal_raw._raw_fg) or { rgb = normal[1] }
        record_palette_usage(newval._raw_fg)
    elseif val.fg ~= nil then
        newval[1] = color_value_to_rgb(val.fg)
        newval._raw_fg = raw_color_ref(val.fg)
        record_palette_usage(val.fg)
    end

    if val.bg == "bg" then
        local normal = Highlight.For("Normal")
        local normal_raw = Highlight.RawFor("Normal")
        newval[2] = normal[2]
        newval._raw_bg = (normal_raw and normal_raw._raw_bg) or { rgb = normal[2] }
        record_palette_usage(newval._raw_bg)
    elseif val.bg ~= nil then
        newval[2] = color_value_to_rgb(val.bg)
        newval._raw_bg = raw_color_ref(val.bg)
        record_palette_usage(val.bg)
    end

    if val.reverse then
        newval[3] = -1
    end

    if val.cterm_fg ~= nil then
        newval._cterm_fg = val.cterm_fg
    end
    if val.cterm_bg ~= nil then
        newval._cterm_bg = val.cterm_bg
    end

    tbl[name] = newval
    bump_version()
    if (ns or 0) == 0 and name == "Normal" then
        sync_default_colors()
    end
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

local function fallback_palette_entries()
    local entries = {}
    for i = 1, #hlns do
        local tbl = hlns[i]
        if tbl then
            for name, raw in pairs(tbl) do
                if type(name) == "string" and type(raw) == "table" and #raw > 0 then
                    local fg = raw[1] or color_value_to_rgb(raw._raw_fg)
                    local bg = raw[2] or color_value_to_rgb(raw._raw_bg)
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

function Highlight.CapturePalette()
    local captured = {}
    for slot = 0, 15 do
        local r, g, b = screen.get_palette_slot(slot)
        captured[slot] = pack_rgb(r, g, b)
    end
    return captured
end

function Highlight.GetPalette()
    return copy_palette(palette)
end

function Highlight.BeginPaletteTracking()
    tracked_palette_usage = {}
end

function Highlight.SetPalette(next_palette)
    for slot = 0, 15 do
        local rgb = next_palette[slot]
        if rgb ~= nil then
            local r, g, b = unpack_rgb(rgb)
            screen.set_palette_slot(slot, r, g, b)
            palette[slot] = rgb
        end
    end
    bump_version()
    invalidate_blit_cache()
end

function Highlight.ResetPalette()
    palette = copy_palette(ROOT_SLOT_RGB)
    Highlight.SetPalette(palette)
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
    local centers = Color.seeded_centers(items, 16)
    local slot_colors = Color.assign_palette_slots(centers, ROOT_SLOT_RGB)

    for slot = 0, 15 do
        palette[slot] = slot_colors[slot]
    end
    Highlight.SetPalette(palette)
    return true
end

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
