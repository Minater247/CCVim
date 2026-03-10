local Json = {}

local function utf8_from_codepoint(codepoint)
    if codepoint <= 0x7F then
        return string.char(codepoint)
    end
    if codepoint <= 0x7FF then
        local b1 = 0xC0 + math.floor(codepoint / 0x40)
        local b2 = 0x80 + (codepoint % 0x40)
        return string.char(b1, b2)
    end
    if codepoint <= 0xFFFF then
        local b1 = 0xE0 + math.floor(codepoint / 0x1000)
        local b2 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
        local b3 = 0x80 + (codepoint % 0x40)
        return string.char(b1, b2, b3)
    end
    local b1 = 0xF0 + math.floor(codepoint / 0x40000)
    local b2 = 0x80 + (math.floor(codepoint / 0x1000) % 0x40)
    local b3 = 0x80 + (math.floor(codepoint / 0x40) % 0x40)
    local b4 = 0x80 + (codepoint % 0x40)
    return string.char(b1, b2, b3, b4)
end

function Json.decode(json_str, opts)
    if type(json_str) ~= "string" then
        return nil, "json_decode expects a string"
    end

    opts = opts or {}
    local pos = 1
    local len = #json_str

    local function skip_whitespace()
        while pos <= len and json_str:sub(pos, pos):match("[%s]") do
            pos = pos + 1
        end
    end

    local decode_value

    local function decode_string()
        pos = pos + 1
        local result = {}
        while pos <= len do
            local c = json_str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(result)
            elseif c == "\\" then
                pos = pos + 1
                local esc = json_str:sub(pos, pos)
                if esc == "n" then
                    result[#result + 1] = "\n"
                elseif esc == "t" then
                    result[#result + 1] = "\t"
                elseif esc == "r" then
                    result[#result + 1] = "\r"
                elseif esc == "b" then
                    result[#result + 1] = "\b"
                elseif esc == "f" then
                    result[#result + 1] = "\f"
                elseif esc == "\\" then
                    result[#result + 1] = "\\"
                elseif esc == '"' then
                    result[#result + 1] = '"'
                elseif esc == "/" then
                    result[#result + 1] = "/"
                elseif esc == "u" then
                    local hex = json_str:sub(pos + 1, pos + 4)
                    local codepoint = tonumber(hex, 16)
                    if not codepoint or #hex ~= 4 then
                        return nil, "invalid unicode escape"
                    end
                    pos = pos + 4
                    result[#result + 1] = utf8_from_codepoint(codepoint)
                else
                    result[#result + 1] = esc
                end
                pos = pos + 1
            else
                result[#result + 1] = c
                pos = pos + 1
            end
        end
        return nil, "unterminated string"
    end

    local function decode_array()
        pos = pos + 1
        local arr = {}
        skip_whitespace()
        if pos <= len and json_str:sub(pos, pos) == "]" then
            pos = pos + 1
            return arr
        end
        while true do
            local val, err = decode_value()
            if err then
                return nil, err
            end
            arr[#arr + 1] = val
            skip_whitespace()
            if pos > len then
                return nil, "unterminated array"
            end
            local next_char = json_str:sub(pos, pos)
            if next_char == "]" then
                pos = pos + 1
                return arr
            elseif next_char == "," then
                pos = pos + 1
            else
                return nil, "expected ',' or ']' in array"
            end
        end
    end

    local function decode_object()
        pos = pos + 1
        local obj = {}
        skip_whitespace()
        if pos <= len and json_str:sub(pos, pos) == "}" then
            pos = pos + 1
            if opts.empty_dict_mt then
                return setmetatable({}, opts.empty_dict_mt)
            end
            return {}
        end
        while true do
            skip_whitespace()
            if pos > len or json_str:sub(pos, pos) ~= '"' then
                return nil, "expected string key in object"
            end
            local key, err = decode_string()
            if err then
                return nil, err
            end
            skip_whitespace()
            if pos > len or json_str:sub(pos, pos) ~= ":" then
                return nil, "expected ':' after object key"
            end
            pos = pos + 1
            local val, err2 = decode_value()
            if err2 then
                return nil, err2
            end
            obj[key] = val
            skip_whitespace()
            if pos > len then
                return nil, "unterminated object"
            end
            local next_char = json_str:sub(pos, pos)
            if next_char == "}" then
                pos = pos + 1
                return obj
            elseif next_char == "," then
                pos = pos + 1
            else
                return nil, "expected ',' or '}' in object"
            end
        end
    end

    function decode_value()
        skip_whitespace()
        if pos > len then
            return nil, "unexpected end of JSON"
        end

        local char = json_str:sub(pos, pos)
        if char == '"' then
            return decode_string()
        elseif char == "[" then
            return decode_array()
        elseif char == "{" then
            return decode_object()
        elseif char == "t" then
            if json_str:sub(pos, pos + 3) == "true" then
                pos = pos + 4
                return true
            end
            return nil, "invalid JSON value"
        elseif char == "f" then
            if json_str:sub(pos, pos + 4) == "false" then
                pos = pos + 5
                return false
            end
            return nil, "invalid JSON value"
        elseif char == "n" then
            if json_str:sub(pos, pos + 3) == "null" then
                pos = pos + 4
                return nil
            end
            return nil, "invalid JSON value"
        elseif char:match("[-0-9]") then
            local num_start = pos
            if char == "-" then
                pos = pos + 1
            end
            while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                pos = pos + 1
            end
            if pos <= len and json_str:sub(pos, pos) == "." then
                pos = pos + 1
                while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                    pos = pos + 1
                end
            end
            if pos <= len and json_str:sub(pos, pos):match("[eE]") then
                pos = pos + 1
                if pos <= len and json_str:sub(pos, pos):match("[+-]") then
                    pos = pos + 1
                end
                while pos <= len and json_str:sub(pos, pos):match("[0-9]") do
                    pos = pos + 1
                end
            end
            return tonumber(json_str:sub(num_start, pos - 1))
        end
        return nil, "unexpected character: " .. char
    end

    local result, err = decode_value()
    if err then
        return nil, err
    end
    skip_whitespace()
    if pos <= len then
        return nil, "trailing garbage after JSON"
    end
    return result
end

return Json
