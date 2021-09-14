-- ftplugin/lua.lua

-- return a table with each designation

local function types()
    local commentstring = "--"
    local removedpunctuation = {
        "~"
    }
    return {commentstring, removedpunctuation}
end

