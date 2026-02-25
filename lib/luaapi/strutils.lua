local strutils = {}
local VimRegex = loadModule("lib.excmd.vim_regex")


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


return strutils
