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

local version = 0.16
local releasedate = "2021-09-10"

local tab = require("/vim/lib/tab")
local argv = require("/vim/lib/args")
local str = require("/vim/lib/str")
local fil = require("/vim/lib/fil")
local monitor
local decargs = argv.pull(args, validArgs, unimplementedArgs) --DecodedArguments
local openfiles = {}
local wid, hig = term.getSize()
local running = true
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
local motd = false
local remappings = {}
local filetypes = false
local filetypearr = {}
local mobile = false
local linenumbers = false
local lineoffset = 0
local syntaxhighlighting = false

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

local function getWindSize()
    if monitor then
        return monitor.getSize()
    else
        return term.getSize()
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

--pull event with remaps
local function pullEventWRMP()
    local e, s, v2, v3 = os.pullEvent()
    if e == "char" and remappings[s] then
        s = remappings[s]
    end
    return e, s, v2, v3
end

local function printarray(arr)
    for i=1,#arr,1 do
        print(arr[i])
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
  
      local ev, p1 = pullEventWRMP()
  
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
    motd = false
    for i=1,hig-1,1 do
        clearScreenLine(i)
    end
    local length = #(tostring(currCursorY + currFileOffset + hig - 1))
    for i=currFileOffset,(hig - 1) + currFileOffset,1 do
        setpos(1, i - currFileOffset)
        if filelines then
            if filelines[i] ~= nil then
                setcolors(colors.black, colors.yellow)
                if linenumbers then
                    if i < 1000 then
                        for i=1,3 - #(tostring(i)),1 do
                            write(" ")
                        end
                    end
                    if i < 10000 then
                        write(i)
                        write(" ")
                    else
                        write("10k+")
                    end
                end
                setcolors(colors.black, colors.white)
                if filetypes and fileContents[currfile]["filetype"] then
                    local synt = filetypearr[fileContents[currfile]["filetype"]].syntax()
                    local wordsOfLine = str.split(filelines[i], " ")
                    setpos(1 - currXOffset + lineoffset, i - currFileOffset)
                    for j=1,#wordsOfLine,1 do
                        if tab.find(synt[1], wordsOfLine[j]) then
                            setcolors(colors.yellow, colors.blue)
                        elseif tab.find(synt[2][1], wordsOfLine[j]) then
                            setcolors(colors.black, colors.lightBlue)
                        elseif tab.find(synt[2][2], wordsOfLine[j]) then
                            setcolors(colors.black, colors.purple)
                        else
                            setcolors(colors.black, colors.white)
                        end
                        write(wordsOfLine[j])
                        if j ~= #wordsOfLine then
                            setcolors(colors.black, colors.white)
                            write(" ")
                        end
                    end
                    --another loop for drawing strings
                    setpos(1 - currXOffset + lineoffset, i - currFileOffset)
                    local quotationmarks = str.indicesOfLetter(filelines[i], synt[3])
                    local inquotes = false
                    local justset = false
                    local quotepoints = {}
                    setcolors(colors.black, colors.red)
                    for j=1,#filelines[i],1 do
                        setpos(1 - currXOffset + lineoffset + j - 1, i - currFileOffset)
                        if tab.find(quotationmarks, j) then
                            if not inquotes then
                                if j < quotationmarks[#quotationmarks] then
                                    inquotes = true
                                    justset = true
                                end
                            end
                        end
                        if inquotes then
                            write(string.sub(filelines[i], j, j))
                            table.insert(quotepoints, #quotepoints, j - 2) --Don't know why I need to subtract 2 but heck it works
                        end
                        if tab.find(quotationmarks, j) and not justset then
                            if inquotes then
                                inquotes = false
                            end
                        end
                        justset = false
                    end
                    local commentstart = 0
                    commentstart = str.find(filelines[i], synt[4], quotepoints)
                    if commentstart and commentstart ~= false then
                        setpos(1 - currXOffset + lineoffset + commentstart - 1, i - currFileOffset)
                        setcolors(colors.black, colors.green)
                        write(string.sub(filelines[i], commentstart, #filelines[i]))
                    end
                    --repeat the line number drawing since we just overwrote it
                    setpos(1, i)
                    setcolors(colors.black, colors.yellow)
                    local _, yy = getWindSize()
                    if yy ~= hig then
                        if i < 1000 then
                            for i=1,3 - #(tostring(i)),1 do
                                write(" ")
                            end
                        end
                        if i < 10000 then
                            write(i)
                            write(" ")
                        else
                            write("10k+")
                        end
                    end
                else
                    write(string.sub(filelines[i], currXOffset + 1, #filelines[i]))
                end
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
    if filelines then
        setpos(currCursorX + lineoffset, currCursorY)
    else
        setpos(currCursorX, currCursorY)
    end
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
        if currCursorX + currXOffset < #(filelines[currCursorY + currFileOffset]) + 1 - endPad then
            currCursorX = currCursorX + 1
            if currCursorX + lineoffset > wid then
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
        elseif currCursorX + lineoffset > wid then
            while currCursorX + lineoffset > wid do
                currXOffset = currXOffset + 1
                currCursorX = currCursorX - 1
            end
        end
        if currCursorY < 1 then
            currFileOffset = currFileOffset - 1
            currCursorY = currCursorY + 1
        end
        if currFileOffset < 0 then
            currFileOffset = currFileOffset + 1
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
    if currCursorY + currFileOffset < #filelines then
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
        elseif currCursorX + lineoffset > wid then
            while currCursorX + lineoffset > wid do
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

local function redrawTerm()
    clearScreenLine(hig)
    if motd then
        clear()
        setcolors(colors.black, colors.white)
        setpos((wid / 2) - (33 / 2), (hig / 2) - 3)
        write("CCVIM - ComputerCraft Vi Improved")
        setpos((wid / 2) - (#("version ".. version) / 2), (hig / 2) - 1)
        write("version "..version)
        setpos((wid / 2) - (13 / 2), (hig / 2))
        write("By Minater247")
        if wid > 53 then
            setpos((wid / 2) - (46 / 2), (hig / 2) + 1)
            write("CCVIM is open source and freely distributable.")
            setpos((wid / 2) - (28 / 2), (hig / 2) + 4)
        else
            setpos((wid / 2) - (28 / 2), (hig / 2) + 3)
        end
        write("Type :q")
        setcolors(colors.black, colors.lightBlue)
        write("<Enter>       ")
        setcolors(colors.black, colors.white)
        write("to exit")

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
    else
        drawFile()
    end
    while currCursorX + lineoffset > wid do
        currCursorX = currCursorX - 1
        currXOffset = currXOffset + 1
    end
    while currCursorX < 1 do
        currCursorX = currCursorX + 1
        currXOffset = currXOffset - 1
    end
    while currCursorY > hig - 1 do
        currCursorY = currCursorY - 1
        currFileOffset = currFileOffset + 1
    end
    while currCursorY < 1 do
        currCursorY = currCursorY + 1
        currFileOffset = currFileOffset - 1
    end
end


local function insertMode()
    drawFile()
    sendMsg("-- INSERT --")
    local ev, key
    while key ~= keys.tab do
        ev, key = pullEventWRMP()
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
                    fileContents[currfile]["unsavedchanges"] = true
                else
                    if currCursorX + currXOffset < 2 then
                        if #filelines > 1 then
                            currCursorX = #(filelines[currCursorY + currFileOffset - 1]) + 1
                            filelines[currCursorY + currFileOffset - 1] = filelines[currCursorY + currFileOffset - 1] .. filelines[currCursorY + currFileOffset]
                            table.remove(filelines, currCursorY + currFileOffset)
                            moveCursorUp()
                            if currCursorX + lineoffset > wid then
                                while currCursorX + lineoffset > wid do
                                    currXOffset = currXOffset + 1
                                    currCursorX = currCursorX - 1
                                end
                            end
                            drawFile()
                            fileContents[currfile]["unsavedchanges"] = true
                        end
                    else
                        filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 2) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #(filelines[currCursorY + currFileOffset]))
                        currXOffset = currXOffset - math.floor(wid / 2)
                        currCursorX = currCursorX + math.floor(wid / 2) - 1
                        if currXOffset < 0 then
                            currCursorX = currXOffset + currCursorX
                            currXOffset = 0
                        end
                        drawFile()
                        fileContents[currfile]["unsavedchanges"] = true
                    end
                end
            elseif key == keys.enter then
                if filelines[currCursorY + currFileOffset] ~= nil then
                    table.insert(filelines, currCursorY + currFileOffset + 1, string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #(filelines[currCursorY + currFileOffset])))
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
                    moveCursorDown()
                    currCursorX = 1
                    currXOffset = 0
                    fileContents[currfile]["unsavedchanges"] = true
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
            if currCursorX + lineoffset > wid then
                currCursorX = currCursorX - 1
                currXOffset = currXOffset + 1
            end
            drawFile()
            if not fileContents[currfile] then
                fileContents[currfile] = {""}
            end
            fileContents[currfile]["unsavedchanges"] = true
        elseif ev == "term_resize" then
            resetSize()
            redrawTerm()
            sendMsg("-- INSERT --")
        elseif ev == "mouse_click" and mobile then
            key = keys.tab --get out of the loop
        end
    end
    sendMsg(" ")
end

local function appendMode()
    drawFile()
    sendMsg("-- APPEND --")
    local ev, key
    while key ~= keys.tab do
        ev, key = pullEventWRMP()
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
                    fileContents[currfile]["unsavedchanges"] = true
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
                        fileContents[currfile]["unsavedchanges"] = true
                    end
                end
            elseif key == keys.enter then
                if filelines[currCursorY + currFileOffset] ~= nil then
                    table.insert(filelines, currCursorY + currFileOffset + 1, string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset])))
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset)
                    moveCursorDown()
                    currCursorX = 1
                    currXOffset = 0
                    fileContents[currfile]["unsavedchanges"] = true
                else
                    table.insert(filelines, currCursorY + currFileOffset + 1, "")
                end
                drawFile()
            end
        elseif ev == "char" then
            if filelines[currCursorY + currFileOffset] == nil then
                filelines[currCursorY + currFileOffset] = ""
            end
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset) .. key ..string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 2, #(filelines[currCursorY + currFileOffset]))
            moveCursorRight(0)
            drawFile()
            if not fileContents[currfile] then
                fileContents[currfile] = filelines
            end
            fileContents[currfile]["unsavedchanges"] = true
        elseif ev == "term_resize" then
            resetSize()
            redrawTerm()
            sendMsg("-- APPEND --")
        elseif ev == "mouse_click" and mobile then
            key = keys.tab --get out of the loop
        end
    end
    sendMsg(" ")
end

--Parse .vimrc file here
if fs.exists("/vim/.vimrc") then
    local vimrclines = fil.toArr("/vim/.vimrc")
    for i=1,#vimrclines,1 do
        if not (string.sub(vimrclines[i], 1, 1) == "\"") then --ignore commented lines
            local rctable = str.split(vimrclines[i], " ")
            if rctable[1] == "set" then
                if not string.find(rctable[2], "=") then
                    if rctable[2] == "mobile" then
                        mobile = true
                    elseif rctable[2] == "number" then
                        linenumbers = true
                        lineoffset = 4
                    elseif rctable[2] == "filetype" then
                        filetypes = true
                    elseif rctable[2] == "syntax" then
                        syntaxhighlighting = true
                    end
                else
                    --set the things to values
                end
            elseif rctable[1] == "map" then
                if rctable[2] and rctable[3] or not (#rctable > 3) then
                    remappings[rctable[2]] = rctable[3]
                else
                    print("Mapping requires 2 arguments.")
                    sendMsg("Press enter to continue...")
                    local _,k = os.pullEvent("key")
                    while k ~= keys.enter do
                        _,k = os.pullEvent("key")
                    end
                end
            elseif rctable[1] ~= "" and rctable[1] ~= nil then
                error("Unrecognized vimrc command " .. rctable[1] .. ". Full vimscript is not yet supported.")
            end
        end
    end
end

local function pullChar()
    local _, tm = os.pullEvent("char")
    if remappings[tm] then
        tm = remappings[tm]
    end
    return _, tm
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
            local doneGettingEnd = false
            local filenamestring = ""
            for j=#decargs["files"][i],1,-1 do
                if string.sub(decargs["files"][i], j, j) ~= "." and not doneGettingEnd then
                    filenamestring = string.sub(decargs["files"][i], j, j) .. filenamestring
                else
                    doneGettingEnd = true
                end
            end
            filelines = fil.toArr(fil.topath(decargs["files"][i]))
            fileContents[i] = fil.toArr(fil.topath(decargs["files"][i]))
            if filetypes then
                if filenamestring ~= decargs["files"][i] and filenamestring ~= string.sub(decargs["files"][i], 2, #decargs["files"][i]) then
                    fileContents[i]["filetype"] = filenamestring
                    if fs.exists("/vim/syntax/"..filenamestring..".lua") then
                        filetypearr[filenamestring] = require("/vim/syntax/"..filenamestring)
                    else
                        fileContents[i]["filetype"] = nil
                    end
                else
                    fileContents[i]["filetype"] = nil
                end
            end
        else
            table.insert(openfiles, #openfiles + 1, decargs["files"][1])
            table.insert(fileContents, #fileContents + 1, {""})
            newfile = true
        end
        filelines = fileContents[1]
    end
    filename = decargs["files"][1]
    if filelines[1] ~= nil then
        local tb = str.wordBeginnings(filelines[1])
        if tb[1] then
            currCursorX = tb[1]
        else
            currCursorX = 1
        end
        while currCursorX + lineoffset > wid do
            currCursorX = currCursorX - 1
            currXOffset = currXOffset + 1
        end
    end
else
    openfiles = {}
    filelines = {""}
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
    --MOTD
    motd = true
    setcolors(colors.black, colors.white)
    setpos((wid / 2) - (33 / 2), (hig / 2) - 3)
    write("CCVIM - ComputerCraft Vi Improved")
    setpos((wid / 2) - (#("version ".. version) / 2), (hig / 2) - 1)
    write("version "..version)
    setpos((wid / 2) - (13 / 2), (hig / 2))
    write("By Minater247")
    if wid > 53 then
        setpos((wid / 2) - (46 / 2), (hig / 2) + 1)
        write("CCVIM is open source and freely distributable.")
        setpos((wid / 2) - (28 / 2), (hig / 2) + 4)
    else
        setpos((wid / 2) - (28 / 2), (hig / 2) + 3)
    end
    write("Type :q")
    setcolors(colors.black, colors.lightBlue)
    write("<Enter>       ")
    setcolors(colors.black, colors.white)
    write("to exit")

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
    local event, var1, var2, var3 = pullEventWRMP()
    resetSize()
    if event == "char" then
        if var1 == ";" then
            print(fileContents[currfile]["filetype"])
        end
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
                    fileContents[currfile]["unsavedchanges"] = false
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
                    fileContents[currfile]["unsavedchanges"] = false
                    sendMsg("\""..name.."\" ")
                    if new then
                        write("[New]  ")
                    else
                        write(" ")
                    end
                    write(#filelines.."L written")
                end
            elseif cmdtab[1] == ":q" or cmdtab[1] == ":q!" then
                if not fileContents[currfile] then
                    fileContents[currfile] = {""}
                end
                if fileContents[currfile]["unsavedchanges"] and cmdtab[1] ~= ":q!" then
                    err("No write since last change (add ! to override)")
                else
                    if #fileContents <= 1 then
                        setcolors(colors.black, colors.white)
                        clear()
                        setpos(1, 1)
                        running = false
                    else
                        table.remove(fileContents, currfile)
                        table.remove(openfiles, currfile)
                        if not (currfile == 1) then
                            currfile = currfile - 1
                        end
                        filelines = fileContents[currfile]
                        if fileContents[currfile] then
                            if fileContents[currfile]["cursor"] then
                                currCursorX = fileContents[currfile]["cursor"][1]
                                currXOffset = fileContents[currfile]["cursor"][2]
                                currCursorY = fileContents[currfile]["cursor"][3]
                                currFileOffset = fileContents[currfile]["cursor"][4]
                            end
                        end
                        drawFile()
                        clearScreenLine(hig)
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                    end
                end
            elseif cmdtab[1] == ":wq" or cmdtab[1] == ":x" then
                if cmdtab[2] == nil and openfiles[currfile] == "" then
                    err("No file name")
                else
                    local name = ""
                    sendMsg(#openfiles .. " " .. currfile)
                    if openfiles[currfile] == "" then
                        for i=2,#cmdtab,1 do
                            name = name .. cmdtab[i]
                            if i ~= #cmdtab then
                                name = name .. " "
                            end
                        end
                    else
                        name = openfiles[currfile]
                    end
                    if name then
                        local file = fs.open(fil.topath(name), "w")
                        for i=1,#filelines,1 do
                            file.writeLine(filelines[i])
                        end
                        file.close()
                        fileContents[currfile]["unsavedchanges"] = false
                        if #fileContents == 1 then
                            setcolors(colors.black, colors.white)
                            clear()
                            setpos(1, 1)
                            running = false
                        else
                            table.remove(fileContents, currfile)
                            table.remove(openfiles, currfile)
                            if not (currfile == 1) then
                                currfile = currfile - 1
                            end
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
                    else
                        err("No file name")
                    end
                end
            elseif cmdtab[1] == ":e" or cmdtab[1] == ":ex" then
                if #cmdtab > 1 then
                    if not motd then
                        if currfile == 0 then
                            currfile = 1
                        end
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        if not openfiles[currfile] then
                            openfiles[currfile] = ""
                        end
                    end
                    local name = ""
                    for i=2,#cmdtab,1 do
                        name = name .. cmdtab[i]
                        if i ~= #cmdtab then
                            name = name .. " "
                        end
                    end
                    if name then
                        filename = name
                    else
                        filename = ""
                    end
                    table.insert(openfiles, #openfiles + 1, filename)
                    if currfile == 0 then
                        currfile = 1
                    end
                    sendMsg(#openfiles.." "..currfile) --will immediately be overwritten if nothing goes wrong, used for debug
                    if fs.exists(fil.topath(name)) then
                        filelines = fil.toArr(fil.topath(name))
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                    else
                        newfile = true
                        sendMsg("\""..filename.."\" [New File]")
                    end
                    table.insert(fileContents, #fileContents + 1, fil.toArr(fil.topath(filename)))
                    if not fileContents[#fileContents] then
                        fileContents[#fileContents] = {""}
                    end
                    currfile = #fileContents
                    filelines = fileContents[currfile]
                    currFileOffset = 0
                    if filelines[1] ~= nil then
                        local tb = str.wordBeginnings(filelines[1])
                        if tb[1] then
                            currCursorX = tb[1]
                        else
                            currCursorX = 0
                        end
                        while currCursorX + lineoffset > wid do
                            currCursorX = currCursorX - 1
                            currXOffset = currXOffset + 1
                        end
                    end
                    local doneGettingEnd = false
                    local filenamestring = ""
                    for j=#openfiles[currfile],1,-1 do
                        if string.sub(openfiles[currfile], j, j) ~= "." and not doneGettingEnd then
                            filenamestring = string.sub(openfiles[currfile], j, j) .. filenamestring
                        else
                            doneGettingEnd = true
                        end
                    end
                    fileContents[currfile]["filetype"] = filenamestring
                    drawFile()
                else
                    err("No file name")
                end
            elseif cmdtab[1] == ":r" or cmdtab[1] == ":read" then
                if #cmdtab > 1 then
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
                else
                    err("No file name")
                end
            elseif cmdtab[1] == ":tabn" or cmdtab[1] == ":tabnext" then
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                    end
                    filename = openfiles[currfile]
                end
            elseif cmdtab[1] == ":tabm" or cmdtab[1] == ":tabmove" then
                fileContents[currfile] = filelines
                fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                local tmp = tonumber(cmdtab[2])
                if tonumber(cmdtab[2]) >= 0 and tonumber(cmdtab[2]) <= #fileContents - 1 then
                    currfile = tonumber(cmdtab[2]) + 1
                    filelines = fileContents[currfile]
                    if fileContents[currfile]["cursor"] then
                        currCursorX = fileContents[currfile]["cursor"][1]
                        currXOffset = fileContents[currfile]["cursor"][2]
                        currCursorY = fileContents[currfile]["cursor"][3]
                        currFileOffset = fileContents[currfile]["cursor"][4]
                    end
                    drawFile()
                    sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                end
                clearScreenLine(hig)
            elseif cmdtab[1] == ":tabo" or cmdtab[1] == ":tabonly" or cmdtab[1] == ":tabo!" or cmdtab[1] == ":tabonly!" then
                local closable = true
                local unclosablename = ""
                local unclosablenum = -1
                for i=1,#fileContents,1 do
                    if fileContents[i]["unsavedchanges"] and not (i == currfile) and cmdtab[1] ~= ":tabo!" and cmdtab[1] ~= ":tabonly!" then
                        closable = false
                        unclosablename = openfiles[i]
                        unclosablenum = i
                    end
                end
                if not closable then
                    err("Unsaved work in \""..unclosablename.."\" (add ! to override)")
                else
                    fileContents = {fileContents[currfile]}
                    openfiles = {openfiles[currfile]}
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
                    sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                end
            elseif cmdtab[1] == ":tabnew" then
                if not cmdtab[2] then
                    cmdtab[2] = 1
                end
                if tonumber(cmdtab[2]) ~= nil then
                    for i=1,tonumber(cmdtab[2]),1 do
                        table.insert(fileContents, currfile + 1, {""})
                        table.insert(openfiles, currfile + 1, "")
                    end
                    sendMsg("added "..tonumber(cmdtab[2]).." new tab")
                    if tonumber(cmdtab[2]) > 1 then
                        write("s")
                    end
                    fileContents[currfile] = filelines
                    fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                    currfile = currfile + 1
                    filelines = fileContents[currfile]
                    sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                    currCursorX = 1
                    currXOffset = 0
                    currCursorY = 1
                    currFileOffset = 0
                    drawFile()
                else
                    if cmdtab[2] then
                        local name = ""
                        for i=2,#cmdtab,1 do
                            name = name .. cmdtab[i]
                            if i ~= #cmdtab then
                                name = name .. " "
                            end
                        end
                        if fs.exists(fil.topath(name)) then
                            fileContents[currfile] = filelines
                            fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                            table.insert(fileContents, currfile + 1, fil.toArr(fil.topath(name)))
                            table.insert(openfiles, currfile + 1, name)
                            currfile = currfile + 1
                            filelines = fileContents[currfile]
                            sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                            currCursorX = 1
                            currXOffset = 0
                            currCursorY = 1
                            currFileOffset = 0
                            local tb = str.wordBeginnings(filelines[1])
                            if tb[1] then
                                currCursorX = tb[1]
                            else
                                currCursorX = 0
                            end
                            while currCursorX + lineoffset > wid do
                                currCursorX = currCursorX - 1
                                currXOffset = currXOffset + 1
                            end
                            drawFile()
                        else
                            local templines = fil.toArr(fil.topath(name))
                            if templines then
                                table.insert(fileContents, currfile + 1, templines)
                            else
                                table.insert(fileContents, currfile + 1, {""})
                            end
                            table.insert(openfiles, currfile + 1, name)
                            fileContents[currfile] = filelines
                            fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                            currfile = currfile + 1
                            filelines = fileContents[currfile]
                            sendMsg("\""..openfiles[currfile].."\"  [New File] "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                            currCursorX = 1
                            currXOffset = 0
                            currCursorY = 1
                            currFileOffset = 0
                            drawFile()
                        end
                    else
                        --just add an empty tab
                        table.insert(fileContents, currfile + 1, {""})
                        table.insert(openfiles, currfile + 1, "")
                        fileContents[currfile] = filelines
                        fileContents[currfile]["cursor"] = {currCursorX, currXOffset, currCursorY, currFileOffset}
                        currfile = currfile + 1
                        filelines = fileContents[currfile]
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                        currCursorX = 1
                        currXOffset = 0
                        currCursorY = 1
                        currFileOffset = 0
                        drawFile()
                    end
                end
                local doneGettingEnd = false
                local filenamestring = ""
                for j=#openfiles[currfile],1,-1 do
                    if string.sub(openfiles[currfile], j, j) ~= "." and not doneGettingEnd then
                        filenamestring = string.sub(openfiles[currfile], j, j) .. filenamestring
                    else
                        doneGettingEnd = true
                    end
                end
                fileContents[currfile]["filetype"] = filenamestring
            elseif cmdtab[1] == ":tabc" or cmdtab[1] == ":tabclose" or cmdtab[1] == ":tabc!" or cmdtab[1] == ":tabclose!" then
                if fileContents[currfile]["unsavedchanges"] and cmdtab[1] ~= ":tabc!" and cmdtab[1] ~= ":tabclose!" then
                    err("No write since last change (add ! to override)")
                else
                    if #fileContents == 1 then
                        setcolors(colors.black, colors.white)
                        clear()
                        setpos(1, 1)
                        running = false
                    else
                        table.remove(fileContents, currfile)
                        table.remove(openfiles, currfile)
                        if not (currfile == 1) then
                            currfile = currfile - 1
                        end
                        filelines = fileContents[currfile]
                        if fileContents[currfile]["cursor"] then
                            currCursorX = fileContents[currfile]["cursor"][1]
                            currXOffset = fileContents[currfile]["cursor"][2]
                            currCursorY = fileContents[currfile]["cursor"][3]
                            currFileOffset = fileContents[currfile]["cursor"][4]
                        end
                        drawFile()
                        clearScreenLine(hig)
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                    end
                end
            elseif cmdtab[1] == ":set" then
                local seterror = false
                if cmdtab[2] == "number" then
                    linenumbers = true
                    lineoffset= 4
                    drawFile()
                elseif cmdtab[2] == "mobile" then
                    mobile = true
                elseif cmdtab[2] == "nonumber" then
                    linenumbers = false
                    lineoffset = 0
                    drawFile()
                elseif cmdtab[2] == "nomobile" then
                    mobile = false
                else
                    err("Variable " .. cmdtab[2] .. " not supported.")
                    seterror = true
                end
                if not seterror then
                    clearScreenLine(hig)
                end
            elseif cmdtab[1] ~= "" then
                err("Not an editor command or unimplemented: "..cmdtab[1])
            end
        elseif var1 == "i"then
            insertMode()
        elseif var1 == "I" then
            currXOffset = 0
            currCursorX = 1
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
            local _, chr = pullChar()
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. chr .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset]))
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
        elseif var1 == "J" then
            filelines[currCursorY + currFileOffset] = filelines[currCursorY + currFileOffset] .. " " .. filelines[currCursorY + currFileOffset + 1]
            table.remove(filelines, currCursorY + currFileOffset + 1)
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
        elseif var1 == "o" then
            table.insert(filelines, currCursorY + currFileOffset + 1, "")
            moveCursorDown()
            currCursorX = 1
            currXOffset = 0
            drawFile()
            insertMode()
            fileContents[currfile]["unsavedchanges"] = true
        elseif var1 == "O" then
            table.insert(filelines, currCursorY + currFileOffset, "")
            currCursorX = 1
            currXOffset = 0
            drawFile()
            insertMode()
            fileContents[currfile]["unsavedchanges"] = true
        elseif var1 == "a" then
            appendMode()
        elseif var1 == "A" then
            currCursorX = #filelines[currCursorY + currFileOffset]
            currXOffset = 0
            while currCursorX + lineoffset > wid do
                currXOffset = currXOffset + 1
                currCursorX = currCursorX - 1
            end
            drawFile()
            appendMode()
        elseif var1 == "Z" then
            local _,c = pullChar()
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
                    fileContents[currfile]["unsavedchanges"] = false
                    setcolors(colors.black, colors.white)
                    clear()
                    setpos(1, 1)
                    running = false
                end
            end
        elseif var1 == "y" then
            local _, c = pullChar()
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
                local _, ch = pullChar()
                if ch == "w" then
                    local word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                    copybuffer = word
                    copytype = "text"
                end
            elseif c == "a" then
                local _, ch = pullChar()
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
            fileContents[currfile]["unsavedchanges"] = true
        elseif var1 == "d" then
            local _, c = pullChar()
            if c == "d" then
                copybuffer = filelines[currCursorY + currFileOffset]
                copytype = "line"
                table.remove(filelines, currCursorY + currFileOffset)
                fileContents[currfile]["unsavedchanges"] = true
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
                currCursorX = beg - 1
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, beg - 1) .. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                fileContents[currfile]["unsavedchanges"] = true
            elseif c == "i" then
                local _, ch = pullChar()
                local word,beg,ed
                if ch == "w" then
                    word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                    copybuffer = word
                    copytype = "text"
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, beg - 1) .. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                    fileContents[currfile]["unsavedchanges"] = true
                    currCursorX = beg - 1
                end
            elseif c == "a" then
                local _, ch = pullChar()
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
                    currCursorX = beg - 1
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, beg - 1) .. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                    fileContents[currfile]["unsavedchanges"] = true
                end
            elseif c == "$" then
                copybuffer = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #filelines[currCursorY + currFileOffset])
                copytype = "text"
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
                fileContents[currfile]["unsavedchanges"] = true
            end
            while currCursorX + currXOffset > #filelines[currCursorY + currFileOffset] do
                currCursorX = currCursorX - 1
                if currCursorX < 1 then
                    currXOffset = currXOffset - 1
                    currCursorX = currCursorX + 1
                end
            end
            drawFile()
        elseif var1 == "D" then
            copybuffer = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #filelines[currCursorY + currFileOffset])
            copytype = "text"
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
        elseif var1 == "p" then
            if copytype == "line" then
                table.insert(filelines, currCursorY + currFileOffset + 1, copybuffer)
            elseif copytype == "text" then
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset) .. copybuffer .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #filelines[currCursorY + currFileOffset])
                currCursorX = currCursorX + #copybuffer --minus one so we can have the function reset viewpoint
                while currCursorX + lineoffset > wid do
                    currCursorX = currCursorX - 1
                    currXOffset = currXOffset + 1
                end
            elseif copytype == "linetable" then
                for i=#copybuffer,1,-1 do
                    table.insert(filelines, currCursorY + currFileOffset + 1, copybuffer[i])
                end
            end
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
        elseif var1 == "P" then
            if copytype == "line" then
                table.insert(filelines, currCursorY + currFileOffset, copybuffer)
            elseif copytype == "text" then
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. copybuffer .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #filelines[currCursorY + currFileOffset])
                currCursorX = currCursorX + #copybuffer
                while currCursorX + lineoffset > wid do
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
            fileContents[currfile]["unsavedchanges"] = true
        elseif var1 == "$" then
            currCursorX = #filelines[currCursorY + currFileOffset]
            while currCursorX + lineoffset > wid do
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
                _, var = pullChar()
                if tonumber(var) ~= nil then
                    num = num .. var
                else
                    ch = var
                end
            end
            if ch == "y" then
                _, ch = pullChar()
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
                _, ch = pullChar()
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
                        fileContents[currfile]["unsavedchanges"] = true
                    end
                end
            elseif ch == "g" then
                _, ch = pullChar()
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                    end
                elseif ch == "e" or ch == "E" then
                    for i=1,tonumber(num),1 do
                        local begs = str.wordEnds(filelines[currCursorY + currFileOffset], not string.match(ch, "%u"))
                        if currCursorX + currXOffset > begs[1] then
                            currCursorX = currCursorX - 1
                            while not tab.find(begs, currCursorX + currXOffset) do
                                currCursorX = currCursorX - 1
                            end
                            while currCursorX + lineoffset > wid do
                                currCursorX = currCursorX + 1
                                currXOffset = currXOffset - 1
                            end
                        end
                    end
                    drawFile()
                end
            elseif ch == "G" then
                currCursorY = tonumber(num) - 1 --minus one for moveCursorDown
                currFileOffset = 0
                currCursorX = 1
                currXOffset = 0
                while currCursorY > hig - 1 do
                    currCursorY = currCursorY - 1
                    currFileOffset = currFileOffset + 1
                end
                drawFile()
            elseif ch == "h" then
                currCursorX = currCursorX - tonumber(num) + 1
                if currCursorX + currXOffset < 1 then
                    currCursorX = 1
                    currXOffset = 0
                else
                    while currCursorX < 1 do
                        currCursorX = currCursorX + 1
                        currXOffset = currXOffset - 1
                    end
                end
                drawFile()
            elseif ch == "l" then
                currCursorX = currCursorX + tonumber(num)
                if currCursorX + currXOffset > #filelines[currCursorY + currFileOffset] then
                    currXOffset = 0
                    currCursorX = #filelines[currCursorY + currFileOffset] + 1
                end
                while currCursorX + lineoffset > wid do
                    currCursorX = currCursorX - 1
                    currXOffset = currXOffset + 1
                end
                drawFile()
            elseif ch == "j" then
                currCursorY = currCursorY + tonumber(num)
                if currCursorY + currFileOffset > #filelines then
                    currCursorY = #filelines
                    currFileOffset = 0
                end
                while currCursorY > hig - 1 do
                    currCursorY = currCursorY - 1
                    currFileOffset = currFileOffset + 1
                end
                drawFile()
            elseif ch == "k" then
                currCursorY = currCursorY - tonumber(num)
                if currCursorY + currFileOffset < 1 then
                    currCursorY = 1
                    currFileOffset = 0
                end
                while currCursorY < 1 do
                    currCursorY = currCursorY + 1
                    currFileOffset = currFileOffset - 1
                end
                drawFile()
            elseif ch == "w" or ch == "W" then
                for i=1,tonumber(num),1 do
                    local begs = str.wordBeginnings(filelines[currCursorY + currFileOffset], not string.match(ch, "%u"))
                    if currCursorX + currXOffset < begs[#begs] then
                        currCursorX = currCursorX + 1
                        while not tab.find(begs, currCursorX + currXOffset) do
                            currCursorX = currCursorX + 1
                        end
                        while currCursorX + lineoffset > wid do
                            currCursorX = currCursorX - 1
                            currXOffset = currXOffset + 1
                        end
                        oldx = currCursorX + currXOffset
                        drawFile()
                    end
                end
            elseif ch == "e" or ch == "E" then
                for i=1,tonumber(num),1 do
                    local begs = str.wordEnds(filelines[currCursorY + currFileOffset], not string.match(ch, "%u"))
                    if currCursorX + currXOffset < begs[#begs] then
                        currCursorX = currCursorX + 1
                        while not tab.find(begs, currCursorX + currXOffset) do
                            currCursorX = currCursorX + 1
                        end
                        while currCursorX + lineoffset > wid do
                            currCursorX = currCursorX - 1
                            currXOffset = currXOffset + 1
                        end
                        drawFile()
                    end
                end
            elseif ch == "b" or ch == "B" then
                for i=1,tonumber(num),1 do
                    local begs = str.wordBeginnings(filelines[currCursorY + currFileOffset], not string.match(ch, "%u"))
                    if currCursorX + currXOffset > begs[1] then
                        currCursorX = currCursorX - 1
                        while not tab.find(begs, currCursorX + currXOffset) do
                            currCursorX = currCursorX - 1
                        end
                        while currCursorX < 1 do
                            currCursorX = currCursorX + 1
                            currXOffset = currXOffset - 1
                        end
                        drawFile()
                    end
                end
            elseif ch == "f" or ch == "t" then
                local _,c = pullChar()
                local idx = str.indicesOfLetter(filelines[currCursorY + currFileOffset], c)
                for i=1,tonumber(num),1 do
                    if #idx > 0 then
                        if currCursorX + currFileOffset < idx[#idx] - jumpoffset then
                            local oldcursor = currCursorX
                            currCursorX = currCursorX + (1 + jumpoffset)
                            while not tab.find(idx, currCursorX + currXOffset) and not (currCursorX + currXOffset >= #filelines[currCursorY + currFileOffset]) do
                                currCursorX = currCursorX + 1
                            end
                            if not tab.find(idx, currCursorX + currXOffset) then
                                currCursorX = oldcursor
                            end
                            if ch == "t" then
                                currCursorX = currCursorX - 1
                            end
                            while currCursorX + lineoffset > wid do
                                currCursorX = currCursorX - 1
                                currXOffset = currXOffset + 1
                            end
                            jumpbuffer = {c, ch}
                            if ch == "t" then
                                jumpoffset = 1
                            else
                                jumpoffset = 0
                            end
                        end
                    end
                end
                drawFile()
            elseif ch == "F" or ch == "T" then
                local _,c = pullChar()
                local idx = str.indicesOfLetter(filelines[currCursorY + currFileOffset], c)
                if #idx > 0 then
                    if currCursorX + currFileOffset > idx[1] + jumpoffset then
                        currCursorX = currCursorX - (1 + jumpoffset)
                        while not tab.find(idx, currCursorX + currXOffset) and currCursorX > 1 do
                            currCursorX = currCursorX - 1
                        end
                        if ch == "T" then
                            currCursorX = currCursorX + 1
                        end
                        while currCursorX < 1 do
                            currCursorX = currCursorX + 1
                            currXOffset = currXOffset - 1
                        end
                        drawFile()
                        jumpbuffer = {c, ch}
                        if ch == "T" then
                            jumpoffset = 1
                        else
                            jumpoffset = 0
                        end
                    end
                end
            end
        elseif var1 == "g" then
            local _,c = pullChar()
            if c == "J" then
                filelines[currCursorY + currFileOffset] = filelines[currCursorY + currFileOffset] .. filelines[currCursorY + currFileOffset + 1]
                table.remove(filelines, currCursorY + currFileOffset + 1)
                drawFile()
                fileContents[currfile]["unsavedchanges"] = true
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
                    while currCursorX + lineoffset > wid do
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
                if currCursorX + lineoffset > wid then
                    while currCursorX + lineoffset > wid do
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
            if begs then
                if currCursorX + currXOffset < begs[#begs] then
                    currCursorX = currCursorX + 1
                    while not tab.find(begs, currCursorX + currXOffset) do
                        currCursorX = currCursorX + 1
                    end
                    while currCursorX + lineoffset > wid do
                        currCursorX = currCursorX - 1
                        currXOffset = currXOffset + 1
                    end
                    oldx = currCursorX + currXOffset
                    drawFile()
                end
            end
        elseif var1 == "e" or var1 == "E" then
            local begs = str.wordEnds(filelines[currCursorY + currFileOffset], not string.match(var1, "%u"))
            if begs then
                if currCursorX + currXOffset < begs[#begs] then
                    currCursorX = currCursorX + 1
                    while not tab.find(begs, currCursorX + currXOffset) do
                        currCursorX = currCursorX + 1
                    end
                    while currCursorX + lineoffset > wid do
                        currCursorX = currCursorX - 1
                        currXOffset = currXOffset + 1
                    end
                    drawFile()
                end
            end
        elseif var1 == "b" or var1 == "B" then
            local begs = str.wordBeginnings(filelines[currCursorY + currFileOffset], not string.match(var1, "%u"))
            if currCursorX + currXOffset > begs[1] then
                currCursorX = currCursorX - 1
                while not tab.find(begs, currCursorX + currXOffset) do
                    currCursorX = currCursorX - 1
                end
                while currCursorX < 1 do
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
            while currCursorX + lineoffset > wid do
                currCursorX = currCursorX - 1
                currXOffset = currXOffset + 1
            end
            drawFile()
        elseif var1 == "f" or var1 == "t" then
            local _,c = pullChar()
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
                    while currCursorX + lineoffset > wid do
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
            local _,c = pullChar()
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
            if jumpbuffer[1] then
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
                            while currCursorX + lineoffset > wid do
                                currCursorX = currCursorX - 1
                                currXOffset = currXOffset + 1
                            end
                            drawFile()
                        end
                    end
                end
            end
        elseif var1 == "c" then
            local _, c = pullChar()
            if c == "c" then
                filelines[currCursorY + currFileOffset] = ""
                currCursorX = 1
                currXOffset = 0
                drawFile()
                fileContents[currfile]["unsavedchanges"] = true
                insertMode()
            elseif c == "$" then
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
                drawFile()
                fileContents[currfile]["unsavedchanges"] = true
                insertMode()
            elseif c == "i" then
                local _, ch = pullChar()
                if ch == "w" then
                    local word,beg,ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                    filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, beg - 1) .. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                    currCursorX = beg
                    currXOffset = 0
                    while currCursorX + lineoffset > wid do
                        currCursorX = currCursorX - 1
                        currXOffset = currXOffset + 1
                    end
                    drawFile()
                    fileContents[currfile]["unsavedchanges"] = true
                    insertMode()
                end
            elseif c == "w" or c == "e" then
                local word, beg, ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1).. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                drawFile()
                fileContents[currfile]["unsavedchanges"] = true
                insertMode()
            end
        elseif var1 == "C" then
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
            insertMode()
        elseif var1 == "s" then
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #filelines[currCursorY + currFileOffset])
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
            insertMode()
        elseif var1 == "S" then
            filelines[currCursorY + currFileOffset] = ""
            currCursorX = 1
            currXOffset = 0
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
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
    elseif event == "term_resize" then
        resetSize()
        redrawTerm()
    end
end