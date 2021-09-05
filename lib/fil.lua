local function toArr(filePath)
    local fileHandle = fs.open(filePath, "r")
    local log
    if fileHandle then
        log = {}
        local line = fileHandle.readLine()
        while line do
            table.insert(log, line)
            line = fileHandle.readLine()
        end
        fileHandle.close()
        return log
    else
        return false
    end
end

local function topath(inp)
    if string.sub(inp, 1, 1) == "/" then
        return inp
    else
        return("/"..shell.dir().."/"..inp)
    end
end

return {toArr = toArr, topath = topath}