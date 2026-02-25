local strutils = {}
local VimRegex = loadModule("lib.excmd.vim_regex")
local Utf8 = loadModule("lib.utf8")


function strutils.startswith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

function strutils.endswith(str, suffix)
    if suffix == "" then
        return true
    end
    return str:sub(-#suffix) == suffix
end

function strutils.trim(s)
    if type(s) ~= "string" then
        error(("s: expected string, got %s"):format(type(s)), 2)
    end
    return s:match("^%s*(.*%S)") or ""
end

function strutils.pesc(s)
    if type(s) ~= "string" then
        error(("s: expected string, got %s"):format(type(s)), 2)
    end
    return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
end

function strutils.regex(re)
    local compiled, c_err = VimRegex.compile(re)
    if not compiled then
        error(c_err or ("invalid regex: " .. tostring(re)), 2)
    end

    return {
        match_str = function(_, s)
            local ss = tostring(s or "")
            local a, b = VimRegex.find_compiled(ss, compiled, true)
            if a then
                return a - 1, b - 1
            end
            return nil
        end,
    }
end

local function _check_string_arg(s, fname)
    if type(s) ~= "string" then
        error((fname .. ": s must be a string"), 2)
    end
end

local function _legacy_str_utfindex(s, old_index)
    local len_bytes = #s
    if old_index == nil then
        old_index = len_bytes
    end
    old_index = math.floor(tonumber(old_index) or 0)
    if old_index < 0 or old_index > len_bytes then
        error("index out of range", 2)
    end

    local utf32 = Utf8.col_from_byte(s, old_index + 1, true) - 1
    -- TODO: true UTF-16 unit counting for non-BMP code points.
    local utf16 = utf32
    return utf32, utf16
end

function strutils.str_utfindex(s, encoding, index, strict_indexing)
    _check_string_arg(s, "str_utfindex")

    if encoding == nil or type(encoding) == "number" then
        return _legacy_str_utfindex(s, encoding)
    end

    if encoding ~= "utf-8" then
        error("TODO: str_utfindex with encoding '" .. tostring(encoding) .. "' is not implemented", 2)
    end

    local len = #s
    local idx = index
    local strict = strict_indexing
    if idx == nil then
        idx = len
        strict = false
    else
        idx = math.floor(tonumber(idx) or 0)
    end
    if strict == nil then
        strict = true
    end

    if idx < 0 then
        return strict and error("index out of range", 2) or 0
    end
    if idx > len then
        return strict and error("index out of range", 2) or len
    end
    return idx
end

function strutils.str_byteindex(s, encoding, index, strict_indexing)
    _check_string_arg(s, "str_byteindex")

    if type(encoding) == "number" then
        local old_index = math.floor(tonumber(encoding) or 0)
        local use_utf16 = index or false
        if use_utf16 then
            error("TODO: str_byteindex with use_utf16=true is not implemented", 2)
        end
        if old_index < 0 then
            error("index out of range", 2)
        end
        local n = Utf8.len(s)
        if old_index > n then
            error("index out of range", 2)
        end
        return Utf8.byte_index(s, old_index + 1, true) - 1
    end

    if encoding ~= "utf-8" then
        error("TODO: str_byteindex with encoding '" .. tostring(encoding) .. "' is not implemented", 2)
    end

    local idx = math.floor(tonumber(index) or 0)
    local strict = strict_indexing
    if strict == nil then
        strict = true
    end
    local len = #s

    if idx < 0 then
        return strict and error("index out of range", 2) or 0
    end
    if idx > len then
        return strict and error("index out of range", 2) or len
    end
    return idx
end


return strutils
