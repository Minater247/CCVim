-- syntax/lua.lua

local function syntax()
    local todos = {"TODO", "XXX", "FIXME", "NOTE"}
    local keywords = {{"function", "if", "while", "for", "do", "return", "else"}, {"local", "nil"}}
    local stringchar = "\""
    local commentstring = "--"
    local removedpunctuation = {
        "~"
    }
    return {todos, keywords, stringchar, commentstring, removedpunctuation}
end

return { syntax = syntax }