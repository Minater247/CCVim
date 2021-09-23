local fil = require("/vim/lib/fil")
local currCursorX = 1
local currXOffset = 0
local currCursorY = 6
local currFileOffset = 0
local filelines = fil.toArr(fil.topath("brackets"))
local wid, hig = term.getSize()
local log = fs.open(fil.topath("log"), "w")
local function setcolors(a, b)
    term.setBackgroundColor(a)
    term.setTextColor(b)
end
local function clearScreenLine(l)
    term.setCursorPos(1, l)
    for i=1,wid,1 do
        term.write(" ")
    end
end
local function setpos(a, b)
    term.setCursorPos(a, b)
end
local function drawFile()
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
                            term.write(" ")
                        end
                    end
                    if i < 10000 then
                        term.write(i)
                        if i < 1000 then
                            term.write(" ")
                        end
                    else
                        term.write("10k+")
                    end
                end
                setcolors(colors.black, colors.white)
                if true then
                    if false then
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
                            term.write(wordsOfLine[j])
                            if j ~= #wordsOfLine then
                                setcolors(colors.black, colors.white)
                                term.write(" ")
                            end
                        end
                        --another loop for drawing strings
                        setpos(1 - currXOffset, i - currFileOffset)
                        local quotationmarks = str.indicesOfLetter(filelines[i], synt[3])
                        local inquotes = false
                        local justset = false
                        local quotepoints = {}
                        setcolors(colors.black, colors.red)
                        for j=1,#filelines[i],1 do
                            setpos(1 - currXOffset + j - 1, i - currFileOffset)
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
                            setpos(1 - currXOffset + commentstart - 1, i - currFileOffset)
                            setcolors(colors.black, colors.green)
                            term.write(string.sub(filelines[i], commentstart, #filelines[i]))
                        end
                        --repeat the line number drawing since we just overwrote it
                        setpos(1, i)
                        setcolors(colors.black, colors.yellow)
                        local _, yy = getWindSize()
                        if yy ~= hig then
                            if i < 1000 then
                                for i=1,3 - #(tostring(i)),1 do
                                    term.write(" ")
                                end
                            end
                            if i < 10000 then
                                term.write(i)
                                term.write(" ")
                            else
                                term.write("10k+")
                            end
                        end
                    else
                        term.write(string.sub(filelines[i], currXOffset + 1, #filelines[i]))
                    end
                end
            else
                setcolors(colors.black, colors.purple)
                term.write("~")
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
        setpos(currCursorX, currCursorY)
    else
        setpos(currCursorX, currCursorY)
    end
    setcolors(colors.lightGray, colors.white)
    if tmp ~= nil and tmp ~= "" then
        term.write(tmp)
    else
        term.write(" ")
    end
    setcolors(colors.black, colors.white)
end
local function sendMsg(message)
    clearScreenLine(hig)
    setpos(1, hig)
    setcolors(colors.black, colors.white)
    term.write(message)
end
setpos(1, 1)
drawFile()
os.pullEvent("key")

if true then
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
                    sendMsg(string.sub(filelines[currCursorY + currFileOffset], currCursorX + currXOffset, currCursorX + currXOffset))
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
                    currCursorY = currCursorY + 1
                end
            end
        end
    end
    while currCursorX < 1 do
        currCursorX = currCursorX + 1
        currXOffset = currXOffset - 1
    end
    while currCursorX > wid do
        currCursorX = currCursorX - 1
        currXOffset = currXOffset + 1
    end
    while currCursorY > hig - 1 do
        currCursorY = currCursorY - 1
        currFileOffset = currFileOffset + 1
    end
    drawFile()
end