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

    local base = bit32.band(num, 4095)

    local start = (ctrld or shifted) and "<" or ""

    if ctrld then start = start .. "C-" end
    if shifted then
        if shiftables[base] then
            start = start .. shiftables[base]
        else
            start = start .. "S-" .. printables[base]
        end
    else
        start = start .. printables[base]
    end

    if ctrld or shifted then start = start .. ">" end

    return start
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
for k, v in pairs(shiftables) do
    shiftables_rev[v] = k
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

local function push_char(seq, ch)
    -- Map literal characters to base key + (optional) shift bit.
    if ch == "\n" then
        table.insert(seq, Key:new(keys.enter, false, false, false))
        return
    elseif ch == "\t" then
        table.insert(seq, Key:new(keys.tab, false, false, false))
        return
    elseif ch == "\b" then
        table.insert(seq, Key:new(keys.backspace, false, false, false))
        return
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

local function push_angle(seq, content)
    -- Handle <...> blocks like <CR>, <S-Tab>, <C-a>, <lt>, etc.
    local clower = content:lower()

    if clower == "lt" then
        -- Literal '<'
        push_char(seq, "<")
        return
    elseif clower == "bar" then
        -- Mapping-special literal '|'
        push_char(seq, "|")
        return
    elseif clower == "plug" then
        -- Preserve as canonical <Plug> text token.
        push_literal_angle(seq, "Plug")
        return
    end

    local ctrl, shift, alt = false, false, false -- 'alt' parsed but ignored
    local parts = {}
    for token in content:gmatch("[^%-]+") do
        parts[#parts + 1] = token
    end

    local base_token = parts[#parts]
    for i = 1, (#parts - 1) do
        local tl = parts[i]:lower()
        if tl == "c" or tl == "ctrl" or tl == "control" then
            ctrl = true
        elseif tl == "s" or tl == "shift" then
            shift = true
        elseif tl == "m" or tl == "meta" or tl == "alt" then
            alt = true -- parsed but intentionally ignored when constructing Key
        else
            error(("Malformed angle key notation: <%s>"):format(content))
        end
    end

    if not base_token or base_token == "" then
        error(("Malformed angle key notation: <%s>"):format(content))
    end

    -- Determine base key code; support both single chars and named keys.
    local keynr, inherent_shift = nil, false
    if #base_token == 1 then
        -- single character inside <...>
        keynr = printables_rev[base_token]
        if not keynr then
            keynr = shiftables_rev[base_token]
            if keynr then inherent_shift = true end
        end
        if not keynr then
            -- allow control chars written literally like <\n>, though uncommon
            if base_token == "\n" then
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
        -- Named key
        local cname = canon_name(base_token)
        keynr = printables_rev[cname]
        if not keynr then
            error(("Unknown key name <%s>"):format(content))
        end
    end

    -- Build the Key (ignore alt/M- per requirement)
    table.insert(seq, Key:new(keynr, ctrl, (shift or inherent_shift), false))
end

-- Conversion to a sequence
function Key.strtoseq(str)
    local i, n = 1, #str
    local seq = {}

    while i <= n do
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

return Key
