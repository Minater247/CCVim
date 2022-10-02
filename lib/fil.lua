local str = require("/vim/lib/str")

local function toArray(filePath)
    local fileHandle = fs.open(filePath, "r")
    if fileHandle then
        local text = fileHandle.readAll()
        fileHandle.close()
        return str.split(text, "\n")
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

return {toArray = toArray, topath = topath}