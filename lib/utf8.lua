local Utf8 = {}

local translations = {
    [0x2713] = "v",
    [0x2714] = "v",
    [0x2611] = "v",
    [0x2715] = "x",
    [0x2717] = "x",
    [0x2718] = "x",
    [0x00D7] = "x",
    [0x2191] = "\x18",
    [0x2193] = "\x19",
    [0x2190] = "\x1b",
    [0x2192] = "\x1a",
    [0xE0B0] = "\x7f",
    [0xE0B2] = "\x7f",
}

local function _ascii_cell_for_codepoint(cp)
    if cp >= 32 and cp <= 127 then
        return string.char(cp)
    end

    -- DEBUG
    if translations[cp] then
        return translations[cp]
    else
        LOG_DEBUG("UNKNOWN CODEPOINT: 0x%X", cp)
        return "?"
    end

    -- return translations[cp] or "?"
end

function Utf8.ascii_cell_for_codepoint(cp)
    return _ascii_cell_for_codepoint(cp)
end

function Utf8.len(s)
    s = tostring(s or "")
    if utf8 and utf8.len then
        local ok, n = pcall(utf8.len, s)
        if ok and n then
            return n
        end
    end
    return #s
end

function Utf8.byte_index(s, col1, allow_eol)
    s = tostring(s or "")
    local col = math.floor(tonumber(col1) or 1)
    if col < 1 then
        col = 1
    end

    if utf8 and utf8.offset then
        local ok, idx = pcall(utf8.offset, s, col)
        if ok and idx then
            return idx
        end

        local n = Utf8.len(s)
        if allow_eol and col >= (n + 1) then
            return #s + 1
        end
        if n < 1 then
            return 1
        end

        local ok_last, last = pcall(utf8.offset, s, n)
        if ok_last and last then
            return last
        end
    end

    local max_col = #s + (allow_eol and 1 or 0)
    if col > max_col then
        col = max_col
    end
    return col
end

function Utf8.col_from_byte(s, byte_idx, allow_eol)
    s = tostring(s or "")
    local idx = math.floor(tonumber(byte_idx) or 1)
    if idx < 1 then
        idx = 1
    end

    if utf8 and utf8.codes then
        local ok, col = pcall(function()
            local c = 1
            for bpos in utf8.codes(s) do
                if bpos >= idx then
                    return c
                end
                c = c + 1
            end
            return c
        end)
        if ok and col then
            if not allow_eol then
                local n = Utf8.len(s)
                if n < 1 then
                    return 1
                end
                if col > n then
                    col = n
                end
            end
            return col
        end
    end

    local max_col = #s + (allow_eol and 1 or 0)
    if idx > max_col then
        idx = max_col
    end
    return idx
end

function Utf8.sub(s, start_col1, end_col1)
    s = tostring(s or "")
    local sc = math.floor(tonumber(start_col1) or 1)
    if sc < 1 then
        sc = 1
    end

    if end_col1 ~= nil then
        local ec = math.floor(tonumber(end_col1) or 0)
        if ec < sc then
            return ""
        end
        local sidx = Utf8.byte_index(s, sc, true)
        local eidx = Utf8.byte_index(s, ec + 1, true) - 1
        if eidx < sidx then
            return ""
        end
        return s:sub(sidx, eidx)
    end

    local sidx = Utf8.byte_index(s, sc, true)
    return s:sub(sidx)
end

function Utf8.char_at(s, col1)
    return Utf8.sub(s, col1, col1)
end

function Utf8.codepoint_at(s, col1)
    s = tostring(s or "")
    local idx = Utf8.byte_index(s, col1, false)
    if utf8 and utf8.codepoint then
        local ok, cp = pcall(utf8.codepoint, s, idx, idx)
        if ok then
            return cp
        end
    end
    return s:byte(idx)
end

function Utf8.each_codepoint(s, visitor)
    s = tostring(s or "")
    if utf8 and utf8.codes then
        local ok = pcall(function()
            for _, cp in utf8.codes(s) do
                visitor(cp)
            end
        end)
        if ok then
            return
        end
    end

    for i = 1, #s do
        visitor(s:byte(i))
    end
end

function Utf8.first_n(s, n)
    s = tostring(s or "")
    if utf8 and utf8.offset then
        local idx = utf8.offset(s, n + 1)
        if idx then
            return s:sub(1, idx - 1)
        end
        return s
    end
    return s:sub(1, n)
end

function Utf8.pad_or_truncate(s, width, pad)
    s = tostring(s or "")
    local n = Utf8.len(s)
    if n >= width then
        return Utf8.first_n(s, width)
    end
    return s .. string.rep(pad or " ", width - n)
end

function Utf8.format_sign_text(text)
    local width = 2
    local pad = " "
    local out = {}
    local s = tostring(text or "")

    if utf8 and utf8.codes then
        for _, cp in utf8.codes(s) do
            out[#out + 1] = _ascii_cell_for_codepoint(cp)
            if #out >= width then
                break
            end
        end
    else
        for i = 1, #s do
            out[#out + 1] = _ascii_cell_for_codepoint(s:byte(i))
            if #out >= width then
                break
            end
        end
    end

    while #out < width do
        out[#out + 1] = pad
    end
    return table.concat(out)
end

return Utf8
