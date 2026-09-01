local Json = {}

local function utf8_from_codepoint(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    elseif codepoint <= 0x7FF then
        return string.char(0xC0 + math.floor(codepoint / 0x40), 0x80 + codepoint % 0x40)
    elseif codepoint <= 0xFFFF then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    end
    return string.char(
        0xF0 + math.floor(codepoint / 0x40000),
        0x80 + math.floor(codepoint / 0x1000) % 0x40,
        0x80 + math.floor(codepoint / 0x40) % 0x40,
        0x80 + codepoint % 0x40
    )
end

function Json.decode(source, opts)
    if type(source) ~= "string" then return nil, "expected string" end
    opts = opts or {}
    local pos, length = 1, #source

    local function skip_space()
        while pos <= length and source:sub(pos, pos):match("[ \t\r\n]") do pos = pos + 1 end
    end

    local function fail(message)
        return nil, message .. " at byte " .. tostring(pos)
    end

    local function hex_escape()
        local hex = source:sub(pos, pos + 3)
        if #hex ~= 4 or not hex:match("^%x%x%x%x$") then return fail("invalid unicode escape") end
        pos = pos + 4
        return tonumber(hex, 16)
    end

    local function decode_string()
        pos = pos + 1
        local out = {}
        while pos <= length do
            local ch = source:sub(pos, pos)
            if ch == '"' then
                pos = pos + 1
                return table.concat(out)
            elseif ch == "\\" then
                pos = pos + 1
                local esc = source:sub(pos, pos)
                local simple = {
                    ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b",
                    f = "\f", n = "\n", r = "\r", t = "\t",
                }
                if simple[esc] then
                    out[#out + 1] = simple[esc]
                    pos = pos + 1
                elseif esc == "u" then
                    pos = pos + 1
                    local codepoint, err = hex_escape()
                    if err then return nil, err end
                    if codepoint >= 0xD800 and codepoint <= 0xDBFF then
                        if source:sub(pos, pos + 1) ~= "\\u" then return fail("missing low surrogate") end
                        pos = pos + 2
                        local low, low_err = hex_escape()
                        if low_err then return nil, low_err end
                        if low < 0xDC00 or low > 0xDFFF then return fail("invalid low surrogate") end
                        codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + low - 0xDC00
                    elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
                        return fail("unexpected low surrogate")
                    end
                    out[#out + 1] = utf8_from_codepoint(codepoint)
                else
                    return fail("invalid escape")
                end
            elseif ch:byte() < 0x20 then
                return fail("unescaped control character")
            else
                out[#out + 1] = ch
                pos = pos + 1
            end
        end
        return fail("unterminated string")
    end

    local decode_value

    local function decode_array()
        pos = pos + 1
        local result, index = {}, 1
        skip_space()
        if source:sub(pos, pos) == "]" then pos = pos + 1 return result end
        while true do
            local value, err = decode_value("array")
            if err then return nil, err end
            result[index], index = value, index + 1
            skip_space()
            local ch = source:sub(pos, pos)
            if ch == "]" then pos = pos + 1 return result end
            if ch ~= "," then return fail("expected ',' or ']'") end
            pos = pos + 1
            skip_space()
        end
    end

    local function decode_object()
        pos = pos + 1
        local result = {}
        skip_space()
        if source:sub(pos, pos) == "}" then
            pos = pos + 1
            return opts.empty_dict_mt and setmetatable(result, opts.empty_dict_mt) or result
        end
        while true do
            if source:sub(pos, pos) ~= '"' then return fail("expected string key") end
            local key, key_err = decode_string()
            if key_err then return nil, key_err end
            skip_space()
            if source:sub(pos, pos) ~= ":" then return fail("expected ':'") end
            pos = pos + 1
            local value, value_err = decode_value("object")
            if value_err then return nil, value_err end
            result[key] = value
            skip_space()
            local ch = source:sub(pos, pos)
            if ch == "}" then pos = pos + 1 return result end
            if ch ~= "," then return fail("expected ',' or '}'") end
            pos = pos + 1
            skip_space()
        end
    end

    local function decode_number()
        local start = pos
        if source:sub(pos, pos) == "-" then pos = pos + 1 end
        if source:sub(pos, pos) == "0" then
            pos = pos + 1
            if source:sub(pos, pos):match("%d") then return fail("leading zero in number") end
        else
            local digit_start = pos
            while source:sub(pos, pos):match("%d") do pos = pos + 1 end
            if pos == digit_start then return fail("invalid number") end
        end
        if source:sub(pos, pos) == "." then
            pos = pos + 1
            local fraction_start = pos
            while source:sub(pos, pos):match("%d") do pos = pos + 1 end
            if pos == fraction_start then return fail("invalid fraction") end
        end
        if source:sub(pos, pos):match("[eE]") then
            pos = pos + 1
            if source:sub(pos, pos):match("[+-]") then pos = pos + 1 end
            local exponent_start = pos
            while source:sub(pos, pos):match("%d") do pos = pos + 1 end
            if pos == exponent_start then return fail("invalid exponent") end
        end
        local value = tonumber(source:sub(start, pos - 1))
        if not value then return fail("invalid number") end
        return value
    end

    function decode_value(context)
        skip_space()
        local ch = source:sub(pos, pos)
        if ch == '"' then return decode_string()
        elseif ch == "[" then return decode_array()
        elseif ch == "{" then return decode_object()
        elseif ch == "t" and source:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif ch == "f" and source:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif ch == "n" and source:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            if opts.luanil and opts.luanil[context] then return nil end
            return opts.null_value
        elseif ch == "-" or ch:match("%d") then return decode_number()
        elseif ch == "" then return fail("unexpected end of input")
        end
        return fail("unexpected character")
    end

    local value, err = decode_value("top")
    if err then return nil, err end
    skip_space()
    if pos <= length then return fail("trailing data") end
    return value
end

local escapes = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encode_string(value, escape_slash)
    return '"' .. value:gsub('[%z\1-\31\\"/]', function(ch)
        if ch == "/" and not escape_slash then return ch end
        return escapes[ch] or (ch == "/" and "\\/" or string.format("\\u%04x", ch:byte()))
    end) .. '"'
end

function Json.encode(value, opts)
    opts = opts or {}
    local active = {}
    local function encode(item)
        local kind = type(item)
        if item == opts.null_value or kind == "nil" then return "null"
        elseif kind == "boolean" then return item and "true" or "false"
        elseif kind == "number" then
            if item ~= item or item == math.huge or item == -math.huge then
                error("cannot encode non-finite number", 0)
            end
            return tostring(item)
        elseif kind == "string" then return encode_string(item, opts.escape_slash)
        elseif kind ~= "table" then error("cannot encode " .. kind, 0) end
        if active[item] then error("cannot encode recursive table", 0) end
        active[item] = true
        local object = opts.empty_dict_mt and getmetatable(item) == opts.empty_dict_mt
        local count, max = 0, 0
        for key in pairs(item) do
            count = count + 1
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then object = true
            elseif key > max then max = key end
        end
        if not object and count ~= max then error("cannot encode sparse array", 0) end
        local out = {}
        if object then
            for key, child in pairs(item) do
                if type(key) ~= "string" then error("JSON object keys must be strings", 0) end
                out[#out + 1] = encode_string(key, opts.escape_slash) .. ":" .. encode(child)
            end
            table.sort(out)
            active[item] = nil
            return "{" .. table.concat(out, ",") .. "}"
        end
        for i = 1, max do out[i] = encode(item[i]) end
        active[item] = nil
        return "[" .. table.concat(out, ",") .. "]"
    end
    return encode(value)
end

return Json
