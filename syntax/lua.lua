-- syntax/lua.lua

local function syntax()
    --synt[1]
    local todos = {
        ["todo"] = true,
        ["xxx"] = true,
        ["fixme"] = true,
        ["note"] = true
    }
    --synt[2]
    local keywords = {
        ["function"] = 1,
        ["if"] = 1,
        ["while"] = 1,
        ["for"] = 1,
        ["do"] = 1,
        ["and"] = 1,
        ["or"] = 1,
        ["return"] = 1,
        ["else"] = 1,
        ["end"] = 1,
        ["then"] = 1,
        ["repeat"] = 1,
        ["until"] = 1,
        ["elseif"] = 1,
        ["true"] = 1,
        ["false"] = 1,
        ["local"] = 2,
        ["nil"] = 2
    }
    --synt[3]
    local stringchar = "\""
    --synt[4]
    local commentstring = "--"
    --synt[5]
    local removedpunctuation = {
        "~"
    }
    --synt[6]
    local type = "code"
    --synt[7]
    local multilinecommentstrings = {"--[[", "]]"}
    --synt[8]
    local definedpunctuation = {
        ["."] = true,
        ["("] = true,
        [")"] = true,
        ["["] = true,
        ["]"] = true,
        ["{"] = true,
        ["}"] = true,
        ["+"] = true,
        ["-"] = true,
        ["*"] = true,
        ["/"] = true,
        ["%"] = true,
        ["^"] = true,
        ["="] = true,
        ["<"] = true,
        [">"] = true,
        ["~"] = true,
        ["!"] = true,
        ["&"] = true,
        ["|"] = true,
        ["?"] = true,
        [":"] = true,
        [","] = true,
        [";"] = true,
        ["#"] = true,
        ["@"] = true,
        ["$"] = true,
        ["\\"] = true,
        [" "] = true
    }
    return {todos, keywords, stringchar, commentstring, removedpunctuation, type, multilinecommentstrings, definedpunctuation}
end

return { syntax = syntax }