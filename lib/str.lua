local function split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

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

return { split = split, wordOfPos = wordOfPos }