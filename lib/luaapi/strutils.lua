local strutils = {}


function strutils.startswith(str, prefix)
    return str:sub(1, #prefix) == prefix
end

function strutils.endswith(str, suffix)
    if suffix == "" then
        return true
    end
    return str:sub(-#suffix) == suffix
end


return strutils
