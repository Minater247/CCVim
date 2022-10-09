local syntax = {}
local tab = require("/vim/lib/tab")
local str = require("/vim/lib/str")

syntax.colors = {
    string = colors.red,
    comment = colors.lime,
    ["function"] = colors.yellow,
    keyword = colors.purple,
    subword = colors.blue,
    table = colors.green,
    punctuation = colors.white,
    default = colors.lightBlue,
    escaped = colors.yellow,
    number = colors.cyan
}

syntax.splitChars = {
    ".",
    ":",
    "(",
    ")",
    "[",
    "]",
    "-",
    " ",
    "\"",
    "\\",
    "#",
    "~",
    "#",
    "=",
    ",",
    ">",
    "<",
    "or",
    "not",
    "and",
    "{",
    "}",
    "[",
    "]", 
    "+",
    "-"
}

syntax.mainWords = {
    "if",
    "for",
    "do",
    "while",
    "end",
    "else",
    "elseif",
    "then",
    "return",
    "function"
}

syntax.subWords = {
    "local",
    "true",
    "false"
}

syntax.punctuation = {
    "~",
    "#",
    "=",
    ",",
    ".",
    ">",
    "<",
    "or",
    "not",
    "and",
    "(",
    ")",
    "{",
    "}",
    "[",
    "]",
    "+",
    "-"
}

local startedmultiline
syntax.parseSyntax = function(subject, multilineStartState)
    local multiline = multilineStartState or "none"
    local lines = {}
    lines.multiline = {}
    local currLine = 0
    for _, line in ipairs(subject) do
        currLine = currLine + 1

        local words = {}
        local word = ""
        local i=1
        while true do
            local char = line:sub(i, i)
            if tab.contains(syntax.splitChars, char) then
                if word ~= "" then
                    words[#words+1] = {}
                    words[#words].string = word
                end
                words[#words+1] = {}
                words[#words].string = char
                word = ""
            else
                word = word .. char
            end


            i = i + 1
            if i > #line then
                break
            end
        end
        if word ~= "" then
            words[#words+1] = {string = word}
        end

        local state = "none"
        local i = 1
        while i <= #words do
            local word = words[i]
            if multiline ~= "none" then
                words[i].color = syntax.colors[multiline]
                if word.string == "]" then
                    if words[i+1] then
                        if words[i+1].string == "]" then
                            words[i+1].color = syntax.colors[multiline]
                            multiline = "none"
                            i = i + 1
                            state = "none"
                        end
                    end
                end
            else
                if state == "none" then
                    if word.string == "\"" then
                        state = "string"
                        words[i].color = syntax.colors.string
                    elseif word.string == "-" then
                        local type
                        if words[i+1] then
                            if words[i+1].string == "-" then
                                type = "single"
                                if words[i+2] then
                                    if words[i+2].string == "[" then
                                        if words[i+3] then
                                            if words[i+3].string == "[" then
                                                type = "multi"
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        if type == "single" then
                            state = "comment"
                            words[i].color = syntax.colors.comment
                        elseif type == "multi" then
                            multiline = "comment"
                            state = "multiline"
                            words[i].color = syntax.colors.comment
                        else
                            words[i].color = syntax.colors.punctuation
                        end
                    elseif word.string == "[" then
                        if words[i+1] then
                            if words[i+1].string == "[" then
                                multiline = "string"
                                state = "multiline"
                                words[i].color = syntax.colors.string
                            else
                                words[i].color = syntax.colors.punctuation
                            end
                        else
                            words[i].color = syntax.colors.punctuation
                        end
                    elseif word.string == "(" then
                        words[i].color = syntax.colors.punctuation
                        words[i-1].color = syntax.colors["function"]
                    elseif (word.string == ".") or (word.string == ":") then
                        if words[i+1] then
                            if tab.contains(syntax.punctuation, words[i+1].string) then
                                words[i+1].color = syntax.colors.punctuation
                            else
                                if tonumber(words[i+1].string) then
                                    words[i+1].color = syntax.colors.number
                                else
                                    words[i+1].color = syntax.colors.table
                                end
                            end
                        end
                        words[i].color = syntax.colors.punctuation
                        i = i + 1
                        state = "none"
                    elseif tab.contains(syntax.mainWords, word.string) then
                        words[i].color = syntax.colors.keyword
                    elseif tab.contains(syntax.subWords, word.string) then
                        words[i].color = syntax.colors.subword
                    elseif tab.contains(syntax.punctuation, word.string) then
                        words[i].color = syntax.colors.punctuation
                    elseif tonumber(word.string) then
                        words[i].color = syntax.colors.number
                    else
                        words[i].color = syntax.colors.default
                    end
                elseif state == "string" then
                    if word.string == "\"" then
                        state = "none"
                        words[i].color = syntax.colors.string
                    elseif word.string == "\\" then
                        words[i].color = syntax.colors.escaped
                        if words[i+1] then
                            if #words[i+1] > 1 then
                                table.insert(words, i+2, words[i+1]:sub(2, #words[i+1]))
                                words[i+1] = words[i+1]:sub(1, 1)
                            end
                            words[i+1].color = syntax.colors.escaped
                        end
                        i = i + 1
                    else
                        words[i].color = syntax.colors.string
                    end
                elseif state == "comment" then
                    words[i].color = syntax.colors.comment
                end
            end
            i = i + 1
        end
        
        local new = {}
        local prevtype = lines.multiline[#lines.multiline] and lines.multiline[#lines.multiline].type or "none"
        if multiline ~= "none" then
            if prevtype == "none" then
                new.type = "start"..multiline
                new.line = currLine
                startedmultiline = currLine
            else
                new.type = multiline
                new.line = startedmultiline
            end
        else
            if prevtype and prevtype ~= "none" and prevtype ~= "endnone" and prevtype ~= "endcomment" and prevtype ~= "startcomment" and prevtype ~= "startstring" and prevtype ~= "endstring" then
                new.type = "end"..prevtype
                new.line = startedmultiline
            else
                new.type = "none"
            end
        end
        lines.multiline[#lines.multiline+1] = new

        lines[#lines+1] = words
        
    end
    return lines
end

return syntax