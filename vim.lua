local args = {...}

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

local version = 0.5
local releasedate = "2021-10-07"

local fileEditorVer = 0.11

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
local jumpoffset = 0 --offset for t/T jumping before/after a letter
local currfile = 1
local fileContents = {}
local motd = false
local remappings = {}
local filetypearr = {}
local mobile = false
local linenumbers = false
local lineoffset = 0
local syntaxhighlighting = false
local oldXOffset = 0
local oldFileOffset = 0
local lowspec = false

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

local function drawFile(forcedredraw)
    motd = false
    local length = #(tostring(currCursorY + currFileOffset + hig - 1))
    if currXOffset ~= oldXOffset or currFileOffset ~= oldFileOffset or forcedredraw then
        for i=1,hig-1,1 do
            clearScreenLine(i)
        end
        oldXOffset = currXOffset
        oldFileOffset = currFileOffset
        for i=currFileOffset,(hig - 1) + currFileOffset,1 do
            setpos(1, i - currFileOffset)
            if filelines then
                if filelines[i] ~= nil then
                    setcolors(colors.black, colors.white)
                    if fileContents[currfile] then
                        if fileContents[currfile]["filetype"] and syntaxhighlighting and filetypearr[fileContents[currfile]["filetype"]] then
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
                            commentstart = str.find(filelines[i], synt[7][2])
                            if not commentstart then
                                commentstart = 0
                            end
                            if not lowspec then
                                if tab.find(fileContents[currfile]["Multi-line comments"][2], i) then
                                    setpos(1 - currXOffset + lineoffset, i - currFileOffset)
                                    setcolors(colors.black, colors.green)
                                    write(filelines[i])
                                elseif tab.find(fileContents[currfile]["Multi-line comments"][3], i) then
                                    setpos(1 - currXOffset + lineoffset, i - currFileOffset)
                                    setcolors(colors.black, colors.green)
                                    write(string.sub(filelines[i], 1, commentstart + 1))
                                end
                            end
                        else
                            setpos(1 - currXOffset + lineoffset, i - currFileOffset)
                            write(string.sub(filelines[i], currXOffset + 1, #filelines[i]))
                        end
                    end
                else
                    setcolors(colors.black, colors.purple)
                    write("~")
                end
            end
        end
    else
        --only draw 3 lines
        for i=currCursorY + currFileOffset - 1, currCursorY + currFileOffset + 2, 1 do
            if i - currFileOffset < hig then
                clearScreenLine(i - currFileOffset)
                setpos(1, i - currFileOffset)
                if filelines then
                    if filelines[i] ~= nil then
                        setcolors(colors.black, colors.white)
                        if fileContents[currfile] then
                            if fileContents[currfile]["filetype"] and syntaxhighlighting and filetypearr[fileContents[currfile]["filetype"]] then
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
                                        table.insert(quotepoints, #quotepoints, j - 2)
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
                                commentstart = str.find(filelines[i], synt[7][2])
                                if not commentstart then
                                    commentstart = 0
                                end
                                if not lowspec then
                                    if tab.find(fileContents[currfile]["Multi-line comments"][2], i) then
                                        setpos(1 - currXOffset + lineoffset, i - currFileOffset)
                                        setcolors(colors.black, colors.green)
                                        write(filelines[i])
                                    elseif tab.find(fileContents[currfile]["Multi-line comments"][3], i) then
                                        setpos(1 - currXOffset + lineoffset, i - currFileOffset)
                                        setcolors(colors.black, colors.green)
                                        write(string.sub(filelines[i], 1, commentstart + 1))
                                    end
                                end
                            else
                                setpos(1 - currXOffset + lineoffset, i - currFileOffset)
                                write(string.sub(filelines[i], currXOffset + 1, #filelines[i]))
                            end
                        end
                    else
                        setcolors(colors.black, colors.purple)
                        write("~")
                    end
                end
            end
        end
    end
    -- Draw the cursor
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
    if linenumbers then
        setcolors(colors.black, colors.yellow)
        for i=currFileOffset,(hig-1)+currFileOffset,1 do
            setpos(1, i - currFileOffset)
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
    end
end

local function moveCursorLeft()
    if currCursorX + currXOffset ~= 1 then
        currCursorX = currCursorX - 1
        if currCursorX < 1 then
            currCursorX = currCursorX + 1
            currXOffset = currXOffset - 1
            drawFile(true)
        else
            drawFile()
        end
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
                drawFile(true)
            else
                drawFile()
            end
        end
    end
    oldx = nil
end

local function moveCursorUp(ignoreX)
    if oldx ~= nil and not ignoreX then
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
        while currCursorY < 1 do
            currFileOffset = currFileOffset - 1
            currCursorY = currCursorY + 1
        end
        while currFileOffset < 0 do
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
        while currCursorY > hig - 1 do
            currFileOffset = currFileOffset + 1
            currCursorY = currCursorY - 1
        end
        drawFile()
    end
end

--Recalculate where multi-line comments are, based on position in file
local function recalcMLCs(force)
    if fileContents[currfile]["Multi-line comments"] and not lowspec then
        local synt
        if fileContents[currfile]["filetype"] then
            local tmp = require("/vim/syntax/"..fileContents[currfile]["filetype"])
            synt = tmp.syntax()
        end
        if force then
            local multilinesInFile = {{}, {}, {}} --beginning quote points, regular quote points, end quote points
            if synt then
                local quotepoints = {}
                local justset = false
                for j=1,#fileContents[currfile],1 do
                    local quotationmarks = str.indicesOfLetter(fileContents[currfile][j], synt[3])
                    local inquotes = false
                    justset = false
                    for k=1,#fileContents[currfile][j],1 do
                        if tab.find(quotationmarks, k) then
                            if not inquotes then
                                if k < quotationmarks[#quotationmarks] then
                                    inquotes = true
                                    justset = true
                                end
                            end
                        end
                        if inquotes then
                            table.insert(quotepoints, #quotepoints, k - 2)
                        end
                        if tab.find(quotationmarks, k) and not justset then
                            if inquotes then
                                inquotes = false
                            end
                        end
                        justset = false
                    end
                end
                local inmulti = false
                justset = false
                for j=1,#fileContents[currfile],1 do
                    if str.find(fileContents[currfile][j], synt[7][1], quotepoints) and not inmulti then
                        inmulti = true
                        justset = true
                        table.insert(multilinesInFile[1], #multilinesInFile[1] + 1, j)
                    end
                    if inmulti and not (str.find(fileContents[currfile][j], synt[7][2])) and not justset then
                        table.insert(multilinesInFile[2], #multilinesInFile[2] + 1, j)
                    end
                    if str.find(fileContents[currfile][j], synt[7][2]) then
                        if inmulti then
                            inmulti = false
                            table.insert(multilinesInFile[3], #multilinesInFile[3] + 1, j)
                        end
                    end
                    justset = false
                end
                fileContents[currfile]["Multi-line comments"] = multilinesInFile
                return true
            end
        elseif (tab.find(fileContents[currfile]["Multi-line comments"][3], currCursorY + currFileOffset) and not str.find(filelines[currCursorY + currFileOffset], synt[7][2])) then
            if currCursorY + currFileOffset > fileContents[currfile]["Multi-line comments"][3][1] then
                error("ok we got something")
            end
        end
        if ((tab.find(fileContents[currfile]["Multi-line comments"][1], currCursorY + currFileOffset) and not str.find(filelines[currCursorY + currFileOffset], synt[7][1])) or (not tab.find(fileContents[currfile]["Multi-line comments"][1], currCursorY + currFileOffset) and str.find(filelines[currCursorY + currFileOffset], synt[7][1])) or (not tab.find(fileContents[currfile]["Multi-line comments"][3], currCursorY + currFileOffset) and str.find(filelines[currCursorY + currFileOffset], synt[7][2])) or force) and syntaxhighlighting then
        else
            return false
        end
    else
        return false
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
        drawFile(true)
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
                    local redrawhere = recalcMLCs()
                    fileContents[currfile]["unsavedchanges"] = true
                    drawFile(redrawhere)
                else
                    if currCursorX + currXOffset < 2 then
                        if currCursorY + currFileOffset > 1 then
                            if #filelines > 1 then
                                currCursorX = #(filelines[currCursorY + currFileOffset - 1]) + 1
                                filelines[currCursorY + currFileOffset - 1] = filelines[currCursorY + currFileOffset - 1] .. filelines[currCursorY + currFileOffset]
                                table.remove(filelines, currCursorY + currFileOffset)
                                moveCursorUp(true)
                                if currCursorX + lineoffset > wid then
                                    while currCursorX + lineoffset > wid do
                                        currXOffset = currXOffset + 1
                                        currCursorX = currCursorX - 1
                                    end
                                end
                                recalcMLCs()
                                drawFile(true)
                                fileContents[currfile]["unsavedchanges"] = true
                            end
                        end
                    else
                        filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 2) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #(filelines[currCursorY + currFileOffset]))
                        currXOffset = currXOffset - math.floor(wid / 2)
                        currCursorX = currCursorX + math.floor(wid / 2) - 1
                        if currXOffset < 0 then
                            currCursorX = currXOffset + currCursorX
                            currXOffset = 0
                        end
                        local redrawhere = recalcMLCs()
                        drawFile(redrawhere)
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
                recalcMLCs()
                drawFile(true)
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
            local redrawhere = recalcMLCs()
            drawFile(redrawhere)
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
                    local redrawhere = recalcMLCs()
                    drawFile(redrawhere)
                    fileContents[currfile]["unsavedchanges"] = true
                else
                    if currCursorX + currXOffset > 1 then
                        filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 2) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #(filelines[currCursorY + currFileOffset]))
                        currXOffset = currXOffset - math.floor(wid / 2)
                        currCursorX = math.floor(wid / 2)
                        if currXOffset < 0 then
                            currCursorX = currXOffset + currCursorX + 1
                            currXOffset = 0
                        end
                        recalcMLCs()
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
                recalcMLCs()
                drawFile(true)
            end
        elseif ev == "char" then
            if filelines[currCursorY + currFileOffset] == nil then
                filelines[currCursorY + currFileOffset] = ""
            end
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset) .. key ..string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset]))
            moveCursorRight(0)
            recalcMLCs()
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
                    elseif rctable[2] == "lowperformance" then
                        lowspec = true
                    end
                else
                    --set the things to values
                end
            elseif rctable[1] == "syntax" and rctable[2] == "on" then
                syntaxhighlighting = true
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

local oldyoff
local function drawDirInfo(dir, sortType, ypos, yoff, filesInDir, initialDraw)
    if initialDraw then
        setcolors(colors.black, colors.white)
        for i=1,hig-1,1 do
            clearScreenLine(i)
        end
        setpos(1, 1)
        write("\" ")
        for i=1,wid - 4,1 do
            write("=")
        end
        setpos(1, 2)
        write("\" CCFXP Directory Listing")
        for i=1,wid-25,1 do
            write(" ")
        end
        setpos(wid-#tostring(fileEditorVer)-6, 2)
        write("ver. "..fileEditorVer)
        setpos(1, 5)
        write("\"   Quick Help: -:go up dir  D:delete  R:rename  s:sort-by")
        for i=1,wid-#("\"   Quick Help: -:go up dir  D:delete  R:rename  s:sort-by"),1 do
            write(" ")
        end
    end
    for i=1,wid-#("\"   "..shell.resolve(dir)),1 do
        write(" ")
    end
    setpos(1, 3)
    write("\"   "..shell.resolve(dir))
    if fs.isDir(shell.resolve(dir)) then
        write("/")
    end
    clearScreenLine(4)
    setpos(1, 4)
    write("\"   Sorted by    ")
    write(sortType)
    for i=1,wid-#("\"   Sorted by    "..sortType),1 do
        write(" ")
    end
    setpos(1, 6)
    setcolors(colors.black, colors.white)
    write("\" ")
    for i=1,wid - 2,1 do
        write("=")
    end
    if oldyoff ~= yoff or initialDraw then
        for i=1+yoff,hig - 7 + yoff,1 do
            clearScreenLine(6+i - yoff)
            setpos(1, 6+i - yoff)
            if i - yoff == ypos then
                setcolors(colors.lightGray, colors.white)
            else
                setcolors(colors.black, colors.white)
            end
            if 6 + i - yoff < hig then
                if filesInDir[i] then
                    write(filesInDir[i])
                    if fs.isDir(dir .. "/" .. filesInDir[i]) then
                        write("/")
                    end
                else
                    setcolors(colors.black, colors.purple)
                    write("~")
                    setcolors(colors.black, colors.white)
                end
            end
        end
        setcolors(colors.black, colors.white)
        oldyoff = yoff
    else
        for i=-1,1,1 do
            setpos(1, 6 + ypos + i)
            if i == 0 then
                setcolors(colors.lightGray, colors.white)
            else
                setcolors(colors.black, colors.white)
            end
            if 6 + ypos + i > 6 and 6 + ypos + i < hig then
                if filesInDir[ypos + yoff + i] then
                    write(filesInDir[ypos + yoff + i])
                    if fs.isDir(dir .. "/" .. filesInDir[ypos + yoff + i]) then
                        write("/")
                    end
                else
                    setcolors(colors.black, colors.purple)
                    write("~")
                    setcolors(colors.black, colors.white)
                end
            end
        end
        setcolors(colors.black, colors.white)
    end
end

-- Directory opener.
-- Make sure the path is passed through fil.path() before coming to this function.
-- Display name can be passed to inputname, but is optional.
local function dirOpener(dir, inputname)
    local currSelection = dir.."/"
    if inputname then
        sendMsg("\""..inputname.."\" is a directory")
    else
        sendMsg("\""..dir.."\" is a direcotry")
    end
    local sortType = "name"
    local currDirY = 1
    local currDirOffset = 0
    local realFilesInDir = fs.list(currSelection)
    local filesInDir = {".."}
    local firstDraw = true
    for i=1,#realFilesInDir,1 do
        table.insert(filesInDir, #filesInDir + 1, realFilesInDir[i])
    end
    if fs.isDir(dir) then
        local stillInExplorer = true
        local redrawNext = false
        local e, k
        while stillInExplorer do
            local realFilesInDir = fs.list(currSelection)
            local filesInDir = {}
            if not (shell.resolve(currSelection) == "") then
                filesInDir = {".."}
            end
            for i=1,#realFilesInDir,1 do
                table.insert(filesInDir, #filesInDir + 1, realFilesInDir[i])
            end
            if sortType == "name" then
                table.sort(filesInDir, 
                    function (k1, k2)
                        if fs.isDir(currSelection .. "/" .. k1) and not fs.isDir(currSelection .. "/" .. k2) then
                            return true
                        elseif fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                            return k1 < k2
                        elseif not fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                            return false
                        else
                            return k1 < k2
                        end
                    end)
            elseif sortType == "extension" then
                table.sort(filesInDir, 
                    function (k1, k2)
                        if fs.isDir(currSelection .. "/" .. k1) and not fs.isDir(currSelection .. "/" .. k2) then
                            return true
                        elseif fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                            return k1 < k2
                        elseif not fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                            return false
                        else
                            if str.getFileExtension(k1) == str.getFileExtension(k2) then
                                return k1 < k2
                            elseif str.getFileExtension(k1) == "" and str.getFileExtension(k2) ~= "" then
                                return false
                            elseif str.getFileExtension(k1) ~= "" and str.getFileExtension(k2) == "" then
                                return true
                            else
                                return str.getFileExtension(k1) < str.getFileExtension(k2)
                            end
                        end
                    end)  --this whole large table.sort function sorts out the directories first and the extensionless files last
            elseif sortType == "size" then
                table.sort(filesInDir,
                    function (k1, k2)
                        return fs.getSize(currSelection.."/"..k1) < fs.getSize(currSelection.."/"..k2)
                    end)
            end
            if redrawNext then
                drawDirInfo(currSelection, sortType, currDirY, currDirOffset, filesInDir, true)
                redrawNext = false
            elseif e ~= "key_up" then
                drawDirInfo(currSelection, sortType, currDirY, currDirOffset, filesInDir, firstDraw)
            end
            e, k = os.pullEvent()
            if e == "char" then
                if k == "s" then
                    if sortType == "name" then
                        sortType = "size"
                    elseif sortType == "size" then
                        sortType = "extension"
                    elseif sortType == "extension" then
                        sortType = "name"
                    end
                    redrawNext = true
                elseif k == "d" then
                    sendMsg("Please give directory name: ")
                    local newdirname = read()
                    if newdirname then
                        if fs.isReadOnly(currSelection) then
                            err("Directory is read-only")
                        else
                            fs.makeDir(currSelection.."/"..newdirname)
                        end
                    end
                    redrawNext = true
                elseif k == "D" then
                    clearScreenLine(hig)
                    local sst = "Confirm deletion of directory<"..shell.resolve(currSelection.."/"..filesInDir[currDirY + currDirOffset]).."> [{y(es)},n(o),a(ll),q(uit)]"
                    if #sst > wid then
                        clearScreenLine(hig - 1)
                        setpos(1, hig-1)
                    else
                        setpos(1, hig)
                    end
                    write(string.sub(sst, 1, wid))
                    if #sst > wid then
                        setpos(1, hig)
                        write(string.sub(sst, wid, #sst))
                    end
                    local _,op
                    while op ~= "y" and op ~= "n" and op ~= "a" and op ~= "q" do
                        _,op = pullChar()
                        if op == "y" then
                            fs.delete(currSelection.."/"..filesInDir[currDirY + currDirOffset])
                        elseif op == "a" then
                            fs.delete(currSelection)
                            fs.makeDir(currSelection)
                            currDirY = 1
                            currDirOffset = 0
                        elseif op == "q" then
                            running = false
                        end
                    end
                    clearScreenLine(hig)
                    redrawNext = true
                elseif k == "R" then
                    sendMsg("Moving "..shell.resolve(currSelection.."/"..filesInDir[currDirY + currDirOffset]).." to : "..shell.resolve(currSelection).."/")
                    fs.move(shell.resolve(currSelection.."/"..filesInDir[currDirY + currDirOffset]), shell.resolve(currSelection).."/"..read())
                elseif k == "%" then
                    sendMsg("Enter filename: ")
                    local filenamevar = read()
                    if filenamevar then
                        if fs.isDir("/"..shell.resolve(currSelection .. "/" .. filenamevar)) then
                            sendMsg("\"/"..shell.resolve(currSelection .. "/" .. filenamevar).. "\" is a directory")
                            currSelection = currSelection .. "/" .. filenamevar
                            drawDirInfo(currSelection, sortType, currDirY, currDirOffset, filesInDir, true)
                        else
                            return "/"..shell.resolve(currSelection .. "/" .. filenamevar)
                        end
                    end
                elseif k == "-" then
                    currSelection = currSelection .. "/" .. ".."
                    redrawNext = true
                elseif k == "j" then
                    if currDirY + currDirOffset < #filesInDir then
                        currDirY = currDirY + 1
                    end
                    while currDirY > hig - 7 do
                        currDirY = currDirY - 1
                        currDirOffset = currDirOffset + 1
                    end
                elseif k == "k" then
                    if currDirY + currDirOffset > 1 then
                        currDirY = currDirY - 1
                    end
                    while currDirY < 1 do
                        currDirY = currDirY + 1
                        currDirOffset = currDirOffset - 1
                    end
                end
            elseif e == "key" then
                if k == keys.enter then
                    if fs.isDir(currSelection .. "/" .. filesInDir[currDirY + currDirOffset]) then
                        currSelection = currSelection .. "/" .. filesInDir[currDirY + currDirOffset]
                        currDirY = 1
                        currDirOffset = 0
                        --refresh file list
                        realFilesInDir = fs.list(currSelection)
                        if not (shell.resolve(currSelection) == "") then
                            filesInDir = {".."}
                        else
                            filesInDir = {}
                        end
                        for i=1,#realFilesInDir,1 do
                            table.insert(filesInDir, #filesInDir + 1, realFilesInDir[i])
                        end
                        redrawNext = true
                    else
                        return "/"..shell.resolve(currSelection .. "/" .. filesInDir[currDirY + currDirOffset])
                    end
                    redrawNext = true
                elseif k == keys.down then
                    if currDirY + currDirOffset < #filesInDir then
                        currDirY = currDirY + 1
                    end
                    while currDirY > hig - 7 do
                        currDirY = currDirY - 1
                        currDirOffset = currDirOffset + 1
                    end
                elseif k == keys.up then
                    if currDirY + currDirOffset > 1 then
                        currDirY = currDirY - 1
                    end
                    while currDirY < 1 do
                        currDirY = currDirY + 1
                        currDirOffset = currDirOffset - 1
                    end
                end
            elseif e == "term_resize" then
                resetSize()
                while currDirY > hig - 7 do
                    currDirY = currDirY - 1
                    currDirOffset = currDirOffset + 1
                end
                while currDirY < 1 do
                    currDirY = currDirY + 1
                    currDirOffset = currDirOffset - 1
                end
                drawDirInfo(currSelection, sortType, currDirY, currDirOffset, filesInDir, true)
            end
            if firstDraw then
                firstDraw = false
            end
        end
    else
        error("dirOpener got invalid path: "..dir.." is not a directory.")
    end
end


for i=1,#decargs,1 do
    if decargs[i] == "--version" then
        print("CCVIM - ComputerCraft Vi IMproved "..version.." ("..releasedate..")")
        do return end --termination
    end
end

if #decargs["files"] > 0 then
    openfiles = decargs["files"]
    for i=1,#openfiles,1 do
        if fs.isDir(fil.topath(decargs["files"][i])) then
            decargs["files"][i] = dirOpener(fil.topath(decargs["files"][i]), decargs["files"][i])
        end
        local nodirectories = fs.getName(decargs["files"][i])
        local filenamestring = ""
        if fs.exists(fil.topath(decargs["files"][i])) then
            local doneGettingEnd = false
            for j=#nodirectories,1,-1 do
                if string.sub(nodirectories, j, j) ~= "." and not doneGettingEnd then
                    filenamestring = string.sub(nodirectories, j, j) .. filenamestring
                else
                    doneGettingEnd = true
                end
            end
            filelines = fil.toArr(fil.topath(decargs["files"][i]))
            fileContents[i] = fil.toArr(fil.topath(decargs["files"][i]))
            if not fileContents[i] then
                error(decargs["files"][i].." failed to load. If this issue persists, please create an issue on the github repository.")
            end
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
        else
            table.insert(openfiles, #openfiles + 1, decargs["files"][1])
            table.insert(fileContents, #fileContents + 1, {""})
            newfile = true
            local doneGettingEnd = false
            for j=#decargs["files"][i],1,-1 do
                if string.sub(decargs["files"][i], j, j) ~= "." and not doneGettingEnd then
                    filenamestring = string.sub(decargs["files"][i], j, j) .. filenamestring
                else
                    doneGettingEnd = true
                end
            end
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
        local multilinesInFile = {{}, {}, {}} --beginning quote points, regular quote points, end quote points
        local synt
        if filenamestring ~= decargs["files"][i] and filenamestring ~= string.sub(decargs["files"][i], 2, #decargs["files"][i]) then
            if fs.exists("/vim/syntax/"..filenamestring..".lua") then
                local tmp = require("/vim/syntax/"..filenamestring)
                synt = tmp.syntax()
            end
        end
        if synt then
            local quotepoints = {}
            local justset = false
            for j=1,#fileContents[i],1 do
                local quotationmarks = str.indicesOfLetter(fileContents[i][j], synt[3])
                local inquotes = false
                justset = false
                for k=1,#fileContents[i][j],1 do
                    if tab.find(quotationmarks, k) then
                        if not inquotes then
                            if k < quotationmarks[#quotationmarks] then
                                inquotes = true
                                justset = true
                            end
                        end
                    end
                    if inquotes then
                        table.insert(quotepoints, #quotepoints, k - 2)
                    end
                    if tab.find(quotationmarks, k) and not justset then
                        if inquotes then
                            inquotes = false
                        end
                    end
                    justset = false
                end
            end
            local inmulti = false
            justset = false
            for j=1,#fileContents[i],1 do
                if str.find(fileContents[i][j], synt[7][1], quotepoints) and not inmulti then
                    inmulti = true
                    justset = true
                    table.insert(multilinesInFile[1], #multilinesInFile[1] + 1, j)
                end
                if inmulti and not (str.find(fileContents[i][j], synt[7][2])) and not justset then
                    table.insert(multilinesInFile[2], #multilinesInFile[2] + 1, j)
                end
                if str.find(fileContents[i][j], synt[7][2]) then
                    if inmulti then
                        inmulti = false
                        table.insert(multilinesInFile[3], #multilinesInFile[3] + 1, j)
                    end
                end
                justset = false
            end
            fileContents[i]["Multi-line comments"] = multilinesInFile
        end
    end
    filelines = fileContents[1]
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
    setcolors(colors.black, colors.white)
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
    drawFile(true)
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
                elseif fs.isReadOnly(fil.topath(name)) then
                    err("File is read-only")
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
                elseif fs.isReadOnly(fil.topath(name)) then
                    err("File is read-only")
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
                        recalcMLCs(true)
                        drawFile(true)
                        clearScreenLine(hig)
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                    end
                end
            elseif cmdtab[1] == ":wq" or cmdtab[1] == ":x" then
                local name = ""
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
                    if cmdtab[2] == nil and openfiles[currfile] == "" then
                        err("No file name")
                    elseif fs.isReadOnly(fil.topath(name)) then
                        err("File is read-only")
                    else
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
                                recalcMLCs(true)
                                drawFile(true)
                                clearScreenLine(hig)
                            end
                        end
                    end
                else
                    err("No file name")
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
                        if fs.isDir(name) then
                            filename = dirOpener(name)
                        else
                            filename = name
                        
                        end
                    else
                        filename = ""
                    end
                    table.insert(openfiles, #openfiles + 1, filename)
                    if currfile == 0 then
                        currfile = 1
                    end
                    newfile = false
                    if fs.exists(fil.topath(filename)) then
                        filelines = fil.toArr(fil.topath(filename))
                        if filelines then
                            sendMsg("\""..filename.."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                        else
                            newfile = true
                            sendMsg("\""..filename.."\" [New File]")
                        end
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
                    if filenamestring ~= openfiles[currfile] and filenamestring ~= string.sub(openfiles[currfile], 2, #openfiles[currfile]) then
                        fileContents[currfile]["filetype"] = filenamestring
                        if fs.exists("/vim/syntax/"..filenamestring..".lua") then
                            filetypearr[filenamestring] = require("/vim/syntax/"..filenamestring)
                        else
                            fileContents[currfile]["filetype"] = nil
                        end
                    else
                        fileContents[currfile]["filetype"] = nil
                    end
                    if newfile then
                        moveCursorRight()
                    end
                    recalcMLCs(true)
                    drawFile(true)
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
                        recalcMLCs(true)
                        drawFile(true)
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
                    end
                    recalcMLCs(true)
                    drawFile(true)
                    sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                    end
                    recalcMLCs(true)
                    drawFile(true)
                    sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
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
                    recalcMLCs(true)
                    drawFile(true)
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
                    recalcMLCs(true)
                    drawFile(true)
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
                            recalcMLCs(true)
                            drawFile(true)
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
                            recalcMLCs(true)
                            drawFile(true)
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
                        recalcMLCs(true)
                        drawFile(true)
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
                        recalcMLCs(true)
                        drawFile(true)
                        clearScreenLine(hig)
                        sendMsg("\""..openfiles[currfile].."\" "..#filelines.."L, "..#(tab.getLongestItem(filelines)).."C")
                    end
                end
            elseif cmdtab[1] == ":set" then
                local seterror = false
                if cmdtab[2] == "number" then
                    linenumbers = true
                    lineoffset= 4
                    drawFile(true)
                elseif cmdtab[2] == "mobile" then
                    mobile = true
                elseif cmdtab[2] == "nonumber" then
                    linenumbers = false
                    lineoffset = 0
                    drawFile(true)
                elseif cmdtab[2] == "nomobile" then
                    mobile = false
                elseif cmdtab[2] == "lowspec" then
                    lowspec = true
                    drawFile(true)
                elseif cmdtab[2] == "nolowspec" then
                    lowspec = false
                    drawFile(true)
                elseif str.find(cmdtab[2], "=") then
                    local tmp = str.split(cmdtab[2], "=")
                    local comm = tmp[1]
                    local stri = ""
                    for i=2,#tmp,1 do
                        stri = stri .. tmp[i]
                        if i ~= #tmp then
                            stri = stri .. "="
                        end
                    end
                    if comm == "filetype" then
                        if stri ~= openfiles[currfile] and stri ~= string.sub(openfiles[currfile], 2, #openfiles[currfile]) then
                            fileContents[currfile]["filetype"] = stri
                            if fs.exists("/vim/syntax/"..stri..".lua") then
                                filetypearr[stri] = require("/vim/syntax/"..stri)
                            else
                                fileContents[currfile]["filetype"] = nil
                            end
                        else
                            fileContents[currfile]["filetype"] = nil
                        end
                    elseif comm == "scale" then
                        if monitor and tonumber(stri) then
                            monitor.setTextScale(tonumber(stri))
                        end
                    end
                    resetSize()
                    redrawTerm()
                    recalcMLCs(true)
                    drawFile(true)
                else
                    err("Variable " .. cmdtab[2] .. " not supported.")
                    seterror = true
                end
                if not seterror then
                    clearScreenLine(hig)
                end
            elseif cmdtab[1] == ":resetscale" then
                resetSize()
                redrawTerm()
            elseif cmdtab[1] == ":syntax" then
                if cmdtab[2] == "on" then
                    syntaxhighlighting = true
                elseif cmdtab[2] == "off" then
                    syntaxhighlighting = false
                else
                    err("invalid :syntax subcommand: "..cmdtab[2])
                end
                recalcMLCs(true)
                drawFile(true)
            elseif cmdtab[1] == ":control" or cmdtab[1] == ":ctrl" then --not yet working
                local _, ch
                if not cmdtab[2] then
                    sendMsg("Emulating held control until next key press:")
                    _, ch = os.pullEvent("char")
                    sendMsg("Sent CONTROL + "..ch)
                else
                    ch = cmdtab[2]
                    clearScreenLine(hig)
                end
                if ch == "e" then
                    currFileOffset = currFileOffset + 1
                    currCursorY = currCursorY - 1
                elseif ch == "y" then
                    currFileOffset = currFileOffset - 1
                    currCursorY = currCursorY + 1
                elseif ch == "b" then
                    local oldCursorY = currCursorY
                    if currCursorY + currFileOffset > hig - 1 then
                        currCursorY = currCursorY - (hig - 1)
                    end
                    while currCursorY < oldCursorY do
                        currCursorY = currCursorY + 1
                        currFileOffset = currFileOffset - 1
                    end
                elseif ch == "f" then
                    local oldCursorY = currCursorY
                    if currCursorY + currFileOffset < #filelines - (hig - 1) then
                        currCursorY = currCursorY + (hig - 1)
                    end
                    while currCursorY > oldCursorY do
                        currCursorY = currCursorY - 1
                        currFileOffset = currFileOffset + 1
                    end
                elseif ch == "d" then
                    local oldCursorY = currCursorY
                    if currCursorY + currFileOffset < #filelines - math.floor((hig - 1)/2) then
                        currCursorY = currCursorY + math.floor((hig - 1)/2)
                    end
                    while currCursorY > oldCursorY do
                        currCursorY = currCursorY - 1
                        currFileOffset = currFileOffset + 1
                    end
                    while currFileOffset > #filelines - (hig - 1) do
                        currFileOffset = currFileOffset - 1
                        currCursorY = currCursorY + 1
                    end
                elseif ch == "u" then
                    local oldCursorY = currCursorY
                    if currCursorY + currFileOffset > (hig - 1) then
                        currCursorY = currCursorY - math.floor((hig - 1)/2)
                    end
                    while currCursorY < oldCursorY do
                        currCursorY = currCursorY + 1
                        currFileOffset = currFileOffset - 1
                    end
                    while currFileOffset < 0 do
                        currFileOffset = currFileOffset + 1
                        currCursorY = currCursorY - 1
                    end
                end
                drawFile()
            elseif cmdtab[1] ~= "" then
                err("Not an editor command or unimplemented: "..cmdtab[1])
            end
        elseif var1 == "i"then
            insertMode()
        elseif var1 == "I" then
            currXOffset = 0
            currCursorX = 1
            drawFile(true)
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
            drawFile(true)
        elseif var1 == "M" then
            currCursorY = math.floor((hig - 1) / 2)
            drawFile(true)
        elseif var1 == "L" then
            currCursorY = hig - 1
            drawFile(true)
        elseif var1 == "r" then
            local _, chr = pullChar()
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. chr .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #(filelines[currCursorY + currFileOffset]))
            recalcMLCs()
            drawFile(true)
            if fileContents[currfile] then
                fileContents[currfile]["unsavedchanges"] = true
            end
        elseif var1 == "J" then
            if filelines[currCursorY + currFileOffset] and filelines[currCursorY + currFileOffset + 1] then
                filelines[currCursorY + currFileOffset] = filelines[currCursorY + currFileOffset] .. " " .. filelines[currCursorY + currFileOffset + 1]
                table.remove(filelines, currCursorY + currFileOffset + 1)
                recalcMLCs()
                drawFile(true)
                fileContents[currfile]["unsavedchanges"] = true
            end
        elseif var1 == "o" then
            table.insert(filelines, currCursorY + currFileOffset + 1, "")
            moveCursorDown()
            currCursorX = 1
            currXOffset = 0
            recalcMLCs()
            drawFile(true)
            insertMode()
            if fileContents[currfile] then
                fileContents[currfile]["unsavedchanges"] = true
            end
        elseif var1 == "O" then
            table.insert(filelines, currCursorY + currFileOffset, "")
            currCursorX = 1
            currXOffset = 0
            recalcMLCs()
            drawFile(true)
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
            recalcMLCs()
            drawFile()
            if fileContents[currfile] then
                fileContents[currfile]["unsavedchanges"] = true
            end
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
                    while currCursorX < 1 do
                        currXOffset = currXOffset - 1
                        currCursorX = currCursorX + 1
                    end
                end
            end
            recalcMLCs()
            drawFile(true)
        elseif var1 == "D" then
            copybuffer = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, #filelines[currCursorY + currFileOffset])
            copytype = "text"
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
            drawFile()
            recalcMLCs()
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
            recalcMLCs(true)
            drawFile(true)
            if fileContents[currfile] then
                fileContents[currfile]["unsavedchanges"] = true
            end
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
            recalcMLCs(true)
            drawFile(true)
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
                        recalcMLCs(true)
                        drawFile(true)
                        fileContents[currfile]["unsavedchanges"] = true
                    end
                end
            elseif ch == "g" then
                _, ch = pullChar()
                if ch == "g" then
                    currCursorY = tonumber(num)
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
                        recalcMLCs(true)
                        drawFile(true)
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
                currCursorY = tonumber(num)
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
                recalcMLCs()
                drawFile(true)
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
                        recalcMLCs(true)
                        drawFile(true)
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
                        recalcMLCs(true)
                        drawFile(true)
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
                        recalcMLCs(true)
                        drawFile(true)
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
                        recalcMLCs(true)
                        drawFile(true)
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
            if begs[#begs] then
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
            if begs[#begs] then
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
            if begs[1] then
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
        elseif var1 == "^" then
            currCursorX = 1
            currXOffset = 0
            local i = currCursorX
            while string.sub(filelines[currCursorY + currFileOffset], i, i) == " " and i < #filelines[currCursorY + currFileOffset] do
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
                recalcMLCs()
                drawFile()
                fileContents[currfile]["unsavedchanges"] = true
                insertMode()
            elseif c == "$" then
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
                recalcMLCs()
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
                    recalcMLCs()
                    drawFile()
                    fileContents[currfile]["unsavedchanges"] = true
                    insertMode()
                end
            elseif c == "w" or c == "e" then
                local word, beg, ed = str.wordOfPos(filelines[currCursorY + currFileOffset], currCursorX + currXOffset)
                filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1).. string.sub(filelines[currCursorY + currFileOffset], ed + 1, #filelines[currCursorY + currFileOffset])
                recalcMLCs()
                drawFile()
                fileContents[currfile]["unsavedchanges"] = true
                insertMode()
            end
        elseif var1 == "C" then
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1)
            recalcMLCs()
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
            insertMode()
        elseif var1 == "s" then
            filelines[currCursorY + currFileOffset] = string.sub(filelines[currCursorY + currFileOffset], 1, currCursorX + currXOffset - 1) .. string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset + 1, #filelines[currCursorY + currFileOffset])
            recalcMLCs()
            drawFile()
            if not fileContents[currfile] then
                fileContents[currfile] = {""}
            end
            fileContents[currfile]["unsavedchanges"] = true
            insertMode()
        elseif var1 == "S" then
            filelines[currCursorY + currFileOffset] = ""
            currCursorX = 1
            currXOffset = 0
            recalcMLCs()
            drawFile()
            fileContents[currfile]["unsavedchanges"] = true
            insertMode()
        elseif var1 == "%" then
            local startpos = {currCursorX, currXOffset, currCursorY, currFileOffset}
            local startbracket = string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset)
            local endbracket = ""
            if startbracket == "(" then
                endbracket = ")"
            elseif startbracket == "{" then
                endbracket = "}"
            elseif startbracket == "[" then
                endbracket = "]"
            else
                endbracket = nil
            end
            if endbracket then
                local extrabrackets = 0
                local continuefor = true
                local test = 0
                currCursorX = currCursorX + 1
                setcolors(colors.black, colors.white)
                for i=currCursorY + currFileOffset,#filelines,1 do
                    if continuefor then
                        while currCursorX + currXOffset <= #filelines[currCursorY + currFileOffset] do
                            if string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset) == startbracket then
                                extrabrackets = extrabrackets + 1
                            elseif string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset) == endbracket then
                                if extrabrackets > 0 then
                                    extrabrackets = extrabrackets - 1
                                else
                                    extrabrackets = extrabrackets - 1
                                end
                            end
                            currCursorX = currCursorX + 1
                        end
                        if (string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset) == endbracket and extrabrackets == 0) or extrabrackets < 0 then
                            if currCursorX > 1 then
                                currCursorX = currCursorX - 1
                            end
                            continuefor = false
                        else
                            currCursorX = 1
                            currXOffset = 0
                            if #filelines > 1 then
                                currCursorY = currCursorY + 1
                            end
                        end
                    end
                end
            end
            while currCursorX < 1 do
                currCursorX = currCursorX + 1
                currXOffset = currXOffset - 1
            end
            while currCursorX > wid - lineoffset do
                currCursorX = currCursorX - 1
                currXOffset = currXOffset + 1
            end
            while currCursorY > hig - 1 do
                currCursorY = currCursorY - 1
                currFileOffset = currFileOffset + 1
            end
            drawFile(true)
            if not string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset) == endbracket then
                currCursorX = startpos[1]
                currXOffset = startpos[2]
                currCursorY = startpos[3]
                currFileOffset = startpos[4]
            end
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
