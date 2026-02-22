local TUI = require("instui")
assert(TUI)

local label = "CCVIM Installer v0.2"

local BASE_URL
local MANIFEST = "nvim.idx"

local install_dir = "/vim"
local git_branch = "rewrite-2026"

local function httpGet(url)
    local res, err = http.get(url)
    if not res then
        return nil, err or "http.get failed"
    end

    local data = res.readAll()
    res.close()
    return data
end

local function parseManifest(text)
    local files = {}
    local stack = {}

    for line in text:gmatch("[^\r\n]+") do
        if line ~= "" then
            local depth = 0
            while line:sub(1, 1) == "\t" do
                depth = depth + 1
                line = line:sub(2)
            end

            local isDir = line:sub(-1) == "/"
            local name = isDir and line:sub(1, -2) or line

            while #stack > depth do
                table.remove(stack)
            end

            if isDir then
                table.insert(stack, name)
            else
                if #stack == 0 then
                    table.insert(files, name)
                else
                    table.insert(files, table.concat(stack, "/") .. "/" .. name)
                end
            end
        end
    end

    return files
end

local function downloadFile(relPath)
    local url = BASE_URL .. relPath
    local localPath = fs.combine(install_dir, relPath)

    local dir = fs.getDir(localPath)
    if dir and dir ~= "" then
        fs.makeDir(dir)
    end

    local data, err = httpGet(url)
    if not data then
        return false, ("failed to GET %s: %s"):format(url, tostring(err))
    end

    local fh, ferr = fs.open(localPath, "wb")
    if not fh then
        return false, ("failed to open %s: %s"):format(localPath, tostring(ferr))
    end
    fh.write(data)
    fh.close()

    return true
end



-- #region Install progress page
local installerBox = TUI.Components.messageBox{
    fill = true,
    minHeight = 3,
    color = colors.white,
    bgColor = colors.gray
}

local progressBackItem

local function buildInstallProgressMenu()
    TUI.clearMessages(installerBox)
    TUI.addMessage(installerBox, "Beginning install...")

    progressBackItem = TUI.Components.disabledOption("Back")

    return {
        TUI.Components.info("Installing to " .. install_dir .. "  from [" .. git_branch .. "]"),

        TUI.Components.separator(),

        installerBox,

        progressBackItem
    }
end

local function runInstall()
    TUI.addMessage(installerBox, "Downloading manifest from:")
    TUI.addMessage(installerBox, BASE_URL .. MANIFEST)

    local text, err = httpGet(BASE_URL .. MANIFEST)
    if not text then
        TUI.addMessage(installerBox, "ERROR: Could not download manifest:")
        TUI.addMessage(installerBox, "        " .. tostring(err))
        return
    end

    local files = parseManifest(text)
    TUI.addMessage(installerBox, ("Found %d files to install."):format(#files))
    TUI.addMessage(installerBox, "Beginning downloads...")

    for i, rel in ipairs(files) do
        TUI.addMessage(installerBox, ("[%d/%d] %s"):format(i, #files, rel))
        local ok, e = downloadFile(rel)
        if not ok then
            TUI.addMessage(installerBox, "  ERROR: " .. tostring(e))
            TUI.addMessage(installerBox, "Installation aborted.")
            return
        end
    end

    TUI.addMessage(installerBox, "All files downloaded successfully.")
    TUI.addMessage(installerBox, "Installation complete.")
end
-- #endregion Install progress page

-- #region Main install page
local function updateInstallDir(dir)
    install_dir = dir
end

local function buildInstallMenu()
    return {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.textbox("Install Directory", updateInstallDir, install_dir),
        TUI.Components.text(""),
        TUI.Components.option("Begin Installation", function()
            TUI.setQuitEnabled(false)
            BASE_URL = "https://raw.githubusercontent.com/Minater247/CCVim/refs/heads/" .. git_branch .. "/"
            TUI.pushMenu(buildInstallProgressMenu())
            runInstall()
            TUI.setQuitEnabled(true)
            TUI.enableOption(progressBackItem, function()
                TUI.popMenu()
            end)
        end),

        TUI.Components.separator(),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
    }
end
-- #endregion Main install page

-- Root installer menu
local function updateBranch(branchname)
    git_branch = branchname
end

local menu = {
    TUI.Components.info(label),
    TUI.Components.separator(),

    TUI.Components.textbox("Install branch", updateBranch, git_branch),

    TUI.Components.separator(),

    TUI.Components.option("Install CCVIM", function()
        TUI.pushMenu(buildInstallMenu())
    end),
    TUI.Components.option("Add to universal path"),
    TUI.Components.option("Update CCVIM"),

    TUI.Components.separator(),

    TUI.Components.option("Exit", TUI.HaltLoop),
}

TUI.run(menu)