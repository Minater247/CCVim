local syntax = {}

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
    ["."] = true,
    [":"] = true,
    ["("] = true,
    [")"] = true,
    ["["] = true,
    ["]"] = true,
    ["-"] = true,
    [" "] = true,
    ["\""] = true,
    ["\\"] = true,
    ["~"] = true,
    ["#"] = true,
    ["="] = true,
    [","] = true,
    [">"] = true,
    ["<"] = true,
    ["or"] = true,
    ["not"] = true,
    ["and"] = true,
    ["{"] = true,
    ["}"] = true,
    ["+"] = true,
}

syntax.mainWords = {
    ["if"] = true,
    ["for"] = true,
    ["do"] = true,
    ["while"] = true,
    ["end"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["then"] = true,
    ["return"] = true,
    ["function"] = true,
}

syntax.subWords = {
    ["local"] = true,
    ["true"] = true,
    ["false"] = true,
    ["nil"] = true,
    ["self"] = true,
}

syntax.punctuation = {
    ["~"] = true,
    ["#"] = true,
    ["="] = true,
    [","] = true,
    ["."] = true,
    [">"] = true,
    ["<"] = true,
    ["or"] = true,
    ["not"] = true,
    ["and"] = true,
    ["("] = true,
    [")"] = true,
    ["{"] = true,
    ["}"] = true,
    ["["] = true,
    ["]"] = true,
    ["+"] = true,
    ["-"] = true,
}

local State = {
    None = 0,
    String = 1,
    Comment = 2,
    Multiline = 3
}

syntax.parseSyntax = function(subject, multilineStartState)
    local multiline = multilineStartState or State.None
    local lines = {}
    lines.multiline = {}
    local currLine = 0

    local colors = syntax.colors
    local splitChars = syntax.splitChars
    local mainWords = syntax.mainWords
    local subWords = syntax.subWords
    local punctuation = syntax.punctuation

    for _, line in ipairs(subject) do
        currLine = currLine + 1

        local words = {}
        local word = ""
        local lineLength = #line
        local i = 1

        while i <= lineLength do
            local char = line:sub(i, i)

            if splitChars[char] then
                if word ~= "" then
                    words[#words+1] = {string = word}
                end

                words[#words+1] = {string = char}
                word = ""
            else
                word = word .. char
            end

            i = i + 1
        end

        if word ~= "" then
            words[#words+1] = {string = word}
        end

        local state = State.None
        i = 1

        while i <= #words do
            local currWord = words[i]

            if multiline ~= State.None then
                currWord.color = colors[multiline]

                if currWord.string == "]" then
                    local nextWord = words[i+1]

                    if nextWord and nextWord.string == "]" then
                        nextWord.color = colors[multiline]
                        multiline = State.None
                        i = i + 1
                        state = State.None
                    end
                end
            else
                if state == State.None then
                    if currWord.string == "\"" then
                        state = State.String
                        currWord.color = colors.string
                    elseif currWord.string == "-" then
                        local type
                        local nextWord = words[i+1]

                        if nextWord and nextWord.string == "-" then
                            type = "single"
                            local nextNextWord = words[i+2]

                            if nextNextWord and nextNextWord.string == "[" then
                                local nextNextNextWord = words[i+3]

                                if nextNextNextWord and nextNextNextWord.string == "[" then
                                    type = "multi"
                                end
                            end
                        end

                        if type == "single" then
                            state = State.Comment
                            currWord.color = colors.comment
                        elseif type == "multi" then
                            multiline = State.Comment
                            state = State.Multiline
                            currWord.color = colors.comment
                        else
                            currWord.color = colors.punctuation
                        end
                    elseif currWord.string == "[" then
                        local nextWord = words[i+1]

                        if nextWord and nextWord.string == "[" then
                            multiline = State.String
                            state = State.Multiline
                            currWord.color = colors.string
                        else
                            currWord.color = colors.punctuation
                        end
                    elseif currWord.string == "(" then
                        currWord.color = colors.punctuation
                        words[i-1].color = colors["function"]
                    elseif currWord.string == "." or currWord.string == ":" then
                        local nextWord = words[i+1]

                        if nextWord then
                            if punctuation[nextWord.string] then
                                nextWord.color = colors.punctuation
                            else
                                if tonumber(nextWord.string) then
                                    nextWord.color = colors.number
                                else
                                    nextWord.color = colors.table
                                end
                            end
                        end

                        currWord.color = colors.punctuation
                        i = i + 1
                        state = State.None
                    elseif mainWords[currWord.string] then
                        currWord.color = colors.keyword
                    elseif subWords[currWord.string] then
                        currWord.color = colors.subword
                    elseif punctuation[currWord.string] then
                        currWord.color = colors.punctuation
                    elseif tonumber(currWord.string) then
                        currWord.color = colors.number
                    else
                        currWord.color = colors.default
                    end
                elseif state == State.String then
                    if currWord.string == "\"" then
                        state = State.None
                        currWord.color = colors.string
                    elseif currWord.string == "\\" then
                        currWord.color = colors.escaped

                        local nextWord = words[i+1]

                        if nextWord then
                            if #nextWord > 1 then
                                table.insert(words, i+2, nextWord:sub(2))
                                words[i+1] = nextWord:sub(1, 1)
                            end

                            nextWord.color = colors.escaped
                        end

                        i = i + 1
                    else
                        currWord.color = colors.string
                    end
                elseif state == State.Comment then
                    currWord.color = colors.comment
                end
            end

            i = i + 1
        end
        
        local new = {}
        local prevtype = lines.multiline[#lines.multiline] and lines.multiline[#lines.multiline].type or State.None

        if multiline ~= State.None then
            if prevtype == State.None then
                new.type = "start"..multiline
                new.line = currLine
                startedmultiline = currLine
            else
                new.type = multiline
                new.line = startedmultiline
            end
        else
            if prevtype and prevtype ~= State.None and prevtype ~= "endnone" and prevtype ~= "endcomment" and prevtype ~= "startcomment" and prevtype ~= "startstring" and prevtype ~= "endstring" then
                new.type = "end"..prevtype
                new.line = startedmultiline
            else
                new.type = State.None
            end
        end

        lines.multiline[#lines.multiline+1] = new
        lines[#lines+1] = words
    end

    return lines
end

return syntax