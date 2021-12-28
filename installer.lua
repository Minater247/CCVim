--[[ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

                        CCVIM INSTALLER
                          VERSION 0.15

- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -]]

local function initialMenu()
    term.clear()
    term.setCursorPos(1, 1)
    print("CCVIM Installer v0.15")
    print() --skip a line
    print("1. Install CCVIM")
    print("2. Add CCVIM to universal path")
    print("3. Add syntax to installation")
    print("4. Update CCVIM")
    print("5. Exit")
end

local function find(table, query)
    if table then
        for i=1,#table,1 do
            if table[i] == query then
                return i
            end
        end
        return false
    end
end

local function toArr(filePath)
    local fileHandle = fs.open(filePath, "r")
    local log
    if fileHandle then
        log = {}
        local line = fileHandle.readLine()
        while line do
            table.insert(log, line)
            line = fileHandle.readLine()
        end
        fileHandle.close()
        return log
    else
        return false
    end
end

local setPath = false
local function addToPath()
    if fs.exists("/vim/vim.lua") then
        local lines = toArr("/startup")
        if not find(lines, "shell.setPath(shell.path()..\":/vim/\")") then
            print("This will not work if you have moved your CCVIM installation. Proceed? [y/n]")
            local _, c = os.pullEvent("char")
            if c == "y" or c == "Y" then
                print("Looking for existing startup file...")
                if fs.exists("startup") then
                    print("Existing startup file found. Would you like to back it up (startup.bkup) before proceeding? [y/n]")
                    local _,cha = os.pullEvent("char")
                    if cha == "y" or cha == "Y" then
                        shell.run("cp", "/startup/", "/startup.bkup/")
                        if not fs.exists("startup.bkup") then
                            error("Failed to create backup file.")
                        end
                        print("Backed up existing startup file to /startup.bkup")
                    else
                        print("Proceeding without backing up existing startup file")
                    end
                end
                print("Adding path setup to startup file...")
                local file = fs.open("startup", "a")
                file.writeLine("shell.setPath(shell.path()..\":/vim/\")")
                file.close()
                print("Added path setup to startup file.")
                setPath = true
            end
        else
            print("Already added to file.")
        end
    else
        print("No vim installation found.")
    end
    print("Press any key to continue...")
    os.pullEvent("char")
end

local function download(url, file, noerr)
    local content = http.get(url)
    if not content then
        if not noerr then
            error("Failed to access resource " .. url)
        else
            return false
        end
    end
    content = content.readAll()
    local fi = fs.open(file, "w")
    fi.write(content)
    fi.close()
end

local function install()
    print("Downloading files from github...")
    local oldx, oldy = term.getCursorPos()
    local wid, hig = term.getSize()
    term.setCursorPos(oldx, oldy)
    for i=1,wid,1 do
        term.write(" ")
    end
    term.setCursorPos(oldx, oldy)
    term.write("Downloading vim.lua ...")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/vim.lua", "/vim/vim.lua")
    term.setCursorPos(oldx, oldy)
    for i=1,wid,1 do
        term.write(" ")
    end
    term.setCursorPos(oldx, oldy)
    term.write("Downloading .vimrc ...")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/.vimrc", "/vim/.vimrc")
    term.setCursorPos(oldx, oldy)
    for i=1,wid,1 do
        term.write(" ")
    end
    term.setCursorPos(oldx, oldy)
    term.write("Downloading .version ...")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/.version", "/vim/.version")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/args.lua", "/vim/lib/args.lua")
    term.setCursorPos(oldx, oldy)
    for i=1,wid,1 do
        term.write(" ")
    end
    term.setCursorPos(oldx, oldy)
    term.write("Downloading args.lua ...")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/fil.lua", "/vim/lib/fil.lua")
    term.setCursorPos(oldx, oldy)
    for i=1,wid,1 do
        term.write(" ")
    end
    term.setCursorPos(oldx, oldy)
    term.write("Downloading str.lua ...")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/str.lua", "/vim/lib/str.lua")
    term.setCursorPos(oldx, oldy)
    for i=1,wid,1 do
        term.write(" ")
    end
    term.setCursorPos(oldx, oldy)
    term.write("Downloading tab.lua ...")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/tab.lua", "/vim/lib/tab.lua")
    print("Done.")
    print("Do you want to add CCVIM to your universal path?")
    print("This allows you to access it from anywhere on the computer. [y/n]")
    local _, c = os.pullEvent("char")
    if c == "y" then
        addToPath()
    end
    if fs.exists("/vim/vim.lua") and fs.exists("/vim/lib/args.lua") and fs.exists("/vim/lib/fil.lua") and fs.exists("/vim/lib/str.lua") and fs.exists("/vim/lib/tab.lua") then
        print("Finished installing.")
        print("Are you able to press tab on your device? [y/n]")
        local _, eh = os.pullEvent("char")
        if eh ~= "y" then
            print("Adding config line to .vimrc ...")
            local ff = fs.open("/vim/.vimrc", "a")
            ff.writeLine("set mobile")
            ff.close()
            print("Configured for tabless use. Tap or click the bottom line to exit insert or append mode.")
        else
            print("Using default config.")
        end
        if setPath then
            print("Please reboot your computer to complete the installation")
        end
        print("Press any key to continue...")
        os.pullEvent("char")
    else
        print("Something went wrong. Do you want to delete the existing files and try again? [y/n]")
        local _, eh = os.pullEvent("char")
        if eh == "y" then
            print("Retrying...")
            install()
        else
            print("Vim was partially installed but failed to download some files. Please rerun the installation before usage.")
            print("Press any key to contine.")
            os.pullEvent("key")
        end
    end
end

local function syntax()
    print("Downloader for the official syntax files.")
    print("Enter the file extension for the filetype: ")
    local fts = string.lower(read())
    print("Looking for extension \""..fts.."\" in repo...")
    if download("https://raw.githubusercontent.com/Minater247/CCVim/main/syntax/"..fts..".lua", "/vim/syntax/"..fts..".lua", true) == false then
        print("Could not find file for extension \""..fts.."\"")
        print("Press any key to continue...")
        os.pullEvent("key")
    else
        print("Downloaded syntax for \""..fts.."\"")
        print("Press any key to continue...")
        os.pullEvent("key")
    end
end

local function split(s, delimiter)
    local result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end

local function update()
    print("Fetching current version...")
    local con = true
    local f
    local vimver
    local instver
    local nf
    local nft
    local nvimver
    local ninstver
    if not fs.isDir("/vim/") then
        con = false 
    end
    if fs.exists("/vim/.version") and con then
        f = toArr("/vim/.version")
        vimver = tonumber(f[1])
        instver = tonumber(f[2])
        nf = http.get("https://raw.githubusercontent.com/Minater247/CCVim/main/.version").readAll()
        nft = split(nf, "\n")
        nvimver = tonumber(nft[1])
        ninstver = tonumber(nft[2])
        if ninstver > instver then
            print("This version of the installer is outdated. Please download a new version to continue.")
            print("Download now? [y/n]")
            local _,inp = os.pullEvent("char")
            if inp == "y" then
                download("https://raw.githubusercontent.com/Minater247/CCVim/main/installer.lua", "/vim/installer")
                fs.delete("/vim/installer.lua")
                fs.move("/vim/installer", "/vim/installer.lua")
                print("Updated installer downloaded. Local path is at /vim/installer.lua")
                print("Updating local version file...")
                local filelines = toArr("/vim/.version")
                filelines[2] = ninstver
                local ff = fs.open("/vim/.version", "w")
                for i=1,#filelines,1 do
                    ff.writeLine(filelines[i])
                end
                print("Updated local version.")
                if nvimver > vimver then
                    print("Please restart the installer to complete the update.")
                end
                ff.close()
                print("Exiting.")
                print("Press any key to continue...")
                os.pullEvent("char")
                error() --not an actual error, displays nothing to user. Just used to quit.
            end
        else
            print("Installer version is current.")
            if nvimver > vimver then
                print("An update is available! "..vimver.." -> "..nvimver)
                print("Downloading files from github...")
                download("https://raw.githubusercontent.com/Minater247/CCVim/main/vim.lua", "/vim/vim.lua")
                download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/args.lua", "/vim/lib/args.lua")
                download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/fil.lua", "/vim/lib/fil.lua")
                download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/str.lua", "/vim/lib/str.lua")
                download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/tab.lua", "/vim/lib/tab.lua")
                print("Update complete.")
                print("Updating local version info...")
                local filelines = toArr("/vim/.version")
                filelines[1] = nvimver
                local ff = fs.open("/vim/.version", "w")
                for i=1,#filelines,1 do
                    ff.writeLine(filelines[i])
                end
                print("Updated local version.")
                ff.close()
                print("Wrapping up...")
                --used to be code here
                print("Done.")
                print("Press any key to continue")
                os.pullEvent("key")
            else
                print("CCVIM version is current.")
                print("Press any key to continue...")
                os.pullEvent("key")
            end
        end
    else
        print("Failed to check version.")
        print("Press any key to continue.")
        os.pullEvent("key")
    end
end

local running = true
while running == true do
    initialMenu()
    local _, ch = os.pullEvent("char")
    while tonumber(ch) == nil do
        _, ch = os.pullEvent("char")
    end
    if ch == "1" then
        term.clear()
        term.setCursorPos(1, 1)
        install()
    elseif ch == "2" then
        term.clear()
        term.setCursorPos(1, 1)
        addToPath()
    elseif ch == "3" then
        term.clear()
        term.setCursorPos(1, 1)
        syntax()
    elseif ch == "4" then
        term.clear()
        term.setCursorPos(1, 1)
        update()
    elseif ch == "5" then
        term.clear()
        term.setCursorPos(1, 1)
        running = false
    end
end