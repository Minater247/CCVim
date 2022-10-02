local str = require("/vim/lib/str")
local fil = require("/vim/lib/fil")

local wid, hig = term.getSize()

local vars = {
    syntax = true
}

local buffers = {}

local function newBuffer(path)
    local buf = {}
    buf.lines = {text = fil.toArray(path)}
    buf.filetype = str.getFileExtension(path)
    if fs.exists("/vim/syntax/" .. buf.filetype..".lua") then
        buf.highlighter = require("/vim/syntax/" .. buf.filetype)
    end

    if vars.syntax and buf.highlighter then
        buf.lines.syntax = buf.highlighter.parseSyntax(buf.lines.text)
    end

    buf.cursorX, buf.cursorY = 1, 1
    buf.scrollX, buf.scrollY = 0, 0

    return buf
end


local function drawBuffer(buf)
    term.clear()
    if buf.lines.syntax then
        local limit = hig + buf.scrollY
        if limit > #buf.lines.syntax then
            limit = #buf.lines.syntax
        end
        for i=buf.scrollY + 1, limit do
            local xpos = 1
            for j=1, #buf.lines.syntax[i] do
                term.setCursorPos(xpos - buf.scrollX, i - buf.scrollY)
                term.setTextColor(buf.lines.syntax[i][j].color)
                term.write(buf.lines.syntax[i][j].string)
                xpos = xpos + #buf.lines.syntax[i][j].string
                if xpos > wid then
                    break
                end
            end
        end
    else
        local limit = hig + buf.scrollY
        if limit > #buf.lines.text then
            limit = #buf.lines.text
        end
        for i=buf.scrollY + 1, limit do
            term.setCursorPos(1 - buf.scrollX, i)
            term.write(buf.lines.text[i])
        end
    end
end








local buffer = newBuffer("/test.lua")
drawBuffer(buffer)
term.setCursorPos(1, hig)

os.pullEvent("key")