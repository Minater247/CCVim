local Tags = {}

local function split_tabs(line)
    local parts, i = {}, 1
    while true do
        local j = string.find(line, "\t", i, true)
        if j then
            parts[#parts + 1] = string.sub(line, i, j - 1)
            i = j + 1
        else
            parts[#parts + 1] = string.sub(line, i)
            return parts
        end
    end
end

function Tags.SearchFile(filename, tag)
    local f = fs.open(filename, "r")
    if not f then return nil end

    local readLine, close = f.readLine, f.close
    local folded = tag:lower()
    local contains, folded_exact, folded_contains

    while true do
        local line = readLine()
        if not line then break end

        local tab = string.find(line, "\t", 1, true)
        local name = tab and string.sub(line, 1, tab - 1) or line
        if name == tag then
            local parts = split_tabs(line)
            close()
            return parts
        elseif not contains and name:find(tag, 1, true) then
            contains = split_tabs(line)
        elseif not folded_exact and name:lower() == folded then
            folded_exact = split_tabs(line)
        elseif not folded_contains and name:lower():find(folded, 1, true) then
            folded_contains = split_tabs(line)
        end
    end

    close()
    return contains or folded_exact or folded_contains
end

return Tags
