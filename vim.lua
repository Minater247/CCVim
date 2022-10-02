local str = require("/vim/lib/str")
local fil = require("/vim/lib/fil")
local argv = require("/vim/lib/args")
local tab = require("/vim/lib/tab")

local wid, hig = term.getSize()
local currBuf = 0

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
local monitor

if not tab.find(args, "--term") then
    monitor = peripheral.find("monitor")
end

local function resetSize()
    if monitor then
        wid, hig = monitor.getSize()
    else
        wid, hig = term.getSize()
    end
end

local function clear()
    if monitor then
        monitor.clear()
    else
        term.clear()
    end
end

local function setcolors(bg, txt)
    if monitor then
        monitor.setBackgroundColor(bg)
        monitor.setTextColor(txt)
    else
        term.setBackgroundColor(bg)
        term.setTextColor(txt)
    end
end

local function write(message)
    if monitor then
        monitor.write(message)
    else
        term.write(message)
    end
end

local function setpos(xpos, ypos)
    if monitor then
        monitor.setCursorPos(xpos, ypos)
    else
        term.setCursorPos(xpos, ypos)
    end
end

local function loadSyntax(buf)
    if fs.exists("/vim/syntax/" .. buf.filetype..".lua") then
        buf.highlighter = require("/vim/syntax/" .. buf.filetype)
    end
    return buf
end

local function clearScreenLine(line)
    setcolors(colors.black, colors.white)
    setpos(1, line)
    for i=1,wid,1 do
        write(" ")
    end
end

local function err(message)
    clearScreenLine(hig)
    setpos(1, hig)
    setcolors(colors.red, colors.white)
    write(message)
end

local function sendMsg(message)
    clearScreenLine(hig)
    setpos(1, hig)
    setcolors(colors.black, colors.white)
    write(message)
end

local function newBuffer(path)
    local givenpath = path
    path = shell.resolve(path)
    local buf = {}
    buf.lines = {text = fil.toArray(path)}
    buf.path = givenpath
    buf.filetype = str.getFileExtension(path)
    buf = loadSyntax(buf)

    if vars.syntax and buf.highlighter then
        buf.lines.syntax = buf.highlighter.parseSyntax(buf.lines.text)
    end

    buf.cursorX, buf.cursorY = 1, 1
    buf.scrollX, buf.scrollY = 0, 0
    buf.unsavedChanges = false

    return buf
end


local function drawBuffer(buf)
    clear()
    if buf.lines.syntax then
        local limit = hig + buf.scrollY
        if limit > #buf.lines.syntax then
            limit = #buf.lines.syntax
        end
        for i=buf.scrollY + 1, limit do
            local xpos = 1
            for j=1, #buf.lines.syntax[i] do
                setpos(xpos - buf.scrollX, i - buf.scrollY - 1)
                setcolors(colors.black, buf.lines.syntax[i][j].color)
                write(buf.lines.syntax[i][j].string)
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
            setpos(1 - buf.scrollX, i)
            write(buf.lines.text[i])
        end
    end
end

local function pullCommand(input, numeric, len)
    clearScreenLine(hig)
    if input == nil then
        input = ''
    end
    local x,y = 1, hig

    local backspace = false
    local finish = false
  
    repeat
        setcolors(colors.black, colors.white)
        setpos(x,y)
        write(input)
        if backspace then
            write("  ")
            resetSize()
            setpos(x - 1, y)
            if #input < 1 then
                finish = true
            end
        end
        if #input > 0 then
            setpos(x + #input, y)
            setcolors(colors.lightGray, colors.white)
            write(" ")
        end
  
      local ev, p1 = os.pullEvent()
  
        if ev == 'char' then
            local send = true
            if #input < 1 then
                setpos(1, 1)
                setcolors(colors.black, colors.white)
                write(" ")
            end
            if numeric and tonumber(p1) == nil then
                send = false
            end
            if len ~= nil then
                if (#input < len) and send then
                    input = input .. p1
                end
            else
                if send then
                    input = input .. p1
                end
            end
        elseif ev == 'key' then
            if p1 == keys.backspace then
                input = input:sub(1, #input - 1)
                backspace = true
            end
        end
    until (ev == 'key' and p1 == keys.enter) or (finish == true and ev == "key")
    return input
end

local function exitclear()
    setcolors(colors.black, colors.white)
    clear()
    setpos(1, 1)
end


if not args then
    error("Something has gone very wrong with argument initialization!")
end
for i=1, #args.files do
    buffers[#buffers+1] = newBuffer(args.files[i])
end
if #buffers > 0 then
    currBuf = 1
    drawBuffer(buffers[currBuf])
end


local running = true
local changedBuffers = true
while running do
    if changedBuffers then
        drawBuffer(buffers[currBuf])
        local linecount = #buffers[currBuf].lines.text
        local bytecount = 0
        for i=1, #buffers[currBuf].lines.text do
            bytecount = bytecount + #buffers[currBuf].lines.text[i]
        end
        sendMsg("\""..buffers[currBuf].path.."\" "..linecount.."L, "..bytecount.."B")
        changedBuffers = false
    end

    local event = {os.pullEvent()}
    if event[1] == "char" then
        if event[2] == ":" then
            local command = pullCommand(":")
            command = command:sub(2, #command)
            local cmdtab = str.split(command, " ")
            if cmdtab[1] == "q" or cmdtab[1] == "q!" then
                if buffers[currBuf].unsavedChanges and cmdtab[1] ~= ":q!" then
                    err("No write since last change (add ! to override)")
                else
                    table.remove(buffers, currBuf)
                    if currBuf > #buffers then
                        currBuf = currBuf - 1
                        changedBuffers = true
                    end
                    if currBuf == 0 then
                        exitclear()
                        running = false
                    end
                end
            else
                err("Not an editor command: "..cmdtab[1])
            end
        end
    end
end

setpos(1, hig)