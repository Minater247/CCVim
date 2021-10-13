local function find(tab, query)
    for i=1,#tab,1 do
        if tab[i] == query then
            return i
        end
    end
    return false
end

local function getLongestItem(tab)
    local longest = ""
    for i=1,#tab,1 do
        if #tab[i] > #longest then
            longest = tab[i]
        end
    end
    return longest
end

local function removeDuplicates(tab)
    if tab then
        local outputtable = {}
        for i=1,#tab,1 do
            if not find(outputtable, tab[i]) then
                table.insert(outputtable, #outputtable + 1, tab[i])
            end
        end
        return outputtable
    end
end

local function insertAtPos(tab, item, index) --Insert an item at a position while pushing the item at that position and those after it over 1
    local rettable = {}
    for i=1,index - 1,1 do
        table.insert(rettable, #rettable + 1, tab[i])
    end
    table.insert(rettable, #rettable + 1, item)
    for i=index,#tab do
        table.insert(rettable, #rettable + 1, tab[i])
    end
    return rettable
end

return { find = find, getLongestItem = getLongestItem, insertAtPos = insertAtPos }