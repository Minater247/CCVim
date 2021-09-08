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

local version = 0.14
local releasedate = "2021-09-07"

local tab = require("/vim/lib/tab")
local argv = require("/vim/lib/args")
local str = require("/vim/lib/str")
local fil = require("/vim/lib/fil")
local monitor
local decargs = argv.pull(args, validArgs, unimplementedArgs) --DecodedArguments
local openfiles = {}
local wid, hig = term.getSize()
local running = true
local unsavedchanges = false
local filelines = {}
local filename = ""
local currCursorX = 1
local currCursorY = 1
local newfile = false
local currFileOffset = 0 --AKA CurrYOffset
local currXOffset = 0
local oldx = nil
local copybuffer = ""
local copytype = nil
local jumpbuffer = {}
local jumpoffset = 0 --offset for going before/after a letter
local currfile = 1
local fileContents = {}

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
        if filelines then
            if filelines[i] ~= nil then
                setcolors(colors.black, colors.white)
                write(string.sub(filelines[i], currXOffset + 1, #filelines[i]))
            else
                setcolors(colors.black, colors.purple)
                write("~")
            end
        end
    end
    local tmp
    if filelines then
        if filelines[currCursorY + currFileOffset] ~= nil then
            tmp = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset)
        end
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
    oldx = nil
end

local function moveCursorRight(endPad)
    if endPad == nil then
        endPad = 0
    end
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
    oldx = nil
end

local function moveCursorUp()
    if oldx ~= nil then
        currCursorX = oldx - currXOffset
    else
        oldx = currCursorX + currXOffset
    end
    if currCursorY + currFileOffset ~= 1 then
        currCursorY = currCursorY - 1
        if currCursorX + currXOffset > #(filelines[currCursorY + currFileOffset]) + 1 then
            if filelines[currCursorY + currFileOffset] ~= "" then
                currCursorX = #(filelines[currCursorY + currFileOffset]) + 1 - currXOffset
            else
                currCursorX = 1
                currXOffset = 0
            end
        end
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
        if currCursorY < 0 then
            currFileOffset = currFileOffset - 1
            currCursorY = currCursorY + 1
        end
        drawFile()
    end
end

local function moveCursorDown()
    if oldx ~= nil then
        currCursorX = oldx - currXOffset
    else
        oldx = currCursorX + currXOffset
    end
    if currCursorY + currFileOffset ~= #filelines then
        currCursorY = currCursorY + 1
        if currCursorX + currXOffset > #(filelines[currCursorY + currFileOffset]) + 1 then
            if filelines[currCursorY + currFileOffset] ~= "" then
                currCursorX = #(filelines[currCursorY + currFileOffset]) + 1 - currXOffset
            else
                currCursorX = 1
                currXOffset = 0
            end
        end
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
                        table.remove(filelines, currCursorY + currFileOffset)
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
        print("CCVIM - ComputerCraft Vi IMproved "..version.." ("..releasedate..")")
        do return end --termination
    end
end

if #decargs["files"] > 0 then
    openfiles = decargs["files"]
    if fs.isDir(fil.topath(decargs["files"][1])) then
        error("Cannot currently open directories")
    end
    for i=1,#openfiles,1 do
        if fs.exists(fil.topath(decargs["files"][i])) then
            table.insert(fileContents, #fileContents + 1, fil.toArr(fil.topath(decargs["files"][i])))
        else
            openfiles = {decargs["files"][1]}
            table.insert(fileContents, #fileContents + 1, {})
            newfile = true
        end
        filelines = fileContents[1]
    end
    filename = decargs["files"][1]
else
    openfiles = {}
    currfile = 0
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
    if newfile then
        sendMsg("\""..filename.."\" [New File]")
    else
        sendMsg("\""..filename.."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                    if fs.exists(fil.topath(name)) then
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
            elseif cmdtab[1] == ":w" or cmdtab[1] == ":w!" then
                local name = ""
                if #cmdtab > 1 then
                    for i=2,#cmdtab,1 do
                        name = name .. cmdtab[i]
                        if i ~= #cmdtab then
                            name = name .. " "
                        end
                    end
                else
                    name = filename
                end
                if #cmdtab < 2 and filename == "" then
                    err("No file name")
                else
                    local new = true
                    if fs.exists(fil.topath(name)) then
                        new = false
                    end
                    local fl = fs.open(fil.topath(name), "w")
                    for i=1,#filelines,1 do
                        fl.writeLine(filelines[i])
                    end
                    fl.close()
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
                table.insert(openfiles, #openfiles + 1, filename)
                table.insert(fileContents, #fileContents + 1, fil.toArr(fil.topath(filename)))
                currfile = #fileContents
                filelines = fileContents[currfile]
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
            elseif cmdtab[1] == ":tabn" or cmdtab[1] == ":tabnext" then
                if #fileContents > 1 then
                    if currfile ~= #fileContents then
                        sendMsg(currfile)
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = currfile + 1
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                        clearScreenLine(hig)
                    else
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = 1
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                        clearScreenLine(hig)
                    end
                    filename = openfiles[currfile]
                end
            elseif cmdtab[1] == ":tabp" or cmdtab[1] == ":tabprevious" then
                if #fileContents > 1 then
                    if currfile ~= 1 then
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = currfile - 1
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                        clearScreenLine(hig)
                    else
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = #fileContents
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                        clearScreenLine(hig)
                    end
                    filename = openfiles[currfile]
                end
            elseif cmdtab[1] == ":tabm" or cmdtab[1] == ":tabmove" then
                fileContents[currfile] = filelines
                fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                local tmp = tonumber(cmdtab[2])
                if tonumber(cmdtab[2]) >= 0 and tonumber(cmdtab[2]) <= #fileContents - 1 then
                    currfile = tonumber(cmdtab[2]) + 1
                    sendMsg(currfile)
                    filelines = fileContents[currfile]
                    if fileContents[currfile]["cursor"] then
                        currCursorX = fileContents[currfile]["cursor"][1]
                        currXOffset = fileContents[currfile]["cursor"][2]
                        currCursorY = fileContents[currfile]["cursor"][3]
                        currFileOffset = fileContents[currfile]["cursor"][4]
                    end
                    drawFile()
                end
                clearScreenLine(hig)
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
        elseif var1 == "A" then
            currCursorX = #filelines[currCursorY + currFileOffset]
            currXOffset = 0
            while currCursorX > wid do
                currXOffset = currXOffset + 1
                currCursorX = currCursorX - 1
            end
            drawFile()
            appendMode()
        elseif var1 == "Z" then
            local _,c = os.pullEvent("char")
            if c == "Q" then
                setcolors(colors.black, colors.white)
                clear()
                setpos(1, 1)
                running = false
            elseif c == "Z" then
                if filename == "" then
                    err("No file name")
                else
                    local file = fs.open(fil.topath(filename), "w")
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
            end
        elseif var1 == "y" then
            local _, c = os.pullEvent("char")
            if c == "y" then
                copybuffer = filelines[currCursorY + currFileOffset]
                copytype = "line"
            elseif c == "w" then
                local word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                copybuffer = word
                if ed ~= #filelines[currCursorY + currFileOffset] then
                    copybuffer = copybuffer .. " "
                end
                copytype = "text"
            elseif c == "i" then
                local _, ch = os.pullEvent("char")
                if ch == "w" then
                    local word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                    copybuffer = word
                    copytype = "text"
                end
            elseif c == "a" then
                local _, ch = os.pullEvent("char")
                if ch == "w" then
                    local word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                    copybuffer = word
                    if ed ~= #filelines[currCursorY + currFileOffset] then
                        copybuffer = copybuffer .. " "
                    elseif beg ~= 1 then
                        copybuffer = " " .. copybuffer
                    end
                    copytype = "text"
                end
            elseif c == "$" then
                copybuffer = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #filelines[currCursorY + currFileOffset])
                copytype = "text"
            end
        elseif var1 == "x" then
            copybuffer = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset)
            copytype = "text"
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #filelines[currCursorY + currFileOffset])
            drawFile()
            unsavedchanges = true
        elseif var1 == "d" then
            local _, c = os.pullEvent("char")
            if c == "d" then
                copybuffer = filelines[currCursorY + currFileOffset]
                copytype = "line"
                table.remove(filelines, currCursorY + currFileOffset)
                drawFile()
                unsavedchanges = true
            elseif c == "w" then
                local word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                copybuffer = word
                if ed ~= #filelines[currCursorY + currFileOffset] then
                    copybuffer = copybuffer .. " "
                end
                copytype = "text"
                if ed ~= #filelines[currCursorY + currFileOffset] then
                    ed = ed + 1
                end
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, beg - 1) .. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                drawFile()
                unsavedchanges = true
            elseif c == "i" then
                local _, ch = os.pullEvent("char")
                local word,beg,ed
                if ch == "w" then
                    word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                    copybuffer = word
                    copytype = "text"
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, beg - 1) .. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                    drawFile()
                    unsavedchanges = true
                end
            elseif c == "a" then
                local _, ch = os.pullEvent("char")
                if ch == "w" then
                    local word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                    copybuffer = word
                    if ed ~= #filelines[currCursorY + currFileOffset] then
                        copybuffer = copybuffer .. " "
                        ed = ed + 1
                    elseif beg ~= 1 then
                        copybuffer = " " .. copybuffer
                        beg = beg - 1
                    end
                    copytype = "text"
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, beg - 1) .. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                    drawFile()
                    unsavedchanges = true
                end
            elseif c == "$" then
                copybuffer = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #filelines[currCursorY + currFileOffset])
                copytype = "text"
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
                drawFile()
                unsavedchanges = true
            end
        elseif var1 == "D" then
            copybuffer = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #filelines[currCursorY + currFileOffset])
            copytype = "text"
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
            drawFile()
            unsavedchanges = true
        elseif var1 == "p" then
            if copytype == "line" then
                table.insert(filelines, currCursorY + currFileOffset + 1, copybuffer)
            elseif copytype == "text" then
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset) .. copybuffer .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #filelines[currCursorY + currFileOffset])
                currCursorX = currCursorX + #copybuffer --minus one so we can have the function reset viewpoint
                while currCursorX > wid do
                    currCursorX = currCursorX - 1
                    currXOffset = currXOffset + 1
                end
            elseif copytype == "linetable" then
                for i=#copybuffer,1,-1 do
                    table.insert(filelines, currCursorY + currFileOffset + 1, copybuffer[i])
                end
            end
            drawFile()
            unsavedchanges = true
        elseif var1 == "P" then
            if copytype == "line" then
                table.insert(filelines, currCursorY + currFileOffset, copybuffer)
            elseif copytype == "text" then
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. copybuffer .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #filelines[currCursorY + currFileOffset])
                currCursorX = currCursorX + #copybuffer
                while currCursorX > wid do
                    currCursorX = currCursorX - 1
                    currXOffset = currXOffset + 1
                end
            elseif copytype == "linetable" then
                for i=#copybuffer,1,-1 do
                    table.insert(filelines, currCursorY + currFileOffset, copybuffer[i])
                end
                currCursorY = currCursorY + #copybuffer
                while currCursorY > hig - 1 do
                    currCursorY = currCursorY - 1
                    currFileOffset = currFileOffset + 1
                end
            end
            drawFile()
            unsavedchanges = true
        elseif var1 == "$" then
            currCursorX = #filelines[currCursorY + currFileOffset]
            while currCursorX > wid do
                currCursorX = currCursorX - 1
                currXOffset = currXOffset + 1
            end
            drawFile()
        elseif var1 == "0" then --must be before the number things so 0 isn't captured too
            currCursorX = 1
            currXOffset = 0
            drawFile()
        elseif tonumber(var1) ~= nil then
            local num = var1 --num IS A STRING! Convert it to a number with tonumber() before use!
            local _, ch
            local var = 0
            while tonumber(var) ~= nil do
                _, var = os.pullEvent("char")
                if tonumber(var) ~= nil then
                    num = num .. var
                else
                    ch = var
                end
            end
            if ch == "y" then
                _, ch = os.pullEvent("char")
                if ch == "y" then
                    if not (currCursorY + currFileOffset + tonumber(num) > #filelines) then
                        copybuffer = {}
                        for i=1,tonumber(num),1 do
                            table.insert(copybuffer, #copybuffer + 1, filelines[currCursorY + currFileOffset + i - 1])
                        end
                        copytype = "linetable"
                    end
                end
            elseif ch == "d" then
                _, ch = os.pullEvent("char")
                if ch == "d" then
                    if not (currCursorY + currFileOffset + tonumber(num) > #filelines) then
                        copybuffer = {}
                        for i=1,tonumber(num),1 do
                            table.insert(copybuffer, #copybuffer + 1, filelines[currCursorY + currFileOffset + i - 1])
                        end
                        copytype = "linetable"
                        for i=1,tonumber(num),1 do
                            table.remove(filelines, currCursorY + currFileOffset)
                        end
                        drawFile()
                        unsavedchanges = true
                    end
                end
            elseif ch == "g" then
                _, ch = os.pullEvent("char")
                if ch == "g" then
                    currCursorY = tonumber(num) - 1 --minus one for moveCursorDown
                    currFileOffset = 0
                    currCursorX = 1
                    currXOffset = 0
                    while currCursorY > hig - 1 do
                        currCursorY = currCursorY - 1
                        currFileOffset = currFileOffset + 1
                    end
                    drawFile()
                elseif ch == "t" then
                    fileContents[currfile] = filelines
                    fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                    currfile = tonumber(num)
                    if currfile <= #fileContents and currfile > 1 then
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                    end
                end
            end
        elseif var1 == "g" then
            local _,c = os.pullEvent("char")
            if c == "J" then
                filelines[currCursorY + currFileOffset] = filelines[currCursorY + currFileOffset] .. filelines[currCursorY + currFileOffset + 1]
                table.remove(filelines, currCursorY + currFileOffset + 1)
                drawFile()
                unsavedchanges = true
            elseif c == "g" then
                currCursorY = 1
                currFileOffset = 0
                currCursorX = 1
                currXOffset = 0
                drawFile()
            elseif c == "e" or c == "E" then
                local begs = str.wordEnds(filelines[currCursorY + currFileOffset], not string.match(c, "%u"))
                if currCursorX + currXOffset > begs[1] then
                    currCursorX = currCursorX - 1
                    while not tab.find(begs, currCursorX + currXOffset) do
                        currCursorX = currCursorX - 1
                    end
                    while currCursorX > wid do
                        currCursorX = currCursorX + 1
                        currXOffset = currXOffset - 1
                    end
                    drawFile()
                end
            elseif c == "_" then
                currCursorX = #filelines[currCursorY + currFileOffset]
                currXOffset = 0
                local i = currCursorX
                while string.sub(filelines[currCursorY + currFileOffset], i, i) == " " do
                    i = i - 1
                end
                currCursorX = i
                if currCursorX > wid then
                    while currCursorX > wid do
                        currCursorX = currCursorX - 1
                        currXOffset = currXOffset + 1
                    end
                elseif currCursorX < 1 then
                    while currCursorX < 1 do
                        currCursorX = currCursorX + 1
                        currXOffset = currXOffset - 1
                    end
                end
                drawFile()
            elseif c == "t" then
                if #fileContents > 1 then
                    if currfile ~= #fileContents then
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = currfile + 1
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                    else
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = 1
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                    end
                    filename = openfiles[currfile]
                end
            elseif c == "T" then
                if #fileContents > 1 then
                    if currfile ~= 1 then
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = currfile - 1
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                    else
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = #fileContents
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                    end
                    filename = openfiles[currfile]
                end
            end
        elseif var1 == "G" then
            currFileOffset = 0
            currCursorY = #filelines
            while currCursorY > hig - 1 do
                currCursorY = currCursorY - 1
                currFileOffset = currFileOffset + 1
            end
            currCursorX = 1
            currXOffset = 0
            drawFile()
        elseif var1 == "w" or var1 == "W" then
            local begs = str.wordBeginnings(filelines[currCursorY + currFileOffset], not string.match(var1, "%u"))
            if currCursorX + currXOffset < begs[#begs] then
                currCursorX = currCursorX + 1
                while not tab.find(begs, currCursorX + currXOffset) do
                    currCursorX = currCursorX + 1
                end
                while currCursorX > wid do
                    currCursorX = currCursorX - 1
                    currXOffset = currXOffset + 1
                end
                oldx = currCursorX + currXOffset
                drawFile()
            end
        elseif var1 == "e" or var1 == "E" then
            local begs = str.wordEnds(filelines[currCursorY + currFileOffset], not string.match(var1, "%u"))
            if currCursorX + currXOffset < begs[#begs] then
                currCursorX = currCursorX + 1
                while not tab.find(begs, currCursorX + currXOffset) do
                    currCursorX = currCursorX + 1
                end
                while currCursorX < 1 do
                    currCursorX = currCursorX - 1
                    currXOffset = currXOffset + 1
                end
                drawFile()
            end
        elseif var1 == "b" or var1 == "B" then
            local begs = str.wordBeginnings(filelines[currCursorY + currFileOffset], not string.match(var1, "%u"))
            if currCursorX + currXOffset > begs[1] then
                currCursorX = currCursorX - 1
                while not tab.find(begs, currCursorX + currXOffset) do
                    currCursorX = currCursorX - 1
                end
                while currCursorX > wid do
                    currCursorX = currCursorX + 1
                    currXOffset = currXOffset - 1
                end
                drawFile()
            end
        elseif var1 == "^" then
            currCursorX = 1
            currXOffset = 0
            local i = currCursorX
            while string.sub(filelines[currCursorY + currFileOffset], i, i) == " " do
                i = i + 1
            end
            currCursorX = i
            while currCursorX > wid do
                currCursorX = currCursorX - 1
                currXOffset = currXOffset + 1
            end
            drawFile()
        elseif var1 == "f" or var1 == "t" then
            local _,c = os.pullEvent("char")
            local idx = str.indicesOfLetter(filelines[currCursorY + currFileOffset], c)
            if #idx > 0 then
                if currCursorX + currFileOffset < idx[#idx] - jumpoffset then
                    local oldcursor = currCursorX
                    currCursorX = currCursorX + (1 + jumpoffset)
                    while not tab.find(idx, currCursorX + currXOffset) and currCursorX + currXOffset ~= #filelines[currCursorY + currFileOffset] do
                        currCursorX = currCursorX + 1
                    end
                    if not tab.find(idx, currCursorX + currXOffset) then
                        currCursorX = oldcursor
                    end
                    if var1 == "t" then
                        currCursorX = currCursorX - 1
                    end
                    while currCursorX > wid do
                        currCursorX = currCursorX - 1
                        currXOffset = currXOffset + 1
                    end
                    drawFile()
                    jumpbuffer = {var1, c}
                    if var1 == "t" then
                        jumpoffset = 1
                    else
                        jumpoffset = 0
                    end
                end
            end
        elseif var1 == "F" or var1 == "T" then
            local _,c = os.pullEvent("char")
            local idx = str.indicesOfLetter(filelines[currCursorY + currFileOffset], c)
            if #idx > 0 then
                if currCursorX + currFileOffset > idx[1] + jumpoffset then
                    currCursorX = currCursorX - (1 + jumpoffset)
                    while not tab.find(idx, currCursorX + currXOffset) and currCursorX > 1 do
                        currCursorX = currCursorX - 1
                    end
                    if var1 == "T" then
                        currCursorX = currCursorX + 1
                    end
                    while currCursorX < 1 do
                        currCursorX = currCursorX + 1
                        currXOffset = currXOffset - 1
                    end
                    drawFile()
                    jumpbuffer = {var1, c}
                    if var1 == "T" then
                        jumpoffset = 1
                    else
                        jumpoffset = 0
                    end
                end
            end
        elseif var1 == ";" or var1 == "," then
            local tx = jumpbuffer[1]
            if var1 == "," then
                if string.match(tx, "%u") then
                    tx = string.lower(tx)
                else
                    tx = string.upper(tx)
                end
            end
            if string.match(tx, "%u") then
                local c = jumpbuffer[2]
                local idx = str.indicesOfLetter(filelines[currCursorY + currFileOffset], c)
                if #idx > 0 then
                    if currCursorX + currFileOffset > idx[1] + jumpoffset then
                        currCursorX = currCursorX - (1 + jumpoffset)
                        while not tab.find(idx, currCursorX + currXOffset) do
                            currCursorX = currCursorX - 1
                        end
                        if jumpbuffer[1] == "T" or jumpbuffer[1] == "t" then
                            currCursorX = currCursorX + 1
                        end
                        while currCursorX < 1 do
                            currCursorX = currCursorX + 1
                            currXOffset = currXOffset - 1
                        end
                        drawFile()
                    end
                end
            else
                local c = jumpbuffer[2]
                local idx = str.indicesOfLetter(filelines[currCursorY + currFileOffset], c)
                if #idx > 0 then
                    if currCursorX + currFileOffset < idx[#idx] - jumpoffset then
                        local oldcursor = currCursorX
                        currCursorX = currCursorX + (1 + jumpoffset)
                        while not tab.find(idx, currCursorX + currXOffset) and currCursorX + currXOffset ~= #filelines[currCursorY + currFileOffset] do
                            currCursorX = currCursorX + 1
                        end
                        if not tab.find(idx, currCursorX + currXOffset) then
                            currCursorX = oldcursor
                        end
                        if jumpbuffer[1] == "t" or jumpbuffer[1] == "T" then
                            currCursorX = currCursorX - 1
                        end
                        while currCursorX > wid do
                            currCursorX = currCursorX - 1
                            currXOffset = currXOffset + 1
                        end
                        drawFile()
                    end
                end
            end
        elseif var1 == "c" then
            local _, c = os.pullEvent("char")
            if c == "c" then
                filelines[currCursorY + currFileOffset] = ""
                currCursorX = 1
                currXOffset = 0
                drawFile()
                unsavedchanges = true
                insertMode()
            elseif c == "$" then
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
                drawFile()
                unsavedchanges = true
                insertMode()
            elseif c == "i" then
                local _, ch = os.pullEvent("char")
                if ch == "w" then
                    local word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, beg - 1) .. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                    currCursorX = beg
                    currXOffset = 0
                    while currCursorX > wid do
                        currCursorX = currCursorX - 1
                        currXOffset = currXOffset + 1
                    end
                    drawFile()
                    unsavedchanges = true
                    insertMode()
                end
            elseif c == "w" or c == "e" then
                local word, beg, ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1).. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                drawFile()
                unsavedchanges = true
                insertMode()
            end
        elseif var1 == "C" then
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
            drawFile()
            unsavedchanges = true
            insertMode()
        elseif var1 == "s" then
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #filelines[currCursorY + currFileOffset])
            drawFile()
            unsavedchanges = true
            insertMode()
        elseif var1 == "S" then
            filelines[currCursorY + currFileOffset] = ""
            currCursorX = 1
            currXOffset = 0
            drawFile()
            unsavedchanges = true
            insertMode()
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