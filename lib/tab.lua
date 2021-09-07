local function find(table, query)
    for i=1,#table,1 do
        if table[i] == query then
            return i
        end
    end
    return false
end

local function getLongestItem(table)
    local longest = ""
    for i=1,#table,1 do
        if #table[i] > #longest then
            longest = table[i]
        end
    end
    return longest
end

return { find = find, getLongestItem = getLongestItem }