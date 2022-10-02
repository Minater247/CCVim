local str = require("/vim/lib/str")
local fil = require("/vim/lib/fil")

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

    return buf
end









local buf = newBuffer("/out.test")
local xpos = 1
term.clear()

local wid, hig = term.getSize()

--template drawing function to draw a buffer
local ff = fs.open("/out.test", "w")
ff.write(textutils.serialise(buf.lines.syntax))
ff.close()
if buf.lines.syntax then
    for i=1, #buf.lines.syntax do
        local locali = i
        if i > hig then
            term.scroll(1)
            locali = hig
        end

        local xpos = 1
        for j=1, #buf.lines.syntax[i] do
            term.setCursorPos(xpos, locali)
            term.setTextColor(buf.lines.syntax[i][j].color)
            term.write(buf.lines.syntax[i][j].string)
            xpos = xpos + #buf.lines.syntax[i][j].string
        end
    end
else
    for i=1, #buf.lines.text do
        term.setCursorPos(1, i)
        term.write(buf.lines.text[i])
    end
end
term.setCursorPos(1, hig)