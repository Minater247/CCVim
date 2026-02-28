local strutils = {}
local VimRegex = loadModule("lib.excmd.vim_regex")
local Utf8 = loadModule("lib.utf8")

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
                return a - 1, b
            end
            return nil
        end,
    }
end

function strutils._str_utfindex(s, old_index)
    local len_bytes = #s
    if old_index == nil then
        old_index = len_bytes
    end
    old_index = math.floor(old_index)
    if old_index < 0 or old_index > len_bytes then
        return nil, nil
    end

    local utf32 = Utf8.col_from_byte(s, old_index + 1, true) - 1
    -- TODO: true UTF-16 unit counting for non-BMP code points.
    local utf16 = utf32
    return utf32, utf16
end

function strutils._str_byteindex(s, old_index, _use_utf16)
    old_index = math.floor(old_index)
    if old_index < 0 then
        return nil
    end

    local n = Utf8.len(s)
    if old_index > n then
        return nil
    end

    return Utf8.byte_index(s, old_index + 1, true) - 1
end


return strutils
