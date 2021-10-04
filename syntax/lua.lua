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
    local multilinecommentstrings = {"--[[", "]]"}
    return {todos, keywords, stringchar, commentstring, removedpunctuation, type, multilinecommentstrings}
end

return { syntax = syntax }