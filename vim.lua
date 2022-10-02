local str = require("/vim/lib/str")
local fil = require("/vim/lib/fil")
local argv = require("/vim/lib/args")
local tab = require("/vim/lib/tab")

local wid, hig
local currBuf = 0
local running = true
local changedBuffers = true
local redrawBuffer = false

local version = 0.734
local releasedate = "2022-08-02"
local fileExplorerVer = 0.121

local vars = {
    syntax = true,
    lineoffset = 4,
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

if tab.contains(args, "--version") then
    print("CCVIM - ComputerCraft Vi IMproved "..version.." ("..releasedate..")")
    do return end
end

local function resetSize()
    if monitor then
        wid, hig = monitor.getSize()
    else
        wid, hig = term.getSize()
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

local function clear(noreset)
    if not noreset then
        setcolors(colors.black, colors.white)
    end
    if monitor then
        monitor.clear()
    else
        term.clear()
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
        if vars.syntax then
            buf.lines.syntax = buf.highlighter.parseSyntax(buf.lines.text)
        end
    end
    redrawBuffer = true
    return buf
end

local function clearScreenLine(line)
    setcolors(colors.black, colors.white)
    setpos(1, line)
    for i=1,wid do
        write(" ")
    end
end

local function clearbufarea(noreset)
    if not noreset then
        setcolors(colors.black, colors.white)
    end
    for i=1, hig - 1 do
        clearScreenLine(i)
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
    if running then
        local givenpath = path
        if path then
            path = shell.resolve(path)
        end
        local buf = {}
        buf.lines = {text = fil.toArray(path) or {""}}
        buf.path = path
        buf.name = givenpath or ""
        buf.filetype = str.getFileExtension(path)
        buf = loadSyntax(buf)

        if vars.syntax and buf.highlighter then
            buf.lines.syntax = buf.highlighter.parseSyntax(buf.lines.text)
        end

        buf.cursorX, buf.cursorY = 1, 1
        buf.oldCursorX = 1
        buf.scrollX, buf.scrollY = 0, 0
        buf.unsavedChanges = false

        return buf
    end
end

local function pullChar()
    local _, tm = os.pullEvent("char")
    return _, tm
end

local function drawBuffer(buf)
    if running then
        if not buf then
            clearbufarea()
            setcolors(colors.black, colors.purple)
            for i=1, hig - 1 do
                setpos(1, i)
                write("~")
            end
            setcolors(colors.black, colors.white)
            setpos((wid / 2) - (33 / 2), (hig / 2) - 2)
            write("CCVIM - ComputerCraft Vi Improved")
            setpos((wid / 2) - (#("version ".. version) / 2), (hig / 2))
            write("version "..version)
            setpos((wid / 2) - (13 / 2), (hig / 2) + 1)
            write("By Minater247")
            if wid > 53 then
                setpos((wid / 2) - (46 / 2), (hig / 2) + 2)
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
        else
            clearbufarea()
            local cursorColor
            if buf.lines.syntax and vars.syntax then
                local limit = hig + buf.scrollY - 1
                if limit > #buf.lines.syntax then
                    limit = #buf.lines.syntax
                end
                for i=buf.scrollY + 1, limit do
                    local xpos = 1 + vars.lineoffset
                    for j=1, #buf.lines.syntax[i] do
                        setpos(xpos - buf.scrollX, i - buf.scrollY)
                        setcolors(colors.black, buf.lines.syntax[i][j].color)
                        write(buf.lines.syntax[i][j].string)
                        xpos = xpos + #buf.lines.syntax[i][j].string
                        if (xpos > buf.cursorX) and (not cursorColor) and i == buf.cursorY then
                            cursorColor = buf.lines.syntax[i][j].color
                        end
                        if xpos - buf.scrollX > wid then
                            break
                        end
                    end
                end
                setpos(buf.cursorX - buf.scrollX + vars.lineoffset, buf.cursorY - buf.scrollY)
                setcolors(colors.lightGray, cursorColor or colors.orange)
                local st = buf.lines.text[buf.cursorY]:sub(buf.cursorX, buf.cursorX)
                if st == "" then
                    st = " "
                end
                write(st)
            else
                local limit = hig + buf.scrollY - 1
                --todo: drop this and do the tilde when no file text on that line onwards
                if limit > #buf.lines.text then
                    limit = #buf.lines.text
                end
                for i=buf.scrollY + 1, limit do
                    setpos(1 - buf.scrollX + vars.lineoffset, i - buf.scrollY)
                    write(buf.lines.text[i])
                end
                setpos(buf.cursorX - buf.scrollX + vars.lineoffset, buf.cursorY - buf.scrollY)
                setcolors(colors.lightGray, colors.white)
                local st = buf.lines.text[buf.cursorY]:sub(buf.cursorX, buf.cursorX)
                if st == "" then
                    st = " "
                end
                write(st)
            end
            if vars.lineoffset > 0 then
                setcolors(colors.black, colors.yellow)
                for i=buf.scrollY,(hig-1)+buf.scrollY do
                    setpos(1, i - buf.scrollY)
                    if i < 1000 then
                        write(string.rep(" ", 3 - #tostring(i)))
                    end
                    if i < 10000 then
                        if i <= #buf.lines.text then
                            write(i)
                        end
                    else
                        if i <= #buf.lines.text then
                            write("10k+")
                        end
                    end
                end
            end
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

local function close()
    table.remove(buffers, currBuf)
    if currBuf > #buffers then
        currBuf = currBuf - 1
        changedBuffers = true
    end
    if currBuf == 0 then
        setcolors(colors.black, colors.white)
        clearbufarea()
        setpos(1, 1)
        running = false
        currBuf = 1
    end
end

--runCommand relies on dirOpener, but that also relies on runCommand.
--we need this table to allow this circular dependency to work at all.
local commands = {}

commands.runCommand = function(command)
    command = command:sub(2, #command)
    local cmdtab = str.split(command, " ")
    if cmdtab[1] == "q" or cmdtab[1] == "q!" then
        if buffers[currBuf] then
            if buffers[currBuf].unsavedChanges and cmdtab[1] ~= ":q!" then
                err("No write since last change (add ! to override)")
                return false
            else
                close()
            end
        else
            close()
        end
        return true
    elseif cmdtab[1] == "e" then
        local nametab = cmdtab
        table.remove(nametab, 1)
        local name = table.concat(nametab, " ")
        if fs.isDir(name) then
            name = commands.dirOpener(shell.resolve(name), name)
        end
        buffers[#buffers+1] = newBuffer(name)
        currBuf = #buffers
        return true
    elseif cmdtab[1] == "sav" or cmdtab[1] == "saveas" or cmdtab[1] == "sav!" or cmdtab[1] == "saveas!" then
        local nametab = cmdtab
        table.remove(nametab, 1)
        local name = table.concat(nametab, " ")
        if #cmdtab < 2 then
            err("Argument required")
            return false
        elseif fs.exists(fil.topath(name)) and not (cmdtab[1]:sub(#cmdtab[1], #cmdtab[1]) == "!") then
            err("File exists (add ! to override)")
            return false
        elseif fs.isReadOnly(fil.topath(name)) then
            err("File is read-only")
            return false
        else
            local new = true
            if fs.exists(fil.topath(name)) then
                new = false
            end
            local file = fs.open(fil.topath(name), "w")
            for i=1,#buffers[currBuf].lines.text do
                file.writeLine(buffers[currBuf].lines.text[i])
            end
            file.close()
            buffers[currBuf].unsavedChanges = false
            sendMsg("\""..name.."\" ")
            if new then
                write("[New] ")
            end
            write(" "..#buffers[currBuf].lines.text.."L written")
        end
        return true
    elseif cmdtab[1] == "w" or cmdtab[1] == "w!" then
        local name = ""
        if #cmdtab > 1 then
            local nametab = cmdtab
            table.remove(nametab, 1)
            name = table.concat(nametab, " ")
        else
            name = buffers[currBuf].path
        end
        if #cmdtab < 2 and buffers[currBuf].path == "" then
            err("No file name")
            return false
        elseif fs.isReadOnly(name) then
            err("File is read-only")
            return false
        else
            local new = true
            if fs.exists(name) then
                new = false
            end
            local fl = fs.open(name, "w")
            for i=1,#buffers[currBuf].lines.text do
                fl.writeLine(buffers[currBuf].lines.text[i])
            end
            fl.close()
            buffers[currBuf].unsavedChanges = false
            sendMsg("\""..name.."\" ")
            if new then
                write("[New]  ")
            else
                write(" ")
            end
            write(#buffers[currBuf].lines.text.."L written")
        end
        return true
    elseif cmdtab[1] == "wq" or cmdtab[1] == "x" then
        local ok = commands.runCommand(":w")
        if ok then
            ok = commands.runCommand(":q")
        end
        return ok
    elseif cmdtab[1] == "r" or cmdtab[1] == "read" then
        if #cmdtab > 1 then
            local nametab = cmdtab
            table.remove(nametab, 1)
            local name = table.concat(nametab, " ")
            if fs.exists(shell.resolve(name)) then
                if fs.isDir(shell.resolve(name)) then
                    name = commands.dirOpener(shell.resolve(name), name)
                end
                local secondArr = fil.toArray(shell.resolve(name))
                if not buffers[currBuf] then
                    buffers[currBuf] = newBuffer()
                end
                for i=1,#secondArr,1 do
                    table.insert(buffers[currBuf].lines.text, secondArr[i])
                end
                sendMsg("\""..name.."\" "..#secondArr.."L, "..tab.countchars(secondArr).."C")
            else
                err("Can't open file "..name)
            end
        else
            err("No file name")
        end
    elseif cmdtab[1] == "set" then
        if string.find(cmdtab[2], "=") then
            local parts = str.split(cmdtab[2], "=")
            local name, value = parts[1], parts[2]
            local nametab = cmdtab
            table.remove(cmdtab, 1)
            table.remove(cmdtab, 1)
            value = value .. table.concat(nametab)
            if name == "syntax" then
                buffers[currBuf].filetype = value
                loadSyntax(buffers[currBuf])
            end
        else
            if cmdtab[2] == "number" then
                vars.lineoffset = 4
            elseif cmdtab[2] == "nonumber" then
                vars.lineoffset = 0
            end
        end
    elseif cmdtab[1] == "syntax" then
        if cmdtab[2] == "on" then
            vars.syntax = true
        else
            vars.syntax = false
        end
    else
        err("Not an editor command: "..cmdtab[1])
    end
end

local oldyoff
local function drawDirInfo(dir, sortType, ypos, yoff, filesInDir, initialDraw)
    if initialDraw then
        setcolors(colors.black, colors.white)
        for i=1,hig-1 do
            clearScreenLine(i)
        end
        setpos(1, 1)
        write("\" ")
        for i=1,wid - 4 do
            write("=")
        end
        setpos(1, 2)
        write("\" CCFXP Directory Listing")
        for i=1,wid-25 do
            write(" ")
        end
        setpos(wid-#tostring(fileExplorerVer)-6, 2)
        write("ver. "..fileExplorerVer)
        setpos(1, 5)
        write("\"   Quick Help: -:go up dir  D:delete  R:rename  s:sort-by")
        for i=1,wid-#("\"   Quick Help: -:go up dir  D:delete  R:rename  s:sort-by") do
            write(" ")
        end
    end
    for i=1,wid-#("\"   "..shell.resolve(dir)) do
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
    write(string.rep(" ", wid-#("\"   Sorted by    "..sortType)))
    setpos(1, 6)
    setcolors(colors.black, colors.white)
    write("\" ")
    for i=1,wid - 2 do
        write("=")
    end
    if oldyoff ~= yoff or initialDraw then
        for i=1+yoff,hig - 7 + yoff do
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
        for i=-1,1 do
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
commands.dirOpener = function(dir, inputname)
    local currSelection = dir.."/"
    local fname = shell.resolve(inputname or dir)
    if fname:sub(#fname, #fname) ~= "/" then
        fname = fname .. "/"
    end
    sendMsg("\"/"..fname.."\" is a directory")
    local sortType = "name"
    local currDirY = 1
    local currDirOffset = 0
    local realFilesInDir = fs.list(currSelection)
    local filesInDir = {".."}
    local firstDraw = true
    for i=1,#realFilesInDir do
        table.insert(filesInDir, #filesInDir + 1, realFilesInDir[i])
    end
    if fs.isDir(dir) then
        local stillInExplorer = true
        local redrawNext = false
        local dothide = false
        local reverseSort = false
        local e, k
        while stillInExplorer and running do
            local realFilesInDir = fs.list(currSelection)
            local filesInDir = {}
            if not (shell.resolve(currSelection) == "") then
                filesInDir = {".."}
            end
            for i=1,#realFilesInDir do
                if dothide then
                    if not (realFilesInDir[i]:sub(1, 1) == ".") then
                        table.insert(filesInDir, #filesInDir + 1, realFilesInDir[i])
                    end
                else
                    table.insert(filesInDir, #filesInDir + 1, realFilesInDir[i])
                end
            end
            if sortType == "name" then
                table.sort(filesInDir, 
                    function (k1, k2)
                        if reverseSort then
                            if fs.isDir(currSelection .. "/" .. k1) and not fs.isDir(currSelection .. "/" .. k2) then
                                return false
                            elseif fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                                return k1 > k2
                            elseif not fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                                return true
                            else
                                return k1 > k2
                            end
                        else
                            if fs.isDir(currSelection .. "/" .. k1) and not fs.isDir(currSelection .. "/" .. k2) then
                                return true
                            elseif fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                                return k1 < k2
                            elseif not fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                                return false
                            else
                                return k1 < k2
                            end
                        end
                    end)
            elseif sortType == "extension" then
                table.sort(filesInDir, 
                    function (k1, k2)
                        if reverseSort then
                            if fs.isDir(currSelection .. "/" .. k1) and not fs.isDir(currSelection .. "/" .. k2) then
                                return false
                            elseif fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                                return k1 > k2
                            elseif not fs.isDir(currSelection .. "/" .. k1) and fs.isDir(currSelection .. "/" .. k2) then
                                return true
                            else
                                if str.getFileExtension(k1) == str.getFileExtension(k2) then
                                    return k1 > k2
                                elseif str.getFileExtension(k1) == "" and str.getFileExtension(k2) ~= "" then
                                    return true
                                elseif str.getFileExtension(k1) ~= "" and str.getFileExtension(k2) == "" then
                                    return false
                                else
                                    return str.getFileExtension(k1) > str.getFileExtension(k2)
                                end
                            end
                        else
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
                        end
                    end)  --this whole large table.sort function sorts out the directories first and the extensionless files last
            elseif sortType == "size" then
                table.sort(filesInDir,
                    function (k1, k2)
                        if reverseSort then
                            return fs.getSize(currSelection.."/"..k1) > fs.getSize(currSelection.."/"..k2)
                        else
                            return fs.getSize(currSelection.."/"..k1) < fs.getSize(currSelection.."/"..k2)
                        end
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
                elseif k == "c" then
                    shell.setDir(currSelection)
                elseif k == "g" then
                    e, k = pullChar()
                    if e == "char" then
                        if k == "h" then
                            dothide = not dothide
                            redrawNext = true
                        end
                    end
                elseif k == "r" then
                    reverseSort = not reverseSort
                    redrawNext = true
                elseif k == ":" then
                    commands.runCommand(pullCommand(":"))
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
                        for i=1,#realFilesInDir do
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

local function validateCursor(buf)
    if buf.cursorX - buf.scrollX < 1 then
        buf.scrollX = buf.scrollX - 1
    end
    if buf.cursorX - buf.scrollX + vars.lineoffset > wid then
        buf.scrollX = buf.scrollX + 1
    end
    if buf.cursorY - buf.scrollY < 1 then
        buf.scrollY = buf.scrollY - 1
    end
    if buf.cursorY - buf.scrollY > hig - 1 then
        buf.scrollY = buf.scrollY + 1
    end
    if buf.cursorX > #buf.lines.text[buf.cursorY] + 1 then
        buf.cursorX = #buf.lines.text[buf.cursorY] + 1
    end
    return buf
end


resetSize()
clear()
if not args then
    error("Something has gone very wrong with argument initialization!")
end
for i=1, #args.files do
    local truepath = shell.resolve(args.files[i])
    if fs.exists(truepath) then
        if fs.isDir(truepath) then
            args.files[i] = commands.dirOpener(args.files[i])
        end
    end
    buffers[#buffers+1] = newBuffer(args.files[i])
end
if #buffers > 0 then
    currBuf = 1
    drawBuffer(buffers[currBuf])
end

--[[ debug syntax output
if running then
    local ff = fs.open("/out.test", "w")
    ff.write(textutils.serialise(buffers[currBuf].lines.syntax))
    ff.close()
end
]]

while running do
    resetSize()
    if changedBuffers or redrawBuffer then
        drawBuffer(buffers[currBuf])
    end
    if changedBuffers then
        if buffers[currBuf] then
            local linecount = #buffers[currBuf].lines.text
            local bytecount = 0
            for i=1, #buffers[currBuf].lines.text do
                bytecount = bytecount + #buffers[currBuf].lines.text[i]
            end
            sendMsg("\""..buffers[currBuf].name.."\" "..linecount.."L, "..bytecount.."B")
            changedBuffers = false
        end
    end

    local event = {os.pullEvent()}
    if event[1] == "char" then
        if event[2] == ":" then
            local oldBuf = currBuf
            local oldBufLen = #buffers
            commands.runCommand(pullCommand(":"))
            if (oldBuf ~= currBuf) or (oldBufLen ~= #buffers) then
                changedBuffers = true
            end
        end
    elseif event[1] == "key" then
        if event[2] == keys.left then
            if buffers[currBuf].cursorX > 1 then
                buffers[currBuf].cursorX = buffers[currBuf].cursorX - 1
                buffers[currBuf] = validateCursor(buffers[currBuf])
                buffers[currBuf].oldCursorX = buffers[currBuf].cursorX
                redrawBuffer = true
            end
        elseif event[2] == keys.right then
            if buffers[currBuf].cursorX < #buffers[currBuf].lines.text[buffers[currBuf].cursorY] + 1 then
                buffers[currBuf] = validateCursor(buffers[currBuf])
                buffers[currBuf].oldCursorX = buffers[currBuf].cursorX
                buffers[currBuf].cursorX = buffers[currBuf].cursorX + 1
                redrawBuffer = true
            end
        elseif event[2] == keys.up then
            if buffers[currBuf].cursorY > 1 then
                buffers[currBuf].cursorY = buffers[currBuf].cursorY - 1
                redrawBuffer = true
                buffers[currBuf] = validateCursor(buffers[currBuf])
            end
        elseif event[2] == keys.down then
            if buffers[currBuf].cursorY < #buffers[currBuf].lines.text then
                buffers[currBuf].cursorY = buffers[currBuf].cursorY + 1
                buffers[currBuf] = validateCursor(buffers[currBuf])
                redrawBuffer = true
            end
        end
    end
end

setpos(1, hig)
--setpos(buf.cursorX - buf.scrollX, buf.cursorY - buf.scrollY)