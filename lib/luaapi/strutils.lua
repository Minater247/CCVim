local strutils = {}


function strutils.startswith(str, prefix)
    return str:sub(1, #prefix) == prefix
end


return strutils