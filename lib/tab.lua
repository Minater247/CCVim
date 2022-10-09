local function find(table, query)
    for i=1,#table,1 do
        if table[i] == query then
            return i
        end
    end
    return false
end

local contains = find

local function getLongestItem(table)
    local longest = ""
    for i=1,#table,1 do
        if #table[i] > #longest then
            longest = table[i]
        end
    end
    return longest
end

local function removeDuplicates(table)
    if table then
        local outputtable = {}
        for i=1,#table,1 do
            if not find(outputtable, table[i]) then
                table.insert(outputtable, #outputtable + 1, table[i])
            end
        end
        return outputtable
    end
end

local function countchars(tab)
    local count = 0
    for i=1,#tab,1 do
        count = count + #tab[i]
    end
    return count
end

local function sub(tab, startpos, endpos)
    local output = {}
    for i=startpos,endpos,1 do
        output[#output+1] = tab[i]
    end
    return output
end

return { find = find, getLongestItem = getLongestItem, countchars = countchars, contains = contains, removeDuplicates = removeDuplicates, sub = sub }