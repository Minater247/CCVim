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

    comments can overwrite strings, but comments can't start in the middle of a string
]]

local parser = {}

local output = io.open("/vim/syntax/synt.log", "w")
io.output(output)
local function print(...)
    local args = {...}
    io.write(os.date() .. " LOG: " .. table.concat(args, " "))
    io.write("\n")
    io.flush()
end

local function splitAtPunctuation(str)
    local sects = {}
    local sect = ""
    local ii = 1
    while true do
        if str:sub(ii, ii):match("%W") then
            if sect ~= "" then
                sects[#sects+1] = {sect, "text"}
                sect = ""
            end
            while str:sub(ii, ii):match("%W") and ii <= #str do
                sect = sect .. str:sub(ii, ii)
                ii = ii + 1
            end
            ii = ii - 1
            if sect ~= "" then
                sects[#sects+1] = {sect, "text"}
                sect = ""
            end
        else
            sect = sect .. str:sub(ii, ii)
        end
        ii = ii + 1
        if ii > #str then
            break
        end
    end
    if sect ~= "" then
        sects[#sects+1] = {sect, "text"}
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

local function strings(arr)
    local instring = false
    local skip = 0
    for i=1,#arr do
        --each item iterated in this layer is a line table
        skip = 0
        local inarr = arr[i]
        for j=1,#inarr do
            --each item iterated in _this_ layer is a section table (text of section, type of section)

            --print(textutils.serialise(inarr[j]))
            if string.find(inarr[j][1], "\"") then
                if skip > 0 then
                    skip = skip - 1
                else
                    if not instring then
                        print("found string "..inarr[j][1])
                        --if there's anything before the quotation mark, break it up
                        local before
                        local comment = inarr[j][1]
                        if string.find(inarr[j][1], "\"") > 1 then
                            before = inarr[j][1]:sub(1, string.find(inarr[j][1], "\"") - 1)
                            comment = inarr[j][1]:sub(string.find(inarr[j][1], "\""), #inarr[j][1])
                            print("starts with " .. before.. " and ends with " .. comment)
                        end
                        table.remove(arr[i], j)
                        if before then
                            table.insert(arr[i], j, {before, "text"})
                            table.insert(arr[i], j + 1, {comment, "string"})
                            skip = 1
                        else
                            table.insert(arr[i], j, {comment, "string"})
                        end
                        instring = true
                    else
                        --TODO: properly handle the end of the string
                        print("end of string with " .. inarr[j][1])
                        instring = false
                        inarr[j][2] = "text"
                    end
                end
            else
                if instring then
                    arr[i][j][2] = "string"
                end
            end

        end

    end
    print(textutils.serialise(arr))
    return arr
end

local function multiLineComments(arr)
    local incomment = false
    for i=1,#arr do
        --each item iterated in this layer is a line table
        local inarr = arr[i]
        for j=1,#inarr do
            --each item iterated in _this_ layer is a section table (text of section, type of section)

            print(textutils.serialise(inarr[j]))
            if string.find(inarr[j][1], "%-%-%[%[") then
                print("found comment start")
                print(inarr[j][1])
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
    strings(splitarr)
    --multiLineComments(splitarr)

    return splitarr
end

local args = {...}
local fil = require("/vim/lib/fil")
local filearr = fil.toArr(args[1])
parser.parse(filearr)
--print(textutils.serialise(parser.parse(filearr)))