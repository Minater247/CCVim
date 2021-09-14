-- syntax/lua.lua

local function syntax()
    local todos = {"TODO", "XXX", "FIXME", "NOTE"}
    local keywords = {{"function", "if", "while", "for", "do", "return", "else"}, {"local", "nil"}}
    local stringchar = "\""
    return {todos, keywords, stringchar}
end

return { syntax = syntax }