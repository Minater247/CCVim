local tab = require("/vim/lib/tab")

local function pull(argTable, validArgs, unimplementedArgs)
    if argTable == nil then
        return nil
    end
    local retTable = {}
    retTable["files"] = {}
    for i=1,#argTable,1 do
        if tab.find(validArgs, argTable[i]) then
            --REPLACE PER USAGE
            if argTable[i] == "--version" then
                table.insert(retTable, #retTable + 1, argTable[i])
            end
            --END REPLACE
        elseif tab.find(unimplementedArgs, argTable[i]) then
            print("Ignoring unimplemented argument: "..argTable[i])
        elseif string.sub(argTable[i], 1, 1) == "-" then
            error("Unknown option argument: "..argTable[i])
        else
            table.insert(retTable["files"], #retTable["files"] + 1, argTable[i])
        end
    end
    return retTable
end

return { pull = pull }