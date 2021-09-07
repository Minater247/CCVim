local function split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

-- Find the word at a given position
local function wordOfPos(inp, pos)
    local beg = pos
    local ed = pos
    while string.sub(inp, beg, beg) ~= " " and beg > 1 and string.sub(inp, beg, beg) ~= nil do
        beg = beg - 1
    end
    while string.sub(inp, ed, ed) ~= " " and ed < #inp and string.sub(inp, ed, ed) ~= nil do
        ed = ed + 1
    end
    if string.sub(inp, beg, beg) == " " then
        beg = beg + 1
    end
    if string.sub(inp, ed, ed) == " " then
        ed = ed - 1
    end
    return string.sub(inp, beg, ed), beg, ed
end

--Returns a table of the beginning index of each word
local function wordBeginnings(inp)
    local letters = {}
    local output = {}
    for i=1,#inp,1 do
        table.insert(letters, #letters + 1, string.sub(inp, i, i))
    end
    if letters[1] ~= " " and letters[1] ~= nil then
        table.insert(output, #output + 1, 1)
    end
    for i=1,#letters,1 do
        if letters[i - 1] == " " and letters[i] ~= " " then
            table.insert(output, #output + 1, i)
        end
    end
    return output
end

return { split = split, wordOfPos = wordOfPos, wordBeginnings = wordBeginnings}