local args = {...}

local validArgs = {
    "--version"
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

local version = 0.1
local releasedate = "2021-09-06 | 03:24:55"

local tab = require("/vim/lib/tab")
local argv = require("/vim/lib/args")
local str = require("/vim/lib/str")
local fil = require("/vim/lib/fil")
local monitor
local decargs = argv.pull(args, validArgs, unimplementedArgs)
local openfiles = {}
local wid, hig = term.getSize()
local running = true
local unsavedchanges = false
local filelines = {}
local filename = ""
local currCursorX = 1
local currCursorY = 1
local newfile = false
local currFileOffset = 0
local currXOffset = 0

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

local function setflash(bool)
    if monitor then
        monitor.setCursorBlink(bool)
    else
        term.setCursorBlink(bool)
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

local function pullCommand(input, numeric, len)
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

local function drawFile()
    for i=1,hig-1,1 do
        clearScreenLine(i)
    end
    for i=currFileOffset,(hig - 1) + currFileOffset,1 do
        setpos(1, i - currFileOffset)
        if filelines[i] ~= nil then
            setcolors(colors.black, colors.white)
            write(string.sub(filelines[i], currXOffset + 1, #filelines[i]))
        else
            setcolors(colors.black, colors.purple)
            write("~")
        end
    end
    local tmp
    if filelines[currCursorY + currFileOffset] ~= nil then
        tmp = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset)
    end
    setpos(currCursorX, currCursorY)
    setcolors(colors.lightGray, colors.white)
    if tmp ~= nil and tmp ~= "" then
        write(tmp)
    else
        write(" ")
    end
end

local function moveCursorLeft()
    if currCursorX + currXOffset ~= 1 then
        currCursorX = currCursorX - 1
        if currCursorX < 1 then
            currCursorX = currCursorX + 1
            currXOffset = currXOffset - 1
        end
        drawFile()
    end
end

local function moveCursorRight(endPad)
    if filelines[currCursorY + currFileOffset] ~= nil then
        if currCursorX + currXOffset ~= #(filelines[currCursorY + currFileOffset]) + 1 - endPad then
            currCursorX = currCursorX + 1
            if currCursorX > wid then
                currCursorX = currCursorX - 1
                currXOffset = currXOffset + 1
            end
            drawFile()
        end
    end
end

local function moveCursorUp()
    if currCursorY + currFileOffset ~= 1 then
        currCursorY = currCursorY - 1
        if currCursorX + currXOffset > #(filelines[currCursorY + currFileOffset]) + 1 then
            if filelines[currCursorY + currFileOffset] ~= "" then
                currCursorX = #(filelines[currCursorY + currFileOffset]) + 1 - currXOffset
                if currCursorX < 1 then
                    while currCursorX < 1 do
                        currXOffset = currXOffset - 1
                        currCursorX = currCursorX + 1
                    end
                elseif currCursorX > wid then
                    while currCursorX > wid do
                        currXOffset = currXOffset + 1
                        currCursorX = currCursorX - 1
                    end
                end
            else
                currCursorX = 1
                currXOffset = 0
            end
        end
        if currCursorY < 0 then
            currFileOffset = currFileOffset - 1
            currCursorY = currCursorY + 1
        end
        drawFile()
    end
end

local function moveCursorDown()
    if currCursorY + currFileOffset ~= #filelines then
        currCursorY = currCursorY + 1
        if currCursorX + currXOffset > #(filelines[currCursorY + currFileOffset]) + 1 then
            if filelines[currCursorY + currFileOffset] ~= "" then
                currCursorX = #(filelines[currCursorY + currFileOffset]) + 1 - currXOffset
                if currCursorX < 1 then
                    while currCursorX < 1 do
                        currXOffset = currXOffset - 1
                        currCursorX = currCursorX + 1
                    end
                elseif currCursorX > wid then
                    while currCursorX > wid do
                        currXOffset = currXOffset + 1
                        currCursorX = currCursorX - 1
                    end
                end
            else
                currCursorX = 1
                currXOffset = 0
            end
        end
        if currCursorY > hig - 1 then
            currFileOffset = currFileOffset + 1
            currCursorY = currCursorY - 1
        end
        drawFile()
    end
end

local function insertMode()
    sendMsg("-- INSERT --")
    local ev, key
    while key ~= keys.tab do
        ev, key = os.pullEvent()
        if ev == "key" then
            if key == keys.left then
                moveCursorLeft()
            elseif key == keys.right then
                moveCursorRight(0)
            elseif key == keys.up then
                moveCursorUp()
            elseif key == keys.down then
                moveCursorDown()
            elseif key == keys.backspace then
                if filelines[currCursorY + currFileOffset] ~= "" and filelines[currCursorY + currFileOffset] ~= nil and currCursorX > 1 then
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 2) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #(filelines[currCursorY + currFileOffset]))
                    moveCursorLeft()
                    drawFile()
                    unsavedchanges = true
                else
                    if currCursorX + currXOffset < 2 then
                        currCursorX = #(filelines[currCursorY + currFileOffset - 1]) + 1
                        filelines[currCursorY + currFileOffset - 1] = filelines[currCursorY + currFileOffset - 1] .. filelines[currCursorY + currFileOffset]
                        table.remove(filelines, currCursorY)
                        moveCursorUp()
                        if currCursorX > wid then
                            while currCursorX > wid do
                                currXOffset = currXOffset + 1
                                currCursorX = currCursorX - 1
                            end
                        end
                        drawFile()
                        unsavedchanges = true
                    else
                        filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 2) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #(filelines[currCursorY + currFileOffset]))
                        currXOffset = currXOffset - math.floor(wid / 2)
                        currCursorX = currCursorX + math.floor(wid / 2) - 1
                        if currXOffset < 0 then
                            currCursorX = currXOffset + currCursorX
                            currXOffset = 0
                        end
                        drawFile()
                        unsavedchanges = true
                    end
                end
            elseif key == keys.enter then
                if filelines[currCursorY + currFileOffset] ~= nil then
                    table.insert(filelines, currCursorY + currFileOffset + 1, string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #(filelines[currCursorY + currFileOffset])))
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
                    currCursorY = currCursorY + 1
                    currCursorX = 1
                    currXOffset = 0
                    unsavedchanges = true
                else
                    table.insert(filelines, currCursorY + currFileOffset + 1, "")
                end
                drawFile()
            end
        elseif ev == "char" then
            if filelines[currCursorY + currFileOffset] == nil then
                filelines[currCursorY + currFileOffset] = ""
            end
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. key ..string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #(filelines[currCursorY + currFileOffset]))
            currCursorX = currCursorX + 1
            if currCursorX > wid then
                currCursorX = currCursorX - 1
                currXOffset = currXOffset + 1
            end
            drawFile()
            unsavedchanges = true
        end
    end
    sendMsg(" ")
end

local function appendMode()
    sendMsg("-- APPEND --")
    local ev, key
    while key ~= keys.tab do
        ev, key = os.pullEvent()
        if ev == "key" then
            if key == keys.left then
                moveCursorLeft()
            elseif key == keys.right then
                moveCursorRight(1)
            elseif key == keys.up then
                moveCursorUp()
            elseif key == keys.down then
                moveCursorDown()
            elseif key == keys.backspace then
                if filelines[currCursorY + currFileOffset] ~= "" and filelines[currCursorY + currFileOffset] ~= nil and currCursorX > 1 then
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset]))
                    moveCursorLeft()
                    drawFile()
                    unsavedchanges = true
                else
                    if currCursorX + currXOffset > 1 then
                        filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset]))
                        currXOffset = currXOffset - math.floor(wid / 2)
                        currCursorX = math.floor(wid / 2)
                        if currXOffset < 0 then
                            currCursorX = currXOffset + currCursorX + 1
                            currXOffset = 0
                        end
                        drawFile()
                        unsavedchanges = true
                    end
                end
            elseif key == keys.enter then
                if filelines[currCursorY + currFileOffset] ~= nil then
                    table.insert(filelines, currCursorY + currFileOffset + 1, string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset])))
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset)
                    moveCursorDown()
                    currCursorX = 1
                    currXOffset = 0
                    unsavedchanges = true
                else
                    table.insert(filelines, currCursorY + currFileOffset + 1, "")
                end
                drawFile()
            end
        elseif ev == "char" then
            if filelines[currCursorY + currFileOffset] == nil then
                filelines[currCursorY + currFileOffset] = ""
            end
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset) .. key ..string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset]))
            moveCursorRight(0)
            drawFile()
            unsavedchanges = true
        end
    end
    sendMsg(" ")
end



for i=1,#decargs,1 do
    if decargs[i] == "--version" then
        print("CCVIM - ComputerCraft Vi IMproved "..version)
        print("Build 1  (2021 September 5)")
        do return end --termination
    end
end

if #decargs["files"] > 0 then
    openfiles = decargs["files"]
    if #openfiles > 1 then
        error("Opening multiple files is currently unsupported.")
    end
    if fs.exists(fil.topath(decargs["files"][1])) then
        filelines = fil.toArr(fil.topath(decargs["files"][1]))
    else
        openfiles = {decargs["files"][1]}
        newfile = true
    end
    filename = decargs["files"][1]
else
    openfiles = {}
end

if not (#openfiles > 0) then
    clear()
    resetSize()
    setcolors(colors.black, colors.purple)
    for i=2,hig - 1,1 do
        setpos(1,i)
        write("~")
    end

    setpos(1, 1)
    setcolors(colors.lightGray, colors.white)
    write(" ")
else
    drawFile()
    sendMsg("\""..filename.."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
    if newfile then
        sendMsg("\""..filename.."\" [New File]")
    end
end

while running == true do
    local event, var1 = os.pullEvent()
    if event == "char" then
        if var1 == ":" then
            clearScreenLine(hig)
            local cmd = pullCommand(":", false)
            local cmdtab = str.split(cmd, " ")
            if cmdtab[1] == ":sav" or cmdtab[1] == ":saveas" or cmdtab[1] == ":sav!" or cmdtab[1] == ":saveas!" then
                local name = ""
                for i=2,#cmdtab,1 do
                    name = name .. cmdtab[i]
                    if i ~= #cmdtab then
                        name = name .. " "
                    end
                end
                if #cmdtab < 2 then
                    err("Argument required")
                elseif fs.exists(fil.topath(name)) and not (cmdtab[1] == ":sav!" or cmdtab[1] == ":saveas!") then
                    err("File exists (add ! to override)")
                else
                    local new = true
                    if fs.exists(fil.topath(name), "w") then
                        new = false
                    end
                    local file = fs.open(fil.topath(name), "w")
                    for i=1,#filelines,1 do
                        file.writeLine(filelines[i])
                    end
                    file.close()
                    unsavedchanges = false
                    sendMsg("\""..name.."\" ")
                    if new then
                        write("[New]  ")
                    else
                        write(" ")
                    end
                    write(#filelines.."L written")
                end
            elseif cmdtab[1] == ":q" or cmdtab[1] == ":q!" then
                if unsavedchanges and cmdtab[1] ~= ":q!" then
                    err("No write since last change (add ! to override)")
                else
                    setcolors(colors.black, colors.white)
                    clear()
                    setpos(1, 1)
                    running = false
                end
            elseif cmdtab[1] == ":wq" or cmdtab[1] == ":x" then
                if cmdtab[2] == nil and filename == "" then
                    err("No file name")
                else
                    local name = ""
                    if filename == "" then
                        for i=2,#cmdtab,1 do
                            name = name .. cmdtab[i]
                            if i ~= #cmdtab then
                                name = name .. " "
                            end
                        end
                    else
                        name = filename
                    end
                    local file = fs.open(fil.topath(name), "w")
                    for i=1,#filelines,1 do
                        file.writeLine(filelines[i])
                    end
                    file.close()
                    unsavedchanges = false
                    setcolors(colors.black, colors.white)
                    clear()
                    setpos(1, 1)
                    running = false
                end
            elseif cmdtab[1] == ":e" or cmdtab[1] == ":ex" then
                local name = ""
                for i=2,#cmdtab,1 do
                    name = name .. cmdtab[i]
                    if i ~= #cmdtab then
                        name = name .. " "
                    end
                end
                filename = name
                if fs.exists(fil.topath(name)) then
                    filelines = fil.toArr(fil.topath(name))
                    sendMsg("\""..filename.."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                else
                    newfile = true
                    sendMsg("\""..filename.."\" [New File]")
                end
                drawFile()
                currFileOffset = 0
            elseif cmdtab[1] == ":r" or cmdtab[1] == ":read" then
                local name = ""
                for i=2,#cmdtab,1 do
                    name = name .. cmdtab[i]
                    if i ~= #cmdtab then
                        name = name .. " "
                    end
                end
                if fs.exists(fil.topath(name)) then
                    local secondArr = fil.toArr(fil.topath(name))
                    for i=1,#secondArr,1 do
                        table.insert(filelines, secondArr[i])
                    end
                    drawFile()
                    sendMsg("\""..name.."\" "..#secondArr.."L, "..#(tab.getLongestItem(secondArr)).."C")
                else
                    err("Can't open file "..name)
                end
            elseif cmdtab[1] ~= "" then
                err("Not an editor command or unimplemented: "..cmdtab[1])
            end
        elseif var1 == "i"then
            insertMode()
        elseif var1 == "I" then
            currXOffset = 1
            currCursorX = 0
            drawFile()
            insertMode()
        elseif var1 == "h" then
            moveCursorLeft()
        elseif var1 == "j" then
            moveCursorDown()
        elseif var1 == "k" then
            moveCursorUp()
        elseif var1 == "l" then
            moveCursorRight(0)
        elseif var1 == "H" then
            currCursorY = 1
            drawFile()
        elseif var1 == "M" then
            currCursorY = math.floor((hig - 1) / 2)
            drawFile()
        elseif var1 == "L" then
            currCursorY = hig - 1
            drawFile()
        elseif var1 == "r" then
            local _, chr = os.pullEvent("char")
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. chr .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset]))
            drawFile()
            unsavedchanges = true
        elseif var1 == "J" then
            filelines[currCursorY + currFileOffset] = filelines[currCursorY + currFileOffset] .. " " .. filelines[currCursorY + currFileOffset + 1]
            table.remove(filelines, currCursorY + currFileOffset + 1)
            drawFile()
            unsavedchanges = true
        elseif var1 == "o" then
            table.insert(filelines, currCursorY + currFileOffset + 1, "")
            moveCursorDown()
            currCursorX = 1
            currXOffset = 0
            drawFile()
            insertMode()
            unsavedchanges = true
        elseif var1 == "O" then
            table.insert(filelines, currCursorY + currFileOffset, "")
            currCursorX = 1
            currXOffset = 0
            drawFile()
            insertMode()
            unsavedchanges = true
        elseif var1 == "a" then
            appendMode()
        end
    elseif event == "key" then
        if var1 == keys.left then
            moveCursorLeft()
        elseif var1 == keys.right then
            moveCursorRight(0)
        elseif var1 == keys.up then
            moveCursorUp()
        elseif var1 == keys.down then
            moveCursorDown()
        end
    end
end