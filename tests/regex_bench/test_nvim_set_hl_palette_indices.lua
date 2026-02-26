local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function make_colors()
    local order = {
        "white", "orange", "magenta", "lightBlue",
        "yellow", "lime", "pink", "gray",
        "lightGray", "cyan", "purple", "blue",
        "brown", "green", "red", "black",
    }
    local t, map = {}, {}
    for i = 1, #order do
        local bit = 2 ^ (i - 1)
        t[order[i]] = bit
        map[bit] = string.format("%x", i - 1)
    end

    t.toBlit = function(bit)
        return map[bit] or "0"
    end

    local function to_byte(v)
        local n = tonumber(v) or 0
        if n <= 1 then
            n = n * 255
        end
        return math.max(0, math.min(255, math.floor(n + 0.5)))
    end

    t.packRGB = function(r, g, b)
        local rr = to_byte(r)
        local gg = to_byte(g)
        local bb = to_byte(b)
        return rr * 0x10000 + gg * 0x100 + bb
    end

    t.unpackRGB = function(rgb)
        if type(rgb) == "number" then
            local rr = math.floor(rgb / 0x10000) % 0x100
            local gg = math.floor(rgb / 0x100) % 0x100
            local bb = rgb % 0x100
            return rr / 255, gg / 255, bb / 255
        elseif type(rgb) == "table" then
            return rgb[1] or 0, rgb[2] or 0, rgb[3] or 0
        end
        return 0, 0, 0
    end

    return t
end

local mock = MockEnv.setup({
    colors = make_colors(),
})

-- Make palette distances deterministic so misuse of palette bit values as RGB
-- is observable in tests.
term.getPaletteColor = function(idx)
    if idx == colors.white then
        return 1, 1, 1
    end
    if idx == colors.black then
        return 0, 0, 0
    end
    return 0.5, 0.5, 0.5
end

local api = mock.loadModule("lib.luaapi.api")
local Fn = mock.loadModule("lib.luaapi.fn")
local Highlight = mock.loadModule("lib.highlight")

-- Direct numeric palette indices should map to the same palette colors.
api.nvim_set_hl(0, "RegressionPaletteNumeric", {
    fg = colors.white,
    bg = colors.black,
})
local direct = Highlight.For("RegressionPaletteNumeric", 0, true)
assert_eq("direct numeric fg preserves white", direct[1], colors.white)
assert_eq("direct numeric bg preserves black", direct[2], colors.black)
local direct_hl = api.nvim_get_hl(0, { name = "RegressionPaletteNumeric", link = false })
assert_eq("nvim_get_hl preserves palette fg", direct_hl.fg, colors.white)
assert_eq("nvim_get_hl preserves palette bg", direct_hl.bg, colors.black)

-- cmp highlight inheritance path: synIDattr('...','fg') returns palette bits.
local pmenu_fg = Fn.synIDattr(Fn.hlID("Pmenu"), "fg")
assert_eq("synIDattr fg returns palette bit", type(pmenu_fg), "number")
api.nvim_set_hl(0, "RegressionFromSynIDattr", {
    fg = pmenu_fg,
    bg = "NONE",
})
local inherited = Highlight.For("RegressionFromSynIDattr", 0, true)
assert_eq("synIDattr-derived fg stays white", inherited[1], colors.white)
assert_eq("NONE background remains unset", inherited[2], nil)
local inherited_hl = api.nvim_get_hl(0, { name = "RegressionFromSynIDattr", link = false })
assert_eq("synIDattr-derived fg preserved", inherited_hl.fg, colors.white)
assert_eq("synIDattr-derived bg unset", inherited_hl.bg, nil)

-- RGB should still be accepted and rendered via nearest palette while retaining
-- the original RGB for API reads.
api.nvim_set_hl(0, "RegressionRgb", {
    fg = 0xFFFFFF,
    bg = 0x000000,
})
local rgb_for = Highlight.For("RegressionRgb", 0, true)
assert_eq("rgb fg maps to white palette for rendering", rgb_for[1], colors.white)
assert_eq("rgb bg maps to black palette for rendering", rgb_for[2], colors.black)
local rgb_hl = api.nvim_get_hl(0, { name = "RegressionRgb", link = false })
assert_eq("nvim_get_hl keeps rgb fg", rgb_hl.fg, 0xFFFFFF)
assert_eq("nvim_get_hl keeps rgb bg", rgb_hl.bg, 0x000000)

print("nvim_set_hl palette-index regression tests: OK")
