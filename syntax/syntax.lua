--[[
    Programming guidelines:
    
    First, split the code into lines
    Then find multi-line comments and strings, handle those
    Then do strings
    Then do comments
    Then do keywords
    Then do numbers
    Then do identifiers
    Then do operators
]]

local parser = {}

local function splitAtPunctuation(str)
    local sects = {}
    local sect = ""
    local ii = 1
    while true do
        if str:sub(ii, ii):match("%W") then
            sects[#sects+1] = {sect, "text"}
            sect = ""
            while str:sub(ii, ii):match("%W") and ii <= #str do
                sect = sect .. str:sub(ii, ii)
                ii = ii + 1
            end
            ii = ii - 1
            sects[#sects+1] = {sect, "text"}
            sect = ""
        else
            sect = sect .. str:sub(ii, ii)
        end
        ii = ii + 1
        if ii > #str then
            break
        end
    end
    if sect ~= "" then
        sects[#sects+1] = sect
    end
    return sects
end

local function popWhitespace(str)
    local ostr = ""
    for i=1,#str do
        if not (str:sub(i, i) == " " and str:sub(i + 1, i + 1) == " ") then
            ostr = ostr .. str:sub(i, i)
        end
    end
    if ostr:sub(1, 1) == " " then
        ostr = ostr:sub(2, #ostr)
    end
    if ostr:sub(#ostr, #ostr) == " " then
        ostr = ostr:sub(1, #ostr - 1)
    end
    return ostr
end

local function multiLineComments(arr)
    local incomment = false
    for i=1,#arr do
        local inarr = arr[i]
        for j=1,#inarr do
            
            --check if this contains the start of a multi-line comment
            if not incomment then
                local pos = inarr[j][1]:find("%-%-%[%[")
                if pos then
                    local endpos = inarr[j][1]:find("%]%]")
                    incomment = true
                    if endpos then
                        local precomment = inarr[j][1]:sub(1, pos - 1)
                        local comment = inarr[j][1]:sub(pos + 3, endpos - 1)
                        local postcomment = inarr[j][1]:sub(endpos + 3, #inarr[j])
                        --replace the existing item with the precomment, the comment, and the postcomment
                        table.remove(arr, i)
                        if precomment and precomment ~= "" then
                            table.insert(arr, i, {precomment, "text"})
                        end
                        table.insert(arr, i + 1, {comment, "comment"})
                        if postcomment and postcomment ~= "" then
                            table.insert(arr, i + 2, {postcomment, "text"})
                        end
                        incomment = false
                    else
                        local precomment = inarr[j][1]:sub(1, pos - 1)
                        local comment = inarr[j][1]:sub(pos + 3, #inarr[j])
                        --replace the existing item with the precomment, the comment, and the postcomment
                        table.remove(arr, i)
                        if precomment and precomment ~= "" then
                            table.insert(arr, i, {precomment, "text"})
                        end
                        table.insert(arr, i + 1, {comment, "comment"})
                    end
                end
            else
                print(textutils.serialise(inarr))
                local pos = inarr[1]:find("%]%]")
                if pos then
                    local comment = inarr[j][1]:sub(1, #inarr[j])
                    local postcomment = inarr[j][1]:sub(pos + 3, #inarr[j])
                    --replace the existing item with the precomment, the end of comment, and the postcomment
                    table.remove(arr, i)
                    table.insert(arr, i, {comment, "comment"})
                    if postcomment and postcomment ~= "" then
                        table.insert(arr, i + 1, {postcomment, "text"})
                    end
                    incomment = false
                else
                    arr[i][j] = {inarr[j][1], "comment"}
                end
            end
        end

    end
end

function parser.parse(arr, options)
    --options is an array
    --TODO: options

    local splitarr = {}
    for i=1,#arr do
        splitarr[i] = splitAtPunctuation(popWhitespace(arr[i]))
    end

    multiLineComments(splitarr)

    return splitarr
end

local args = {...}
local fil = require("/vim/lib/fil")
local filearr = fil.toArr("/vim/syntax/syntax.lua")
print(textutils.serialise(parser.parse(filearr)))