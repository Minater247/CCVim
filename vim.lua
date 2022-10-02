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
    buf.highlighter = require("/vim/syntax/" .. buf.filetype)

    if vars.syntax and buf.highlighter then
        buf.lines.syntax = buf.highlighter.parseSyntax(buf.lines.text)
    end

    return buf
end


local buf = newBuffer("/test.lua")
local xpos = 1
term.clear()

--draw
local ff = fs.open("/out.test", "w")
ff.write(textutils.serialise(buf.lines.syntax))
ff.close()
for i=1, #buf.lines.syntax do
    local xpos = 1
    for j=1, #buf.lines.syntax[i] do
        term.setCursorPos(xpos, i)
        term.setTextColor(buf.lines.syntax[i][j].color)
        term.write(buf.lines.syntax[i][j].string)
        xpos = xpos + #buf.lines.syntax[i][j].string
    end
end
term.setCursorPos(1, #buf.lines.syntax + 1)