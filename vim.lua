local str = require("/vim/lib/str")
local fil = require("/vim/lib/fil")
local argv = require("/vim/lib/args")

local wid, hig = term.getSize()

local vars = {
    syntax = true
}
local validArgs = {
    "--version",
    "--term"
}

local unimplementedArgs = {
    "--",
    "-v",
    "-e",
    "-E",
    "-s",
    "-d",
    "-y",
    "-R",
    "-Z",
    "-m",
    "-M",
    "-b",
    "-l",
    "-C",
    "-N",
    "-V",
    "-D",
    "-n",
    "-r",
    "-L",
    "-T",
    "--not-a-term",
    "--ttyfail",
    "-u",
    "--noplugin",
    "-p",
    "-o",
    "-O",
    "+",
    "--cmd",
    "-c",
    "-S",
    "-s",
    "-w",
    "-W",
    "-x",
    "--startuptime",
    "-i",
    "--clean",
    "-h",
    "--help"
}
local args = argv.pull({...}, validArgs, unimplementedArgs)

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
                term.setCursorPos(xpos - buf.scrollX, i - buf.scrollY - 1)
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




if not args then
    error("Something has gone very wrong with argument initialization!")
end
for i=1, #args.files do
    buffers[#buffers+1] = newBuffer(args.files[i])
end



drawBuffer(buffers[1])
term.setCursorPos(1, hig)

os.pullEvent("key")