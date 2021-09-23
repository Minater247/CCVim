-- syntax/lua.lua

local function syntax()
    local todos = {"TODO", "XXX", "FIXME", "NOTE"}
    local keywords = {{"function","if", "while", "for", "do", "return", "else", "end", "then", "repeat", "until", "elseif", "true", "false"}, {"local", "nil"}}
    local stringchar = "\""
    local commentstring = "--"
    local removedpunctuation = {
        "~"
    }
    local type = "code"
    return {todos, keywords, stringchar, commentstring, removedpunctuation, type}
end

return { syntax = syntax }