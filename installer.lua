local function initialMenu()
    term.clear()
    term.setCursorPos(1, 1)
    print("Welcome to the CCVIM Installer")
    print() --skip a line
    print("1. Install CCVIM")
    print("2. Add CCVIM to universal path")
    print("3. Exit")
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

local function addToPath()
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
        end
    else
        print("Already added to file.")
    end
    print("Press any key to continue...")
    os.pullEvent("key")
end

local function download(url, file)
    local content = http.get(url).readAll()
    if not content then
        error("Failed to access resource " .. url)
    end
    local fi = fs.open(file, "w")
    fi.write(content)
    fi.close()
end

local function install()
    print("Downloading files from github...")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/vim.lua", "/vim/vim.lua")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/args.lua", "/vim/lib/args.lua")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/fil.lua", "/vim/lib/fil.lua")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/str.lua", "/vim/lib/str.lua")
    download("https://raw.githubusercontent.com/Minater247/CCVim/main/lib/tab.lua", "/vim/lib/tab.lua")
    print("Done.")
    print("Do you want to add CCVIM to your universal path?")
    print("This allows you to access it from anywhere on the computer. [y/n]")
    local _, c = os.pullEvent("char")
    if c == "y" then
        addToPath()
    end
    print("Finished installing.")
    print("Press any key to continue...")
    os.pullEvent("key")
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
        running = false
    end
end