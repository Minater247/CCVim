--[[
    Handles text highlighting and color management.
]]

local Highlight = {}

local AliasTable = loadModule("lib.aliastable")
local Error = loadModule("lib.error")
local HL_VERSION = 1

local function bump_version()
    HL_VERSION = HL_VERSION + 1
end

--- The actual color palette used for the screen terminal.
local palette = {
    [colors.white] = colors.packRGB(term.getPaletteColor(colors.white)),
    [colors.orange] = colors.packRGB(term.getPaletteColor(colors.orange)),
    [colors.magenta] = colors.packRGB(term.getPaletteColor(colors.magenta)),
    [colors.lightBlue] = colors.packRGB(term.getPaletteColor(colors.lightBlue)),
    [colors.yellow] = colors.packRGB(term.getPaletteColor(colors.yellow)),
    [colors.lime] = colors.packRGB(term.getPaletteColor(colors.lime)),
    [colors.pink] = colors.packRGB(term.getPaletteColor(colors.pink)),
    [colors.gray] = colors.packRGB(term.getPaletteColor(colors.gray)),
    [colors.lightGray] = colors.packRGB(term.getPaletteColor(colors.lightGray)),
    [colors.cyan] = colors.packRGB(term.getPaletteColor(colors.cyan)),
    [colors.purple] = colors.packRGB(term.getPaletteColor(colors.purple)),
    [colors.blue] = colors.packRGB(term.getPaletteColor(colors.blue)),
    [colors.brown] = colors.packRGB(term.getPaletteColor(colors.brown)),
    [colors.green] = colors.packRGB(term.getPaletteColor(colors.green)),
    [colors.red] = colors.packRGB(term.getPaletteColor(colors.red)),
    [colors.black] = colors.packRGB(term.getPaletteColor(colors.black)),
}

--- Calculates the distance between two colors.
---@param color1 number The hexadecimal representation of the first color.
---@param color2 number The hex representation of the second color.
---@return number . The distance between the two colors.
local function colorDistance(color1, color2)
    local r1, g1, b1 = colors.unpackRGB(color1)
    local r2, g2, b2 = colors.unpackRGB(color2)

    local dr = (r1 - r2)
    local dg = (g1 - g2)
    local db = (b1 - b2)

    return math.sqrt(0.30 * dr * dr + 0.59 * dg * dg + 0.11 * db * db)
end

local function is_palette_index(val)
    return type(val) == "number" and palette[val] ~= nil
end

---Highlight groups. Items are {fg, bg}. If fg is -1, it reverses the default colors.
-- Namespaced highlight tables. Index = ns_id + 1.
-- Namespace 0 (index 1) is the global namespace containing the default groups.
local hlns = { AliasTable() }

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
--#region defaults
do
    local hlgroups = hlns[1] -- global namespace table
    hlgroups.SpecialKey = { colors.cyan }
    hlgroups._:link("EndOfBuffer", "NonText")
    hlgroups.NonText = { colors.blue }
    hlgroups.Directory = { colors.cyan }
    hlgroups.ErrorMsg = { colors.red }
    hlgroups.IncSearch = { nil, nil, -1 }
    hlgroups.Search = { colors.black, colors.yellow }
    hlgroups.MoreMsg = { colors.green }
    hlgroups.LineNr = { colors.lightGray }
    hlgroups.CursorLineNr = { colors.yellow }
    hlgroups.Question = { colors.lime }
    hlgroups.StatusLine = { nil, nil, -1 }
    hlgroups.StatusLineNC = { nil, colors.gray }
    hlgroups._:link("WinSeparator", "Normal")
    hlgroups._:link("VertSplit", "WinSeparator")
    hlgroups.Title = { colors.magenta }
    hlgroups.Visual = { nil, nil, -1 }
    hlgroups._:link("VisualNOS", "Visual")
    hlgroups.WarningMsg = { colors.red }
    hlgroups.WildMenu = { colors.black, colors.yellow }
    hlgroups.Folded = { colors.cyan, colors.gray }
    hlgroups.FoldColumn = { colors.cyan, colors.lightGray }
    hlgroups.DiffAdd = { nil, colors.blue }
    hlgroups.DiffChange = { nil, colors.purple }
    hlgroups.DiffDelete = { colors.blue, colors.cyan }
    hlgroups.DiffText = { nil, colors.red }
    hlgroups.SignColumn = { colors.cyan, colors.gray }
    hlgroups._:link("CursorLineSign", "SignColumn")
    hlgroups.SpellBad = { colors.gray, colors.red }
    hlgroups.SpellCap = { colors.gray, colors.blue }
    hlgroups.SpellRare = { colors.gray, colors.magenta }
    hlgroups.SpellLocal = { colors.gray, colors.cyan }
    hlgroups.Pmenu = { nil, colors.magenta }
    hlgroups.PmenuSel = { nil, colors.gray }
    hlgroups.PMenuSbar = { nil, colors.lightGray }
    hlgroups.PmenuThumb = { nil, colors.white }
    hlgroups._:link("Tabline", "StatusLineNC")
    hlgroups._:link("TablineFill", "Tabline")
    hlgroups.CursorColumn = { nil, colors.lightGray }
    hlgroups.CursorLine = { nil, colors.lightGray }
    hlgroups.ColorColumn = { nil, colors.red }
    hlgroups.Cursor = { nil, nil, -1 }
    hlgroups.lCursor = { nil, nil, -1 }
    hlgroups.MatchParen = { nil, colors.cyan }
    hlgroups.Comment = { colors.green }
    hlgroups.Constant = { colors.red }
    hlgroups._:link("String", "Constant")
    hlgroups._:link("Character", "Constant")
    hlgroups.Number = { colors.lime }
    hlgroups.Boolean = { colors.blue }
    hlgroups._:link("Float", "Number")
    hlgroups.Identifier = { colors.lightBlue }
    hlgroups.Function = { colors.yellow }
    hlgroups.Statement = { colors.white }
    hlgroups._:link("Conditional", "Statement")
    hlgroups._:link("Repeat", "Statement")
    hlgroups._:link("Label", "Statement")
    hlgroups._:link("Operator", "Statement")
    hlgroups.Keyword = { colors.purple }
    hlgroups._:link("Exception", "Statement")
    hlgroups.PreProc = { colors.pink }
    hlgroups._:link("Include", "PreProc")
    hlgroups._:link("Define", "PreProc")
    hlgroups._:link("Macro", "PreProc")
    hlgroups._:link("PreCondit", "PreProc")
    hlgroups.Type = { colors.lime }
    hlgroups._:link("StorageClass", "Type")
    hlgroups._:link("Structure", "Type")
    hlgroups._:link("Typedef", "Type")
    hlgroups.Special = { colors.orange }
    hlgroups._:link("SpecialChar", "Special")
    hlgroups._:link("Tag", "Special")
    hlgroups._:link("Delimiter", "Normal")
    hlgroups._:link("SpecialComment", "Special")
    hlgroups._:link("Debug", "Special")
    hlgroups.Underlined = { colors.purple }
    hlgroups.Ignore = { colors.black }
    hlgroups.Error = { colors.white, colors.red }
    hlgroups.Todo = { colors.black, colors.yellow }
    hlgroups.Field = { colors.green }
    hlgroups._:link("MsgArea", "Normal")
    hlgroups._:link("MsgSeparator", "StatusLine")
    hlgroups.Normal = { colors.white, colors.black }
end
--#endregion defaults

hlns[1].Nil = { colors.blue }

local background = colors.black
local foreground = colors.white

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
        if fg == nil then fg = foreground end
        if bg == nil then bg = background end
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

function Highlight.Link(name, target, ns)
    local tbl = ns_table(ns)
    if tbl._:hasConcreteKey(name) then
        LOG_DEBUG(name .. "HAS CONCRETE")
        return Error(414)
    end
    tbl._:link(name, target)
    bump_version()
end

function Highlight.Clear(name, ns)
    local tbl, _, idx = ns_table(ns)
    if name == nil then
        -- :highlight clear with no group clears the entire namespace
        hlns[idx] = AliasTable()
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

local function findClosestColor(val)
    if is_palette_index(val) then
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

    local tbl = ns_table(ns)
    local hl = tbl[name] or {}
    if which == "fg" then
        hl[1] = color
    elseif which == "bg" then
        hl[2] = color
    else
        error("Unknown/unhandled color location: " .. which)
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
        if normal_raw and normal_raw._raw_fg ~= nil then
            newval._raw_fg = normal_raw._raw_fg
        end
    elseif val.fg ~= nil then
        newval[1] = findClosestColor(val.fg)
        newval._raw_fg = val.fg
    end

    if val.bg == "bg" then
        local hlfor = Highlight.For("Normal")
        if not hlfor[2] then
            error("Normal not defined")
        end
        newval[2] = hlfor[2]
        local normal_raw = Highlight.RawFor("Normal")
        if normal_raw and normal_raw._raw_bg ~= nil then
            newval._raw_bg = normal_raw._raw_bg
        end
    elseif val.bg ~= nil then
        newval[2] = findClosestColor(val.bg)
        newval._raw_bg = val.bg
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
