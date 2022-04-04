local tab = require("/vim/lib/tab")

local punctuation = {
    ".",
    "!",
    "?",
    "/",
    ",",
    ":",
    "[",
    "]",
    "{",
    "}",
    "(",
    ")",
    "@",
    "-",
    "\""
}

local escapable = {
    "\""
}

local function split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

-- Find the word at a given position
local function wordOfPos(inp, pos, dopunct)
    local beg = pos
    local ed = pos
    if not dopunct then
        while string.sub(inp, beg, beg) ~= " " and beg > 1 and string.sub(inp, beg, beg) ~= nil do
            beg = beg - 1
        end
        while string.sub(inp, ed, ed) ~= " " and ed < #inp and string.sub(inp, ed, ed) ~= nil do
            ed = ed + 1
        end
    else
        while string.sub(inp, beg, beg) ~= " " and beg > 1 and string.sub(inp, beg, beg) ~= nil and not tab.contains(punctuation, string.sub(inp, beg, beg)) do
            beg = beg - 1
        end
        if tab.contains(punctuation, string.sub(inp, beg, beg)) then
            beg = beg + 1
        end
        while string.sub(inp, ed, ed) ~= " " and ed < #inp and string.sub(inp, ed, ed) ~= nil and not tab.contains(punctuation, string.sub(inp, ed, ed)) do
            ed = ed + 1
        end
        if tab.contains(punctuation, string.sub(inp, ed, ed)) then
            ed = ed - 1
        end
    end
    if string.sub(inp, beg, beg) == " " then
        beg = beg + 1
    end
    if string.sub(inp, ed, ed) == " " then
        ed = ed - 1
    end
    return string.sub(inp, beg, ed), beg, ed
end

--Returns a table of the beginning index of each word, if nopunc then punctuation counts as a split
local function wordBeginnings(inp, nopunc)
    if nopunc == nil then
        nopunc = false
    end
    local letters = {}
    local output = {}
    for i=1,#inp,1 do
        table.insert(letters, #letters + 1, string.sub(inp, i, i))
    end
    if letters[1] ~= " " and letters[1] ~= nil and not (tab.find(punctuation, letters[1] and nopunc)) then
        table.insert(output, #output + 1, 1)
    end
    for i=1,#letters,1 do
        if (letters[i - 1] == " " and letters[i] ~= " " and not (tab.find(punctuation, letters[i]) and nopunc)) or (tab.find(punctuation, letters[i - 1]) and letters[i] ~= " " and nopunc) then
            table.insert(output, #output + 1, i)
        end
    end
    return output
end

--Returns a table with the end index of each word
local function wordEnds(inp, nopunc)
    if nopunc == nil then
        nopunc = false
    end
    local letters = {}
    local output = {}
    for i=1,#inp,1 do
        table.insert(letters, #letters + 1, string.sub(inp, i, i))
    end
    for i=1,#letters,1 do
        if ((letters[i + 1] == " " or letters[i + 1] == nil) and letters[i] ~= " " and not (tab.find(punctuation, letters[i]) and nopunc)) or (tab.find(punctuation, letters[i + 1]) and letters[i] ~= " " and nopunc) then
            table.insert(output, #output + 1, i)
        end
    end
    return output
end
--Returns a table of the indices of every letter, case-sensitive
local function indicesOfLetter(inp, chr)
    if inp == nil then
        return {}
    end
    local output = {}
    for i=1,#inp,1 do
        if string.sub(inp, i, i) == chr then
            if tab.find(escapable, chr) then
                if string.sub(inp, i-1, i-1) ~= "\\" then
                    table.insert(output, #output + 1, i)
                end
            else
                table.insert(output, #output + 1, i)
            end
        end
    end
    return output
end

local function find(inp, mtch, ignore)
    if inp then
        for i=1,#inp,1 do
            if string.sub(inp, i, i + #mtch - 1) == mtch then
                if ignore then
                    if not tab.find(ignore, i) then
                        return i
                    end
                else
                    return i
                end
            end
        end
        return false
    else
        return false
    end
end

local function getFileExtension(inpstring)
    local outputstring = ""
    local i = #inpstring
    while i > 0 and string.sub(inpstring, i, i) ~= "." do
        outputstring = string.sub(inpstring, i, i) .. outputstring
        i = i - 1
    end
    if i ~= 0 and outputstring ~= inpstring and outputstring ~= string.sub(inpstring, 2, #inpstring) then
        return outputstring
    else
        return ""
    end
end

return { split = split, wordOfPos = wordOfPos, wordBeginnings = wordBeginnings, wordEnds = wordEnds, indicesOfLetter = indicesOfLetter, find = find, getFileExtension = getFileExtension }