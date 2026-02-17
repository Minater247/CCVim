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
    local tlen = #tag

    while true do
        local line = readLine()
        if not line then break end

        if string.sub(line, 1, tlen) == tag and (string.byte(line, tlen + 1) == 9 or #line == tlen) then
            local parts = split_tabs(line)
            close()
            return parts
        end
    end

    close()
    return nil
end

return Tags
