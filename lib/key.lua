local Key = {}
Key.__index = Key

-- TODO: support for caps lock

local function C(n)
    return bit32.bor(n, 4096)
end

local function S(n)
    return bit32.bor(n, 8192)
end

local function CS(n)
    return bit32.bor(n, 12288)
end

local printables = {
    [keys.tab] = "Tab",
    [keys.backspace] = "BS",
    [keys.enter] = "CR",
    [keys.space] = "Space",
    [keys.up] = "Up",
    [keys.down] = "Down",
    [keys.left] = "Left",
    [keys.right] = "Right",
    [keys.home] = "Home",
    [keys["end"]] = "End",
    [keys.pageUp] = "PageUp",
    [keys.pageDown] = "PageDown",
    [keys.insert] = "Insert",
    [keys.delete] = "Del",
    [keys.f1] = "F1",
    [keys.f2] = "F2",
    [keys.f3] = "F3",
    [keys.f4] = "F4",
    [keys.f5] = "F5",
    [keys.f6] = "F6",
    [keys.f7] = "F7",
    [keys.f8] = "F8",
    [keys.f9] = "F9",
    [keys.f10] = "F10",
    [keys.f11] = "F11",
    [keys.f12] = "F12",
    [keys.f13] = "F13",
    [keys.f14] = "F14",
    [keys.f15] = "F15",

    [keys.one] = "1",
    [keys.two] = "2",
    [keys.three] = "3",
    [keys.four] = "4",
    [keys.five] = "5",
    [keys.six] = "6",
    [keys.seven] = "7",
    [keys.eight] = "8",
    [keys.nine] = "9",
    [keys.zero] = "0",
    [keys.minus] = "-",
    [keys.equals] = "=",

    [keys.q] = "q",
    [keys.w] = "w",
    [keys.e] = "e",
    [keys.r] = "r",
    [keys.t] = "t",
    [keys.y] = "y",
    [keys.u] = "u",
    [keys.i] = "i",
    [keys.o] = "o",
    [keys.p] = "p",
    [keys.a] = "a",
    [keys.s] = "s",
    [keys.d] = "d",
    [keys.f] = "f",
    [keys.g] = "g",
    [keys.h] = "h",
    [keys.j] = "j",
    [keys.k] = "k",
    [keys.l] = "l",
    [keys.z] = "z",
    [keys.x] = "x",
    [keys.c] = "c",
    [keys.v] = "v",
    [keys.b] = "b",
    [keys.n] = "n",
    [keys.m] = "m",

    [keys.leftBracket] = "[",
    [keys.rightBracket] = "]",
    [keys.semiColon] = ";",
    [keys.apostrophe] = "'",
    [keys.grave] = "`",
    [keys.backslash] = "\\",
    [keys.comma] = ",",
    [keys.period] = ".",
    [keys.slash] = "/",
    [keys.space] = " ",

    [keys.numPad0] = "k0",
    [keys.numPad1] = "k1",
    [keys.numPad2] = "k2",
    [keys.numPad3] = "k3",
    [keys.numPad4] = "k4",
    [keys.numPad5] = "k5",
    [keys.numPad6] = "k6",
    [keys.numPad7] = "k7",
    [keys.numPad8] = "k8",
    [keys.numPad9] = "k9",
    [keys.numPadSubtract] = "kMinus",
    [keys.numPadAdd] = "kPlus",
    [keys.numPadDecimal] = "kPoint",
    [keys.multiply] = "kMultiply",
    [keys.numPadEnter] = "kEnter",
    [keys.numPadDivide] = "kDivide",

    plug = "Plug",
}

local shiftables = {
    [keys.one] = "!",
    [keys.two] = "@",
    [keys.three] = "#",
    [keys.four] = "$",
    [keys.five] = "%",
    [keys.six] = "^",
    [keys.seven] = "&",
    [keys.eight] = "*",
    [keys.nine] = "(",
    [keys.zero] = ")",
    [keys.minus] = "_",
    [keys.equals] = "+",

    [keys.q] = "Q",
    [keys.w] = "W",
    [keys.e] = "E",
    [keys.r] = "R",
    [keys.t] = "T",
    [keys.y] = "Y",
    [keys.u] = "U",
    [keys.i] = "I",
    [keys.o] = "O",
    [keys.p] = "P",
    [keys.a] = "A",
    [keys.s] = "S",
    [keys.d] = "D",
    [keys.f] = "F",
    [keys.g] = "G",
    [keys.h] = "H",
    [keys.j] = "J",
    [keys.k] = "K",
    [keys.l] = "L",
    [keys.z] = "Z",
    [keys.x] = "X",
    [keys.c] = "C",
    [keys.v] = "V",
    [keys.b] = "B",
    [keys.n] = "N",
    [keys.m] = "M",

    [keys.leftBracket] = "{",
    [keys.rightBracket] = "}",
    [keys.semiColon] = ":",
    [keys.apostrophe] = "\"",
    [keys.grave] = "~",
    [keys.backslash] = "|",
    [keys.comma] = "<",
    [keys.period] = ">",
    [keys.slash] = "?",
}

-- TODO: handle keys.delete
local emittables = {
    [keys.tab] = "\t",
    [keys.backspace] = "\b",
    [keys.enter] = "\n",
    [keys.space] = " ",

    [keys.one] = "1",
    [keys.two] = "2",
    [keys.three] = "3",
    [keys.four] = "4",
    [keys.five] = "5",
    [keys.six] = "6",
    [keys.seven] = "7",
    [keys.eight] = "8",
    [keys.nine] = "9",
    [keys.zero] = "0",
    [keys.minus] = "-",
    [keys.equals] = "=",

    [keys.q] = "q",
    [keys.w] = "w",
    [keys.e] = "e",
    [keys.r] = "r",
    [keys.t] = "t",
    [keys.y] = "y",
    [keys.u] = "u",
    [keys.i] = "i",
    [keys.o] = "o",
    [keys.p] = "p",
    [keys.a] = "a",
    [keys.s] = "s",
    [keys.d] = "d",
    [keys.f] = "f",
    [keys.g] = "g",
    [keys.h] = "h",
    [keys.j] = "j",
    [keys.k] = "k",
    [keys.l] = "l",
    [keys.z] = "z",
    [keys.x] = "x",
    [keys.c] = "c",
    [keys.v] = "v",
    [keys.b] = "b",
    [keys.n] = "n",
    [keys.m] = "m",

    [keys.leftBracket] = "[",
    [keys.rightBracket] = "]",
    [keys.semiColon] = ";",
    [keys.apostrophe] = "'",
    [keys.grave] = "`",
    [keys.backslash] = "\\",
    [keys.comma] = ",",
    [keys.period] = ".",
    [keys.slash] = "/",
    [keys.space] = " ",

    [keys.numPad0] = "0",
    [keys.numPad1] = "1",
    [keys.numPad2] = "2",
    [keys.numPad3] = "3",
    [keys.numPad4] = "4",
    [keys.numPad5] = "5",
    [keys.numPad6] = "6",
    [keys.numPad7] = "7",
    [keys.numPad8] = "8",
    [keys.numPad9] = "9",
    [keys.numPadSubtract] = "-",
    [keys.numPadAdd] = "+",
    [keys.numPadDecimal] = "",
    [keys.multiply] = "*",
    [keys.numPadEnter] = "\n",
    [keys.numPadDivide] = "/",

    [S(keys.one)] = "!",
    [S(keys.two)] = "@",
    [S(keys.three)] = "#",
    [S(keys.four)] = "$",
    [S(keys.five)] = "%",
    [S(keys.six)] = "^",
    [S(keys.seven)] = "&",
    [S(keys.eight)] = "*",
    [S(keys.nine)] = "(",
    [S(keys.zero)] = ")",
    [S(keys.minus)] = "_",
    [S(keys.equals)] = "+",

    [S(keys.q)] = "Q",
    [S(keys.w)] = "W",
    [S(keys.e)] = "E",
    [S(keys.r)] = "R",
    [S(keys.t)] = "T",
    [S(keys.y)] = "Y",
    [S(keys.u)] = "U",
    [S(keys.i)] = "I",
    [S(keys.o)] = "O",
    [S(keys.p)] = "P",
    [S(keys.a)] = "A",
    [S(keys.s)] = "S",
    [S(keys.d)] = "D",
    [S(keys.f)] = "F",
    [S(keys.g)] = "G",
    [S(keys.h)] = "H",
    [S(keys.j)] = "J",
    [S(keys.k)] = "K",
    [S(keys.l)] = "L",
    [S(keys.z)] = "Z",
    [S(keys.x)] = "X",
    [S(keys.c)] = "C",
    [S(keys.v)] = "V",
    [S(keys.b)] = "B",
    [S(keys.n)] = "N",
    [S(keys.m)] = "M",

    [S(keys.leftBracket)] = "{",
    [S(keys.rightBracket)] = "}",
    [S(keys.semiColon)] = ":",
    [S(keys.apostrophe)] = "\"",
    [S(keys.grave)] = "~",
    [S(keys.backslash)] = "|",
    [S(keys.comma)] = "<",
    [S(keys.period)] = ">",
    [S(keys.slash)] = "?",

    [S(keys.space)] = " ",
    [S(keys.enter)] = "\n",
}

function Key:new(keynr, ctrld, shifted, alted)
    local obj = setmetatable({
        numeric = bit32.bor(keynr, bit32.bor(ctrld and 4096 or 0, bit32.bor(shifted and 8192 or 0, alted and 16384 or 0)))
    }, Key)

    return obj
end

function Key:C()
    self.numeric = bit32.bor(self.numeric, 4096)
end

function Key:S()
    self.numeric = bit32.bor(self.numeric, 8192)
end

function Key:CS()
    self.numeric = bit32.bor(self.numeric, 12288)
end

function Key:printable()
    return Key.printable_number(self.numeric)
end

function Key.printable_number(num)
    local ctrld = bit32.band(num, 4096) ~= 0
    local shifted = bit32.band(num, 8192) ~= 0
    local alted = bit32.band(num, 16384) ~= 0

    local base = bit32.band(num, 4095)
    local bname = printables[base]
    if bname == nil then
        return ""
    end

    if not ctrld and not shifted and not alted then
        return bname
    end

    local start = "<"
    if ctrld then
        start = start .. "C-"
    end
    if alted then
        start = start .. "M-"
    end
    if shifted then
        if shiftables[base] ~= nil then
            start = start .. shiftables[base]
        else
            start = start .. "S-" .. bname
        end
    else
        start = start .. bname
    end

    return start .. ">"
end

local digitmap = {
    [keys.one] = 1,
    [keys.two] = 2,
    [keys.three] = 3,
    [keys.four] = 4,
    [keys.five] = 5,
    [keys.six] = 6,
    [keys.seven] = 7,
    [keys.eight] = 8,
    [keys.nine] = 9,
    [keys.zero] = 0,

    [keys.numPad0] = 0,
    [keys.numPad1] = 1,
    [keys.numPad2] = 2,
    [keys.numPad3] = 3,
    [keys.numPad4] = 4,
    [keys.numPad5] = 5,
    [keys.numPad6] = 6,
    [keys.numPad7] = 7,
    [keys.numPad8] = 8,
    [keys.numPad9] = 9,

    [bit32.bor(keys.numPad0, 8192)] = 0,
    [bit32.bor(keys.numPad1, 8192)] = 1,
    [bit32.bor(keys.numPad2, 8192)] = 2,
    [bit32.bor(keys.numPad3, 8192)] = 3,
    [bit32.bor(keys.numPad4, 8192)] = 4,
    [bit32.bor(keys.numPad5, 8192)] = 5,
    [bit32.bor(keys.numPad6, 8192)] = 6,
    [bit32.bor(keys.numPad7, 8192)] = 7,
    [bit32.bor(keys.numPad8, 8192)] = 8,
    [bit32.bor(keys.numPad9, 8192)] = 9,
}
function Key.ToDigitNumeric(code)
    return digitmap[code]
end

function Key:ToDigit()
    return digitmap[self.numeric]
end

function Key:emittable()
    return emittables[self.numeric]
end

function Key.__eq(a, b)
    return a.numeric == b.numeric
end

local printables_rev = {}
local shiftables_rev = {}
for k, v in pairs(printables) do
    printables_rev[v] = k
end
printables_rev["Space"] = keys.space
for k, v in pairs(shiftables) do
    shiftables_rev[v] = k
end

local TERM_PREFIX_1 = 255
local TERM_PREFIX_2 = 254
local TERM_PREFIX = string.char(TERM_PREFIX_1, TERM_PREFIX_2)
local NVIM_K_SPECIAL = 128
local NVIM_KS_MODIFIER = 252
local NVIM_KS_COMMAND = 253

local function bytes3(a, b, c)
    return string.char(a, b, c)
end

local NVIM_SPECIAL_KEYCODE = {
    ["<BS>"] = bytes3(128, 107, 98),
    ["<Home>"] = bytes3(128, 107, 104),
    ["<End>"] = bytes3(128, 64, 55),
    ["<PageUp>"] = bytes3(128, 107, 80),
    ["<PageDown>"] = bytes3(128, 107, 78),
    ["<Insert>"] = bytes3(128, 107, 73),
    ["<Del>"] = bytes3(128, 107, 68),
    ["<Up>"] = bytes3(128, 107, 117),
    ["<Down>"] = bytes3(128, 107, 100),
    ["<Left>"] = bytes3(128, 107, 108),
    ["<Right>"] = bytes3(128, 107, 114),
    ["<S-Tab>"] = bytes3(128, 107, 66),
    ["<F1>"] = bytes3(128, 107, 49),
    ["<F2>"] = bytes3(128, 107, 50),
    ["<F3>"] = bytes3(128, 107, 51),
    ["<F4>"] = bytes3(128, 107, 52),
    ["<F5>"] = bytes3(128, 107, 53),
    ["<F6>"] = bytes3(128, 107, 54),
    ["<F7>"] = bytes3(128, 107, 55),
    ["<F8>"] = bytes3(128, 107, 56),
    ["<F9>"] = bytes3(128, 107, 57),
    ["<F10>"] = bytes3(128, 107, 59),
    ["<F11>"] = bytes3(128, 70, 49),
    ["<F12>"] = bytes3(128, 70, 50),
    ["<C-Home>"] = bytes3(128, 253, 87),
    ["<C-Left>"] = bytes3(128, 253, 85),
    ["<C-Right>"] = bytes3(128, 253, 86),
    ["<S-Up>"] = bytes3(128, 253, 4),
    ["<S-Down>"] = bytes3(128, 253, 5),
    ["<S-Left>"] = bytes3(128, 35, 52),
    ["<S-Right>"] = bytes3(128, 37, 105),
    ["<Nul>"] = bytes3(128, 255, 88),
    ["<Cmd>"] = bytes3(128, 253, 104),
}

local NVIM_SPECIAL_BY_BYTES = {}
for notation, seq in pairs(NVIM_SPECIAL_KEYCODE) do
    local b1, b2, b3 = string.byte(seq, 1, 3)
    NVIM_SPECIAL_BY_BYTES[("%d,%d,%d"):format(b1, b2, b3)] = notation
end

local NVIM_SPECIAL_TO_NUMERIC = {
    ["<BS>"] = keys.backspace,
    ["<Home>"] = keys.home,
    ["<End>"] = keys["end"],
    ["<PageUp>"] = keys.pageUp,
    ["<PageDown>"] = keys.pageDown,
    ["<Insert>"] = keys.insert,
    ["<Del>"] = keys.delete,
    ["<Up>"] = keys.up,
    ["<Down>"] = keys.down,
    ["<Left>"] = keys.left,
    ["<Right>"] = keys.right,
    ["<S-Tab>"] = S(keys.tab),
    ["<F1>"] = keys.f1,
    ["<F2>"] = keys.f2,
    ["<F3>"] = keys.f3,
    ["<F4>"] = keys.f4,
    ["<F5>"] = keys.f5,
    ["<F6>"] = keys.f6,
    ["<F7>"] = keys.f7,
    ["<F8>"] = keys.f8,
    ["<F9>"] = keys.f9,
    ["<F10>"] = keys.f10,
    ["<F11>"] = keys.f11,
    ["<F12>"] = keys.f12,
    ["<C-Home>"] = C(keys.home),
    ["<C-Left>"] = C(keys.left),
    ["<C-Right>"] = C(keys.right),
    ["<S-Up>"] = S(keys.up),
    ["<S-Down>"] = S(keys.down),
    ["<S-Left>"] = S(keys.left),
    ["<S-Right>"] = S(keys.right),
    ["<Nul>"] = C(S(keys.two)),
}

local function key_from_numeric(num)
    return setmetatable({ numeric = num }, Key)
end

local function encode_numeric_termcode(num)
    local hi = bit32.band(bit32.rshift(num, 8), 0xff)
    local lo = bit32.band(num, 0xff)
    return TERM_PREFIX .. string.char(hi, lo)
end

local function decode_numeric_termcode_at(str, i)
    if i + 3 > #str then
        return nil
    end
    if string.byte(str, i) ~= TERM_PREFIX_1 or string.byte(str, i + 1) ~= TERM_PREFIX_2 then
        return nil
    end
    local hi = string.byte(str, i + 2)
    local lo = string.byte(str, i + 3)
    local num = bit32.bor(bit32.lshift(hi, 8), lo)
    return num, i + 4
end

-- Conversion to a sequence
-- Helpers for name normalization and pushing keys
local function canon_name(name)
    local lower = name:lower()

    -- F-keys
    local fnum = lower:match("^f(%d%d?)$")
    if fnum then return "F" .. fnum end

    -- Keypad digits k0..k9
    local kdig = lower:match("^k([0-9])$")
    if kdig then return "k" .. kdig end

    -- Keypad operators
    local km = {
        ["kplus"]     = "kPlus",
        ["kminus"]    = "kMinus",
        ["kmultiply"] = "kMultiply",
        ["kdivide"]   = "kDivide",
        ["kpoint"]    = "kPoint",
        ["kenter"]    = "kEnter",
    }
    if km[lower] then return km[lower] end

    -- Navigation / control synonyms
    local syn = {
        ["cr"] = "CR",
        ["enter"] = "CR",
        ["return"] = "CR",
        ["bs"] = "BS",
        ["backspace"] = "BS",
        ["del"] = "Del",
        ["delete"] = "Del",
        ["space"] = "Space",
        ["spacebar"] = "Space",
        ["tab"] = "Tab",
        ["pageup"] = "PageUp",
        ["page_up"] = "PageUp",
        ["pagedown"] = "PageDown",
        ["page_down"] = "PageDown",
        ["up"] = "Up",
        ["down"] = "Down",
        ["left"] = "Left",
        ["right"] = "Right",
        ["home"] = "Home",
        ["end"] = "End",
        ["insert"] = "Insert",
    }
    if syn[lower] then return syn[lower] end

    -- Otherwise, return original (could be a printable letter/punct already)
    return name
end

local function numeric_for_ctrl_char_byte(byte)
    if byte == 13 or byte == 10 then
        return keys.enter
    end
    if byte == 9 then
        return keys.tab
    end
    if byte == 8 then
        return keys.backspace
    end
    if byte >= 1 and byte <= 26 then
        local base = printables_rev[string.char(byte + 96)]
        if base then
            return C(base)
        end
    end
    if byte == 0 then
        return C(S(keys.two)) -- <C-@>
    end
    if byte == 27 then
        return C(keys.leftBracket)
    end
    if byte == 28 then
        return C(keys.backslash)
    end
    if byte == 29 then
        return C(keys.rightBracket)
    end
    if byte == 30 then
        return C(S(keys.six)) -- <C-^>
    end
    if byte == 31 then
        return C(S(keys.minus)) -- <C-_>
    end
    if byte == 127 then
        return C(S(keys.slash)) -- <C-?>
    end
    return nil
end

local function push_char(seq, ch)
    -- Map literal characters to base key + (optional) shift bit.
    if ch == "\n" or ch == "\r" then
        table.insert(seq, Key:new(keys.enter, false, false, false))
        return
    elseif ch == "\t" then
        table.insert(seq, Key:new(keys.tab, false, false, false))
        return
    elseif ch == "\b" then
        table.insert(seq, Key:new(keys.backspace, false, false, false))
        return
    end

    local b = string.byte(ch)
    if b ~= nil and (b < 32 or b == 127) then
        local num = numeric_for_ctrl_char_byte(b)
        if num ~= nil then
            table.insert(seq, key_from_numeric(num))
            return
        end
    end

    local base = printables_rev[ch]
    local shifted = false
    if not base then
        base = shiftables_rev[ch]
        if base then shifted = true end
    end
    if not base then
        error(("Unknown literal character in mapping: %q"):format(ch))
    end
    table.insert(seq, Key:new(base, false, shifted, false))
end

local function push_literal_angle(seq, content)
    push_char(seq, "<")
    for i = 1, #content do
        push_char(seq, content:sub(i, i))
    end
    push_char(seq, ">")
end

local function parse_angle_content(content)
    local raw = content
    local force_keycode = false
    if raw:sub(1, 1) == "*" then
        force_keycode = true
        raw = raw:sub(2)
    end
    if raw == "" then
        error(("Malformed angle key notation: <%s>"):format(content))
    end

    local clower = raw:lower()
    if clower == "lt" then
        return { kind = "literal_char", ch = "<", force_keycode = force_keycode }
    elseif clower == "bar" then
        return { kind = "literal_char", ch = "|", force_keycode = force_keycode }
    elseif clower == "plug" then
        return { kind = "literal_angle", content = "Plug", force_keycode = force_keycode }
    elseif clower == "cmd" then
        return { kind = "cmd", force_keycode = force_keycode }
    elseif clower == "nl" then
        return { kind = "literal_char", ch = "\n", force_keycode = force_keycode }
    elseif clower == "esc" then
        return { kind = "literal_char", ch = string.char(27), force_keycode = force_keycode }
    elseif clower == "nul" then
        return { kind = "key", key = Key:new(keys.two, true, true, false), force_keycode = force_keycode }
    end

    local ctrl, shift, alt = false, false, false
    local parts = {}
    for token in raw:gmatch("[^%-]+") do
        parts[#parts + 1] = token
    end

    local base_token = parts[#parts]
    for i = 1, (#parts - 1) do
        local tl = parts[i]:lower()
        if tl == "c" or tl == "ctrl" or tl == "control" then
            ctrl = true
        elseif tl == "s" or tl == "shift" then
            shift = true
        elseif tl == "m" or tl == "meta" or tl == "alt" or tl == "a" then
            alt = true
        else
            error(("Malformed angle key notation: <%s>"):format(content))
        end
    end

    if not base_token or base_token == "" then
        error(("Malformed angle key notation: <%s>"):format(content))
    end

    local keynr, inherent_shift = nil, false
    if #base_token == 1 then
        keynr = printables_rev[base_token]
        if not keynr then
            keynr = shiftables_rev[base_token]
            if keynr then
                inherent_shift = true
            end
        end
        if not keynr then
            if base_token == "\n" or base_token == "\r" then
                keynr = keys.enter
            elseif base_token == "\t" then
                keynr = keys.tab
            elseif base_token == "\b" then
                keynr = keys.backspace
            end
        end
        if not keynr then
            error(("Unknown key name <%s>"):format(content))
        end
    else
        local cname = canon_name(base_token)
        keynr = printables_rev[cname]
        if not keynr then
            error(("Unknown key name <%s>"):format(content))
        end
    end

    return {
        kind = "key",
        key = Key:new(keynr, ctrl, (shift or inherent_shift), alt),
        force_keycode = force_keycode,
    }
end

local function push_angle(seq, content)
    local parsed = parse_angle_content(content)
    if parsed.kind == "literal_char" then
        push_char(seq, parsed.ch)
    elseif parsed.kind == "literal_angle" then
        push_literal_angle(seq, parsed.content)
    elseif parsed.kind == "cmd" then
        -- Keep command-mapping usability in feed/mapping paths.
        push_char(seq, ":")
    else
        table.insert(seq, parsed.key)
    end
end

local function decode_nvim_special_at(str, i)
    if i + 2 > #str then
        return nil
    end
    local b1, b2, b3 = string.byte(str, i, i + 2)
    if b1 ~= NVIM_K_SPECIAL then
        return nil
    end
    local notation = NVIM_SPECIAL_BY_BYTES[("%d,%d,%d"):format(b1, b2, b3)]
    if not notation then
        return nil
    end
    return notation, i + 3
end

local function decode_modifier_payload_byte_to_numeric(mod, payload)
    local has_shift = bit32.band(mod, 2) ~= 0
    local has_ctrl = bit32.band(mod, 4) ~= 0
    local has_alt = bit32.band(mod, 8) ~= 0

    local base_num = nil
    local inherent_shift = false

    if has_ctrl and payload >= string.byte("A") and payload <= string.byte("Z") then
        local lower = string.char(payload + 32)
        base_num = printables_rev[lower]
    else
        local ch = string.char(payload)
        base_num = printables_rev[ch]
        if not base_num then
            base_num = shiftables_rev[ch]
            if base_num then
                inherent_shift = true
            end
        end
    end

    if not base_num then
        local ctrl_num = numeric_for_ctrl_char_byte(payload)
        if ctrl_num then
            base_num = bit32.band(ctrl_num, 4095)
            inherent_shift = bit32.band(ctrl_num, 8192) ~= 0
            has_ctrl = has_ctrl or (bit32.band(ctrl_num, 4096) ~= 0)
        end
    end

    if not base_num then
        return nil
    end

    local num = base_num
    if has_ctrl then
        num = bit32.bor(num, 4096)
    end
    if has_alt then
        num = bit32.bor(num, 16384)
    end
    if has_shift or inherent_shift then
        num = bit32.bor(num, 8192)
    end
    return num
end

local function decode_nvim_modifier_at(str, i)
    if i + 3 > #str then
        return nil
    end
    local b1, b2, mod = string.byte(str, i, i + 2)
    if b1 ~= NVIM_K_SPECIAL or b2 ~= NVIM_KS_MODIFIER then
        return nil
    end

    local j = i + 3
    local special_notation, nj = decode_nvim_special_at(str, j)
    if special_notation then
        local base_num = NVIM_SPECIAL_TO_NUMERIC[special_notation]
        if base_num then
            local num = base_num
            if bit32.band(mod, 2) ~= 0 then num = bit32.bor(num, 8192) end
            if bit32.band(mod, 4) ~= 0 then num = bit32.bor(num, 4096) end
            if bit32.band(mod, 8) ~= 0 then num = bit32.bor(num, 16384) end
            return num, nj
        end
    end

    local payload = string.byte(str, j)
    local num = decode_modifier_payload_byte_to_numeric(mod, payload)
    if not num then
        return nil
    end
    return num, j + 1
end

-- Conversion to a sequence
function Key.strtoseq(str)
    local i, n = 1, #str
    local seq = {}

    while i <= n do
        local num, ni = decode_numeric_termcode_at(str, i)
        if num ~= nil then
            seq[#seq + 1] = key_from_numeric(num)
            i = ni
            goto continue
        end

        local mnum, mni = decode_nvim_modifier_at(str, i)
        if mnum ~= nil then
            seq[#seq + 1] = key_from_numeric(mnum)
            i = mni
            goto continue
        end

        local nvim_notation, nvim_ni = decode_nvim_special_at(str, i)
        if nvim_notation ~= nil then
            local nnum = NVIM_SPECIAL_TO_NUMERIC[nvim_notation]
            if nnum ~= nil then
                seq[#seq + 1] = key_from_numeric(nnum)
            elseif nvim_notation == "<Cmd>" then
                push_char(seq, ":")
            end
            i = nvim_ni
            goto continue
        end

        local c = str:sub(i, i)
        if c == "<" then
            -- Find the matching '>' (no nesting per Vim notation)
            local j = str:find(">", i + 1, true)
            if not j then
                -- No closing '>' -> treat '<' literally
                push_char(seq, "<")
                i = i + 1
            else
                local content = str:sub(i + 1, j - 1)
                -- Empty <> or whitespace-only? Treat '<' literally then continue.
                if content == "" or content:match("^%s+$") then
                    push_char(seq, "<")
                    i = i + 1
                else
                    push_angle(seq, content)
                    i = j + 1
                end
            end
        else
            push_char(seq, c)
            i = i + 1
        end

        ::continue::
    end

    return seq
end

function Key.seqtostr(seq)
    local tab = {}
    for i = 1, #seq do
        tab[i] = seq[i]:emittable()
    end
    return table.concat(tab)
end

local function collapse_ctrl_key(base, shifted)
    local g = shifted and shiftables[base] or printables[base]
    if g == nil or #g ~= 1 then
        return nil
    end

    local b = string.byte(g)
    if b >= string.byte("a") and b <= string.byte("z") then
        return b - 96
    end
    if b >= string.byte("A") and b <= string.byte("Z") then
        return b - 64
    end
    if g == "@" then
        return NVIM_SPECIAL_KEYCODE["<Nul>"]
    end
    if g == "[" then return 27 end
    if g == "\\" then return 28 end
    if g == "]" then return 29 end
    if g == "^" then return 30 end
    if g == "_" then return 31 end
    if g == "?" then return 127 end
    return nil
end

local function modifier_payload_byte(base, shifted, preserve_ctrl_char)
    if base == keys.enter or base == keys.numPadEnter then
        return 13
    end
    if base == keys.tab then
        return 9
    end
    if base == keys.backspace then
        return 8
    end
    if base == keys.space then
        return 32
    end

    local p = printables[base]
    if preserve_ctrl_char and p and #p == 1 and p:match("[a-z]") then
        return string.byte(string.upper(p))
    end

    local g = shifted and shiftables[base] or printables[base]
    if g and #g == 1 then
        return string.byte(g)
    end
    return nil
end

local function shift_mod_bit(base, shifted)
    if not shifted then
        return 0
    end
    if shiftables[base] ~= nil then
        return 0
    end
    return 2
end

local function key_to_termcode_string(key, opts)
    opts = opts or {}
    local force_keycode = not not opts.force_keycode
    local from_expr = not not opts.from_expr

    local num = key.numeric
    local ctrld = bit32.band(num, 4096) ~= 0
    local shifted = bit32.band(num, 8192) ~= 0
    local alted = bit32.band(num, 16384) ~= 0
    local base = bit32.band(num, 4095)

    local notation = Key.to_map_notation(num)
    local special = NVIM_SPECIAL_KEYCODE[notation]
    if special then
        return special
    end

    if ctrld and from_expr and force_keycode then
        local payload = modifier_payload_byte(base, shifted, true)
        if payload then
            local mod = bit32.bor(4, bit32.bor(alted and 8 or 0, shift_mod_bit(base, shifted)))
            return string.char(NVIM_K_SPECIAL, NVIM_KS_MODIFIER, mod, payload)
        end
    end

    if ctrld then
        local collapsed = collapse_ctrl_key(base, shifted)
        if collapsed ~= nil then
            if alted then
                local mod = bit32.bor(8, shift_mod_bit(base, shifted))
                if type(collapsed) == "number" then
                    return string.char(NVIM_K_SPECIAL, NVIM_KS_MODIFIER, mod, collapsed)
                end
                return string.char(NVIM_K_SPECIAL, NVIM_KS_MODIFIER, mod) .. collapsed
            end
            if type(collapsed) == "number" then
                return string.char(collapsed)
            end
            return collapsed
        end
    end

    if alted or ctrld then
        local payload = modifier_payload_byte(base, shifted, false)
        if payload then
            local mod = bit32.bor(
                shift_mod_bit(base, shifted),
                bit32.bor(ctrld and 4 or 0, alted and 8 or 0)
            )
            return string.char(NVIM_K_SPECIAL, NVIM_KS_MODIFIER, mod, payload)
        end
    end

    if not ctrld and not alted then
        if base == keys.enter or base == keys.numPadEnter then
            return "\r"
        end
        local emitted = key:emittable()
        if emitted ~= nil then
            return emitted
        end
    end

    return encode_numeric_termcode(num)
end

function Key.replace_termcodes(str, do_lt, special)
    local text = tostring(str or "")
    local replace_special = (special == true or special == 1)
    if not replace_special then
        return text
    end
    local translate_lt = (do_lt == true or do_lt == 1)

    local out = {}
    local i, n = 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c ~= "<" then
            out[#out + 1] = c
            i = i + 1
        else
            local j = text:find(">", i + 1, true)
            if not j then
                out[#out + 1] = c
                i = i + 1
            else
                local content = text:sub(i + 1, j - 1)
                if content == "" or content:match("^%s+$") then
                    out[#out + 1] = "<"
                    i = i + 1
                else
                    local ok, parsed = pcall(parse_angle_content, content)
                    if not ok then
                        out[#out + 1] = text:sub(i, j)
                    elseif parsed.kind == "literal_char" then
                        if parsed.ch == "<" and not translate_lt then
                            out[#out + 1] = "<lt>"
                        else
                            out[#out + 1] = parsed.ch
                        end
                    elseif parsed.kind == "literal_angle" then
                        out[#out + 1] = "<" .. parsed.content .. ">"
                    elseif parsed.kind == "cmd" then
                        out[#out + 1] = NVIM_SPECIAL_KEYCODE["<Cmd>"]
                    else
                        out[#out + 1] = key_to_termcode_string(parsed.key, { force_keycode = false, from_expr = false })
                    end
                    i = j + 1
                end
            end
        end
    end

    return table.concat(out)
end

function Key.decode_angle_escape(content)
    local ok, parsed = pcall(parse_angle_content, tostring(content or ""))
    if not ok then
        return nil
    end

    if parsed.kind == "literal_char" then
        return parsed.ch
    end
    if parsed.kind == "literal_angle" then
        return "<" .. parsed.content .. ">"
    end
    if parsed.kind == "cmd" then
        return NVIM_SPECIAL_KEYCODE["<Cmd>"]
    end
    if parsed.kind == "key" then
        return key_to_termcode_string(parsed.key, { force_keycode = parsed.force_keycode, from_expr = true })
    end
    return nil
end

function Key.to_map_notation(num)
    local p = Key.printable_number(num)
    if p == "" then
        return ""
    end
    if p:sub(1, 1) == "<" then
        return p
    end
    if #p == 1 then
        return p
    end
    return "<" .. p .. ">"
end

local function raw_keytrans_atom(byte)
    if byte == 0 then return "<Nul>" end
    if byte == 9 then return "<Tab>" end
    if byte == 10 then return "<NL>" end
    if byte == 13 then return "<CR>" end
    if byte == 27 then return "<Esc>" end
    if byte == 32 then return "<Space>" end
    if byte == 60 then return "<lt>" end
    if byte == 127 then return "^?" end
    if byte >= 1 and byte <= 31 then
        return ("<C-%s>"):format(string.char(byte + 64))
    end
    return nil
end

local function modifier_payload_atom(payload)
    local atom = raw_keytrans_atom(payload)
    if atom then
        if atom:sub(1, 1) == "<" and atom:sub(-1) == ">" then
            return atom:sub(2, -2)
        end
        return atom
    end
    return string.char(payload)
end

local function keytrans_modifier_at(text, i)
    if i + 3 > #text then
        return nil
    end
    local b1, b2, mod = string.byte(text, i, i + 2)
    if b1 ~= NVIM_K_SPECIAL or b2 ~= NVIM_KS_MODIFIER then
        return nil
    end
    local j = i + 3

    local base_atom = nil
    local special_notation, nsi = decode_nvim_special_at(text, j)
    if special_notation then
        base_atom = special_notation:sub(2, -2)
        j = nsi
    else
        local payload = string.byte(text, j)
        if payload == nil then
            return nil
        end
        base_atom = modifier_payload_atom(payload)
        j = j + 1
    end

    local prefix = "<"
    if bit32.band(mod, 8) ~= 0 then prefix = prefix .. "M-" end
    if bit32.band(mod, 4) ~= 0 then prefix = prefix .. "C-" end
    if bit32.band(mod, 2) ~= 0 then prefix = prefix .. "S-" end
    return prefix .. base_atom .. ">", j
end

function Key.keytrans(str)
    local text = tostring(str or "")
    local out = {}
    local i, n = 1, #text
    while i <= n do
        local num, ni = decode_numeric_termcode_at(text, i)
        if num ~= nil then
            out[#out + 1] = Key.to_map_notation(num)
            i = ni
        else
            local mod_text, mod_ni = keytrans_modifier_at(text, i)
            if mod_text ~= nil then
                out[#out + 1] = mod_text
                i = mod_ni
            else
                local nvim_notation, nvim_ni = decode_nvim_special_at(text, i)
                if nvim_notation ~= nil then
                    out[#out + 1] = nvim_notation
                    i = nvim_ni
                else
                    local b = string.byte(text, i)
                    local t = raw_keytrans_atom(b)
                    if t ~= nil then
                        out[#out + 1] = t
                    else
                        out[#out + 1] = text:sub(i, i)
                    end
                    i = i + 1
                end
            end
        end
    end
    return table.concat(out)
end

return Key
