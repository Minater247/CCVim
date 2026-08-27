local DEFAULT_BRANCH = "main"
local INSTALLER_VERSION = "0.3"
local COMPRESSED_URL = "https://minater247.github.io/CCVim/"
local MANIFEST = "nvim.idx"
local VERSION_FILE = ".version"
local PREFS_FILE = ".installer_prefs"
local INSTALLER_FILES = {
    "instui.lua",
    "vim_installer.lua",
    VERSION_FILE,
}

local label = "CCVIM Installer v" .. INSTALLER_VERSION
local install_dir = "/vim"
local git_branch = DEFAULT_BRANCH
local manifest_tree
local manifest_branch
local colorschemes
local syntaxes
local ftplugins
local indents
local helpfiles
local keymaps
local install_tutor
local install_spellfiles
local updateBranch
local openInstallMenu
local runSavedUpdate

local function httpGet(url)
    local res, err = http.get(url)
    if not res then
        return nil, err or "http.get failed"
    end

    local data = res.readAll()
    res.close()
    return data
end

local function trim(str)
    return (tostring(str):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function readFile(path, mode)
    local fh, err = fs.open(path, mode or "r")
    if not fh then
        return nil, err
    end

    local data = fh.readAll()
    fh.close()
    return data
end

local function writeFile(path, data, mode)
    local dir = fs.getDir(path)
    if dir ~= "" then
        fs.makeDir(dir)
    end

    local fh, err = fs.open(path, mode or "w")
    if not fh then
        return false, err
    end

    fh.write(data)
    fh.close()
    return true
end

local function baseUrl(branch)
    return "https://raw.githubusercontent.com/Minater247/CCVim/refs/heads/" .. branch .. "/"
end

local function parseVersionFile(text)
    local lines = {}
    for rawLine in tostring(text or ""):gmatch("[^\r\n]+") do
        lines[#lines + 1] = trim(rawLine)
    end

    return lines[1], lines[2] or lines[1]
end

local function resolveInstallerFile(relPath)
    local source = debug.getinfo(1, "S").source
    local program = source:sub(1, 1) == "@" and source:sub(2) or ((arg and arg[0]) or "")
    local dir = fs.getDir(program)
    if dir and dir ~= "" then
        return fs.combine(dir, relPath)
    end

    return relPath
end

local function readLocalInstallerVersion()
    local text = readFile(resolveInstallerFile(VERSION_FILE))
    if text then
        local _, installerVersion = parseVersionFile(text)
        if installerVersion ~= "" then
            return installerVersion
        end
    end

    return INSTALLER_VERSION
end

local function downloadInstallerFile(relPath, data)
    local fileData = data
    if not fileData then
        local err
        fileData, err = httpGet(baseUrl(DEFAULT_BRANCH) .. relPath)
        if not fileData then
            return false, ("failed to GET %s: %s"):format(relPath, tostring(err))
        end
    end

    local localPath = resolveInstallerFile(relPath)
    local ok, err = writeFile(localPath, fileData)
    if not ok then
        return false, ("failed to write %s: %s"):format(localPath, tostring(err))
    end

    return true
end

local function pauseForKey(messageLines)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    for i = 1, #messageLines do
        print(messageLines[i])
    end

    while true do
        local event = os.pullEvent()
        if event == "key" or event == "char" then
            return
        end
    end
end

local function promptInstallerUpdate(localVersion, remoteVersion)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)

    print(label)
    print("")
    print("A newer installer is available.")
    print("Installed: " .. localVersion)
    print("Latest:    " .. remoteVersion)
    print("")
    print("Press Y to update or Q to quit.")

    while true do
        local event, param = os.pullEvent()
        if event == "char" then
            local ch = param:lower()
            if ch == "y" then
                return true
            end
            if ch == "q" then
                return false
            end
        end
    end
end

local function restartInstaller()
    dofile(resolveInstallerFile("vim_installer.lua"))
    os.exit()
end

local function ensureLatestInstaller()
    local versionText, err = httpGet(baseUrl(DEFAULT_BRANCH) .. VERSION_FILE)
    if not versionText then
        pauseForKey({
            label,
            "",
            "Could not check for installer updates.",
            tostring(err),
            "",
            "Press any key to continue.",
        })
        return
    end

    local remoteAppVersion, remoteInstallerVersion = parseVersionFile(versionText)
    local localInstallerVersion = readLocalInstallerVersion()
    local remoteNumber = tonumber(remoteInstallerVersion)
    local localNumber = tonumber(localInstallerVersion)
    if remoteInstallerVersion == localInstallerVersion
        or (remoteNumber and localNumber and remoteNumber <= localNumber)
    then
        return
    end

    if not promptInstallerUpdate(localInstallerVersion, remoteInstallerVersion) then
        os.exit()
    end

    local localVersionText = readFile(resolveInstallerFile(VERSION_FILE))
    local localAppVersion = localVersionText and parseVersionFile(localVersionText)
    if not localAppVersion or localAppVersion == "" then localAppVersion = remoteAppVersion end
    local updatedVersionText = localAppVersion .. "\n" .. remoteInstallerVersion .. "\n"

    for i = 1, #INSTALLER_FILES do
        local relPath = INSTALLER_FILES[i]
        local ok, updateErr = downloadInstallerFile(
            relPath,
            relPath == VERSION_FILE and updatedVersionText or nil
        )
        if not ok then
            error(updateErr, 0)
        end
    end

    restartInstaller()
end

local function ensureInstallerDependency(relPath)
    local localPath = resolveInstallerFile(relPath)
    if fs.exists(localPath) then
        return localPath
    end

    local data, err = httpGet(baseUrl(DEFAULT_BRANCH) .. relPath)
    if not data then
        error(("failed to download %s: %s"):format(relPath, tostring(err)))
    end

    local ok, ferr = writeFile(localPath, data)
    if not ok then
        error(("failed to open %s for writing: %s"):format(localPath, tostring(ferr)))
    end

    return localPath
end

ensureLatestInstaller()

local TUI = assert(dofile(ensureInstallerDependency("instui.lua")))
assert(TUI)

local function parseManifest(text)
    --   directory = table
    --   file      = true
    local root = {}

    local nodes = { root }

    for rawLine in text:gmatch("[^\r\n]+") do
        if rawLine ~= "" then
            local depth = 0
            while rawLine:sub(depth + 1, depth + 1) == "\t" do
                depth = depth + 1
            end

            local line = rawLine:sub(depth + 1)
            local isDir = line:sub(-1) == "/"
            local name = isDir and line:sub(1, -2) or line

            for i = #nodes, depth + 2, -1 do
                nodes[i] = nil
            end

            local parent = nodes[depth + 1] or root

            if isDir then
                local child = parent[name]
                if type(child) ~= "table" then
                    child = {}
                    parent[name] = child
                end
                nodes[depth + 2] = child
            else
                parent[name] = true
            end
        end
    end

    return root
end

local doRelease = true
local releaseBranch
local releaseMatches

local function useRelease()
    if not doRelease or git_branch ~= DEFAULT_BRANCH then return false end
    if releaseBranch ~= git_branch then
        local releaseVersion = httpGet(COMPRESSED_URL .. VERSION_FILE)
        local branchVersion = httpGet(baseUrl(git_branch) .. VERSION_FILE)
        releaseBranch = git_branch
        releaseMatches = releaseVersion and branchVersion and trim(releaseVersion) == trim(branchVersion)
    end
    return releaseMatches
end

local function downloadFile(relPath)
    local url = baseUrl(git_branch) .. relPath
    local localPath = fs.combine(install_dir, relPath)

    local dir = fs.getDir(localPath)
    if dir and dir ~= "" then
        fs.makeDir(dir)
    end

    local data, err

    if useRelease() then
        data = httpGet(COMPRESSED_URL .. relPath)
    end
    
    if not data then
        data, err = httpGet(url)
        if not data then
            return false, ("failed to GET %s: %s"):format(url, tostring(err))
        end
    end

    local fh, ferr = fs.open(localPath, "wb")
    if not fh then
        return false, ("failed to open %s: %s"):format(localPath, tostring(ferr))
    end
    fh.write(data)
    fh.close()

    return true
end

local function copySelectionTable(source)
    local copy = {}
    for k, v in pairs(source) do
        copy[k] = not not v
    end
    return copy
end

local function replaceSelectionTable(target, source)
    for k in pairs(target) do
        target[k] = nil
    end
    for k, v in pairs(source) do
        target[k] = not not v
    end
end

local function savedPreferencesPath()
    return resolveInstallerFile(PREFS_FILE)
end

local function hasSavedPreferences()
    return fs.exists(savedPreferencesPath())
end

local function capturePreferences()
    return {
        install_dir = install_dir,
        git_branch = git_branch,
        doRelease = doRelease,
        colorschemes = copySelectionTable(colorschemes),
        syntaxes = copySelectionTable(syntaxes),
        ftplugins = copySelectionTable(ftplugins),
        indents = copySelectionTable(indents),
        helpfiles = copySelectionTable(helpfiles),
        keymaps = copySelectionTable(keymaps),
        install_tutor = install_tutor,
        install_spellfiles = install_spellfiles,
    }
end

local function applyPreferences(preferences)
    install_dir = preferences.install_dir
    git_branch = preferences.git_branch == "rewrite-2026" and DEFAULT_BRANCH or preferences.git_branch
    doRelease = preferences.doRelease
    replaceSelectionTable(colorschemes, preferences.colorschemes)
    replaceSelectionTable(syntaxes, preferences.syntaxes)
    replaceSelectionTable(ftplugins, preferences.ftplugins)
    replaceSelectionTable(indents, preferences.indents)
    replaceSelectionTable(helpfiles, preferences.helpfiles)
    replaceSelectionTable(keymaps, preferences.keymaps)
    install_tutor = preferences.install_tutor
    install_spellfiles = preferences.install_spellfiles
    manifest_tree = nil
    manifest_branch = nil
end

local function savePreferences()
    local ok, err = writeFile(savedPreferencesPath(), textutils.serialize(capturePreferences()))
    if not ok then
        return false, ("failed to save installer preferences: %s"):format(tostring(err))
    end
    return true
end

local function loadPreferences()
    local text, err = readFile(savedPreferencesPath())
    if not text then
        return nil, ("failed to read saved installer preferences: %s"):format(tostring(err))
    end

    local preferences = textutils.unserialize(text)
    if type(preferences) ~= "table" then
        return nil, "failed to parse saved installer preferences"
    end

    applyPreferences(preferences)
    return preferences
end

local function ensureManifestLoaded()
    if manifest_tree and manifest_branch == git_branch then
        return true
    end

    local text, err = httpGet(baseUrl(git_branch) .. MANIFEST)
    if not text then
        return false, err
    end

    manifest_tree = parseManifest(text)
    manifest_branch = git_branch

    for k, v in pairs(manifest_tree.runtime.doc) do
        if v == true and helpfiles[k] == nil then
            helpfiles[k] = true
        end
    end

    return true
end



--#region Components pages
colorschemes = {}

local function selectionMenuHeader(selection, names, build)
    return {
        TUI.Components.info(label),
        TUI.Components.separator(),
        TUI.Components.option("Select All", function()
            for _, k in ipairs(names) do selection[k] = true end
            TUI.popMenu()
            TUI.pushMenu(build())
        end),
        TUI.Components.option("Deselect All", function()
            for k in pairs(selection) do selection[k] = false end
            for _, k in ipairs(names) do selection[k] = false end
            TUI.popMenu()
            TUI.pushMenu(build())
        end),
        TUI.Components.separator(),
        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
        TUI.Components.separator(),
    }
end

local function buildColorschemesMenu()
    local color_names = {}
    for k, v in pairs(manifest_tree.runtime.colors) do
        if v == true and k:match("^[%w_%-]+%.vim$") and k ~= "default.vim" then
            table.insert(color_names, k)
        end
    end
    table.sort(color_names)
    local tui = selectionMenuHeader(colorschemes, color_names, buildColorschemesMenu)
    for _, k in ipairs(color_names) do
        table.insert(tui, TUI.Components.checkbox(k, colorschemes[k], function(newval)
            colorschemes[k] = newval
        end))
    end

    return tui
end

syntaxes = {
    ["lua.vim"] = true,
    ["vim.vim"] = true,
    ["help.vim"] = true,
    ["json.vim"] = true,
    ["tutor.vim"] = true,
    ["markdown.vim"] = true,
}

local function buildSyntaxesMenu()
    local syntax_names = {}
    for k, v in pairs(manifest_tree.runtime.syntax) do
        if v == true and k:match("^[%w_%-]+%.vim$")
            and k ~= "syntax.vim" and k ~= "synload.vim"
            and k ~= "nosyntax.vim" and k ~= "manual.vim"
        then
            table.insert(syntax_names, k)
        end
    end
    table.sort(syntax_names)
    local tui = selectionMenuHeader(syntaxes, syntax_names, buildSyntaxesMenu)
    for _, k in ipairs(syntax_names) do
        table.insert(tui, TUI.Components.checkbox(k, syntaxes[k], function(newval)
            syntaxes[k] = newval
        end))
    end

    return tui
end

ftplugins = {
    ["lua.lua"] = true,
    ["lua.vim"] = true,
    ["vim.vim"] = true,
    ["help.lua"] = true,
    ["help.vim"] = true,
    ["json.vim"] = true,
    ["tutor.vim"] = true,
    ["markdown.lua"] = true,
    ["markdown.vim"] = true,
}

local function buildFtpluginsMenu()
    local ftplugin_names = {}
    for k, v in pairs(manifest_tree.runtime.ftplugin) do
        if v == true and (k:match("^[%w_%-]+%.vim$") or k:match("^[%w_%-]+%.lua$")) then
            table.insert(ftplugin_names, k)
        end
    end
    table.sort(ftplugin_names)
    local tui = selectionMenuHeader(ftplugins, ftplugin_names, buildFtpluginsMenu)
    for _, k in ipairs(ftplugin_names) do
        table.insert(tui, TUI.Components.checkbox(k, ftplugins[k], function(newval)
            ftplugins[k] = newval
        end))
    end

    return tui
end

indents = {
    ["lua.vim"] = true,
    ["vim.vim"] = true,
    ["json.vim"] = true,
}

local function buildIndentsMenu()
    local indents_names = {}
    for k, v in pairs(manifest_tree.runtime.indent) do
        if v == true and (k:match("^[%w_%-]+%.vim$") or k:match("^[%w_%-]+%.lua$")) then
            table.insert(indents_names, k)
        end
    end
    table.sort(indents_names)
    local tui = selectionMenuHeader(indents, indents_names, buildIndentsMenu)
    for _, k in ipairs(indents_names) do
        table.insert(tui, TUI.Components.checkbox(k, indents[k], function(newval)
            indents[k] = newval
        end))
    end

    return tui
end

-- These are either not applicable or unimplemented
helpfiles = {
    ["news-0.10.txt"] = false,
    ["news.txt"] = false,
    ["news-0.9.txt"] = false,
    ["ft_ada.txt"] = false,
    ["ft_hare.txt"] = false,
    ["ft_ps1.txt"] = false,
    ["ft_raku.txt"] = false,
    ["ft_rust.txt"] = false,
    ["ft_sql.txt"] = false,
    ["dev_arch.txt"] = false,
    ["dev_style.txt"] = false,
    ["dev_tools.txt"] = false,
    ["dev_vimpatch.txt"] = false,
    ["develop.txt"] = false,
    ["diff.txt"] = false,
    ["if_perl.txt"] = false,
    ["if_pyth.txt"] = false,
    ["if_ruby.txt"] = false,
    ["support.txt"] = false,
    ["terminal.txt"] = false,
    ["undo.txt"] = false,
    ["treesitter.txt"] = false,
    ["testing.txt"] = false,
    ["vietnamese.txt"] = false,
    ["arabic.txt"] = false,
}

local function buildHelpfilesMenu()
    local helpfile_names = {}
    for k, v in pairs(manifest_tree.runtime.doc) do
        if v == true then
            table.insert(helpfile_names, k)
        end
    end
    table.sort(helpfile_names)
    local tui = selectionMenuHeader(helpfiles, helpfile_names, buildHelpfilesMenu)
    for _, k in ipairs(helpfile_names) do
        table.insert(tui, TUI.Components.checkbox(k, helpfiles[k], function(newval)
            helpfiles[k] = newval
        end))
    end

    return tui
end

keymaps = {}

local function buildKeymapsMenu()
    local keymap_names = {}
    for k, v in pairs(manifest_tree.runtime.keymap) do
        if v == true then
            table.insert(keymap_names, k)
        end
    end
    table.sort(keymap_names)
    local tui = selectionMenuHeader(keymaps, keymap_names, buildKeymapsMenu)
    table.insert(tui, TUI.Components.text("These may or may not work. They have not been tested."))
    table.insert(tui, TUI.Components.separator())
    for _, k in ipairs(keymap_names) do
        table.insert(tui, TUI.Components.checkbox(k, keymaps[k], function(newval)
            keymaps[k] = newval
        end))
    end

    return tui
end

-- Unfortunately only ASCII is supported by ComputerCraft so ja/zh won't work
install_tutor = true

install_spellfiles = false

local function buildComponentsMenu()
    local ok, err = ensureManifestLoaded()
    if not ok then
        return {
            TUI.Components.text("Failed to download manifest:"),
            TUI.Components.info(tostring(err))
        }
    end

    return {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.option("Colorschemes", function()
            TUI.pushMenu(buildColorschemesMenu())
        end),
        TUI.Components.option("Syntax Languages", function()
            TUI.pushMenu(buildSyntaxesMenu())
        end),
        TUI.Components.option("Filetype Plugins", function()
            TUI.pushMenu(buildFtpluginsMenu())
        end),
        TUI.Components.option("Indent Languages", function()
            TUI.pushMenu(buildIndentsMenu())
        end),
        TUI.Components.option("Helpfiles", function()
            TUI.pushMenu(buildHelpfilesMenu())
        end),
        TUI.Components.option("Keymaps", function()
            TUI.pushMenu(buildKeymapsMenu())
        end),
        TUI.Components.checkbox("Tutor Files", install_tutor, function(newval)
            install_tutor = newval
        end),
        TUI.Components.checkbox("Spellcheck Files", install_spellfiles, function(newval)
            install_spellfiles = newval
        end),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end)
    }
end
--#endregion Components pages

-- #region Install progress page
local installerBox = TUI.Components.messageBox{
    fill = true,
    minHeight = 3,
    color = colors.white,
    bgColor = colors.gray
}

local progressBackItem

local function buildRootMenu()
    local menu = {
        TUI.Components.info(label),
        TUI.Components.separator(),

        TUI.Components.textbox("Install branch", updateBranch, git_branch),

        TUI.Components.separator(),

        TUI.Components.option("Install CCVIM", openInstallMenu),
    }

    if hasSavedPreferences() or fs.exists(fs.combine(install_dir, "vim.lua")) then
        menu[#menu + 1] = TUI.Components.option("Update CCVIM", runSavedUpdate)
    else
        menu[#menu + 1] = TUI.Components.disabledOption("Update CCVIM")
    end

    menu[#menu + 1] = TUI.Components.disabledOption("Add to universal path")
    menu[#menu + 1] = TUI.Components.separator()
    menu[#menu + 1] = TUI.Components.option("Exit", TUI.HaltLoop)

    return menu
end

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
    if not manifest_tree or manifest_branch ~= git_branch then
        TUI.addMessage(installerBox, "Downloading manifest from:")
        TUI.addMessage(installerBox, baseUrl(git_branch) .. MANIFEST)

        local ok, err = ensureManifestLoaded()
        if not ok then
            TUI.addMessage(installerBox, "ERROR: Could not download manifest:")
            TUI.addMessage(installerBox, "        " .. tostring(err))
            return
        end
    end
    TUI.addMessage(installerBox, "Manifest downloaded. Walking files...")
    
    local function countFiles(entry)
        local n = 0
        for _, v in pairs(entry) do
            if v == true then
                n = n + 1
            elseif type(v) == "table" then
                n = n + countFiles(v)
            end
        end
        return n
    end

    local root_files = {
        "nvim.lua",
        "vim.lua",
    }

    local base_count = #root_files + countFiles(manifest_tree.lib) + countFiles(manifest_tree.layout)
    TUI.addMessage(installerBox, ("Core runtime: %d files to install"):format(base_count))

    local function downwalk(entry, parents, state, total)
        for k, v in pairs(entry) do
            if v == true then
                state.done = state.done + 1

                local file
                if #parents > 0 then
                    file = table.concat(parents, "/") .. "/" .. k
                else
                    file = k
                end

                TUI.addMessage(installerBox, ("[%d/%d] %s"):format(state.done, total, file))

                local ok, e = downloadFile(file)
                if not ok then
                    return false, ("failed to download %s: %s"):format(file, tostring(e))
                end

            elseif type(v) == "table" then
                parents[#parents + 1] = k
                local ok, err = downwalk(v, parents, state, total)
                parents[#parents] = nil
                if not ok then
                    return false, err
                end
            end
        end

        return true
    end

    local function failure(err)
        TUI.addMessage(installerBox, "  ERROR: " .. tostring(err))
        TUI.addMessage(installerBox, "Installation aborted.")
    end

    local state = { done = 0 }
    local ok, err
    for i = 1, #root_files do
        local file = root_files[i]
        state.done = state.done + 1
        TUI.addMessage(installerBox, ("[%d/%d] %s"):format(state.done, base_count, file))
        ok, err = downloadFile(file)
        if not ok then
            return failure(err)
        end
    end
    ok, err = downwalk(manifest_tree.lib, { "lib" }, state, base_count)
    if not ok then
        return failure(err)
    end
    ok, err = downwalk(manifest_tree.layout, { "layout" }, state, base_count)
    if not ok then
        return failure(err)
    end

    TUI.addMessage(installerBox, "Downloading colorscheme files...")
    local colorschemecnt = 0
    colorschemes["default.vim"] = true
    colorschemes["vim.lua"] = true
    for _, v in pairs(colorschemes) do
        if v then
            colorschemecnt = colorschemecnt + 1
        end
    end
    done = 0
    for k, v in pairs(colorschemes) do
        if v then
            done = done + 1
            TUI.addMessage(installerBox, ("[%d/%d] %s"):format(done, colorschemecnt, k))
            ok, err = downloadFile("runtime/colors/" .. k)
            if not ok then
                return failure(err)
            end
        end
    end

    TUI.addMessage(installerBox, "Downloading syntax runtime files...")
    local syntaxcnt = 0
    syntaxes["syntax.vim"] = true
    syntaxes["synload.vim"] = true
    syntaxes["nosyntax.vim"] = true
    syntaxes["manual.vim"] = true
    syntaxes["query.lua"] = true
    if syntaxes["tutor.vim"] then
        syntaxes["tutor.lua"] = true
    end
    if syntaxes["vim.vim"] then
        syntaxes["vim/generated.vim"] = true
    end
    -- Shared
    if
        syntaxes["deb822sources.vim"]
        or syntaxes["debchangelog.vim"]
        or syntaxes["debsources.vim"]
        or syntaxes["debversions.vim"]
    then
            
        syntaxes["shared/debversions.vim"] = true
    end
    if syntaxes["hgcommit.vim"] then
        syntaxes["shared/hgcommitDiff.vim"] = true
    end
    if syntaxes["typescript.vim"] or syntaxes["typescriptreact.vim"] then
        syntaxes["shared/typescriptcommon.vim"] = true
    end
    -- modula2
    if syntaxes["modula2.vim"] then
        syntaxes["modula2/opt/iso.vim"] = true
        syntaxes["modula2/opt/pim.vim"] = true
        syntaxes["modula2/opt/r10.vim"] = true
    end
    -- actual loop
    for _, v in pairs(syntaxes) do
        if v then
            syntaxcnt = syntaxcnt + 1
        end
    end
    done = 0
    for k, v in pairs(syntaxes) do
        if v then
            done = done + 1
            TUI.addMessage(installerBox, ("[%d/%d] %s"):format(done, syntaxcnt, k))
            ok, err = downloadFile("runtime/syntax/" .. k)
            if not ok then
                return failure(err)
            end
        end
    end

    TUI.addMessage(installerBox, "Downloading filetype runtime files...")
    local ftplugincnt = 0
    for _, v in pairs(ftplugins) do
        if v then
            ftplugincnt = ftplugincnt + 1
        end
    end
    done = 0
    for k, v in pairs(ftplugins) do
        if v then
            done = done + 1
            TUI.addMessage(installerBox, ("[%d/%d] %s"):format(done, ftplugincnt, k))
            ok, err = downloadFile("runtime/ftplugin/" .. k)
            if not ok then
                return failure(err)
            end
        end
    end

    if install_tutor then
        TUI.addMessage(installerBox, "Downloading tutor files...")

        ok, err = downloadFile("runtime/tutor/vimtutor")
        if not ok then return failure(err) end
        ok, err = downloadFile("runtime/tutor/tutor.tutor")
        if not ok then return failure(err) end
        ok, err = downloadFile("runtime/tutor/tutor.tutor.json")
        if not ok then return failure(err) end
        local tutor_total = countFiles(manifest_tree.runtime.tutor.en)
        if tutor_total > 0 then
            local tutor_state = { done = 0 }
            ok, err = downwalk(manifest_tree.runtime.tutor.en, {"runtime", "tutor", "en"}, tutor_state, tutor_total)
            if not ok then return failure(err) end
        end
    end

    if install_spellfiles then
        TUI.addMessage(installerBox, "Downloading spellcheck files...")

        ok, err = downloadFile("runtime/spll/cleanadd.vim")
        if not ok then return failure(err) end
        ok, err = downloadFile("runtime/spell/en.utf-8.spl")
        if not ok then return failure(err) end
    end

    TUI.addMessage(installerBox, "Downloading keymaps...")
    local keymapcnt = 0
    for _, v in pairs(keymaps) do
        if v then
            keymapcnt = keymapcnt + 1
        end
    end
    done = 0
    for k, v in pairs(keymaps) do
        if v then
            done = done + 1
            TUI.addMessage(installerBox, ("[%d/%d] %s"):format(done, keymapcnt, k))
            ok, err = downloadFile("runtime/keymaps/" .. k)
            if not ok then
                return failure(err)
            end
        end
    end
    
    TUI.addMessage(installerBox, "Downloading core runtime files...")
    local core_entries = {
        manifest_tree.runtime.autoload,
        manifest_tree.runtime.lua,
        manifest_tree.runtime.pack,
        manifest_tree.runtime.plugin,
        manifest_tree.runtime.queries,
    }
    local core_single_files = {
        "runtime/example_init.lua",
        "runtime/filetype.lua",
        "runtime/filetype.vim",
        "runtime/ftoff.vim",
        "runtime/ftplugin.vim",
        "runtime/ftplugof.vim",
        "runtime/indent.vim",
        "runtime/indoff.vim",
        "runtime/optwin.vim",
    }

    local core_total = 0
    for _, e in ipairs(core_entries) do
        core_total = core_total + countFiles(e)
    end
    core_total = core_total + #core_single_files

    local core_state = { done = 0 }
    -- walk the directory groups
    ok, err = downwalk(manifest_tree.runtime.autoload, {"runtime", "autoload"}, core_state, core_total)
    if not ok then return failure(err) end
    ok, err = downwalk(manifest_tree.runtime.lua, {"runtime", "lua"}, core_state, core_total)
    if not ok then return failure(err) end
    ok, err = downwalk(manifest_tree.runtime.pack, {"runtime", "pack"}, core_state, core_total)
    if not ok then return failure(err) end
    ok, err = downwalk(manifest_tree.runtime.plugin, {"runtime", "plugin"}, core_state, core_total)
    if not ok then return failure(err) end
    ok, err = downwalk(manifest_tree.runtime.queries, {"runtime", "queries"}, core_state, core_total)
    if not ok then return failure(err) end
    -- single files
    for _, f in ipairs(core_single_files) do
        core_state.done = core_state.done + 1
        TUI.addMessage(installerBox, ("[%d/%d] %s"):format(core_state.done, core_total, f))
        ok, err = downloadFile(f)
        if not ok then return failure(err) end
    end

    TUI.addMessage(installerBox, "Downloading version metadata...")
    local metadata_files = {
        ".version",
    }
    for i, f in ipairs(metadata_files) do
        TUI.addMessage(installerBox, ("[%d/%d] %s"):format(i, #metadata_files, f))
        ok, err = downloadFile(f)
        if not ok then return failure(err) end
    end


    TUI.addMessage(installerBox, "All files downloaded successfully.")
    local saved, saveErr = savePreferences()
    if not saved then
        TUI.addMessage(installerBox, "ERROR: " .. tostring(saveErr))
        TUI.addMessage(installerBox, "The update option will remain unavailable.")
        return
    end
    TUI.replaceMenu(1, buildRootMenu())
    TUI.addMessage(installerBox, "Saved installer preferences.")
    TUI.addMessage(installerBox, "Installation complete.")
end
-- #endregion Install progress page

-- #region Main install page
local function updateInstallDir(dir)
    install_dir = dir
end

local function beginInstallFlow()
    TUI.setQuitEnabled(false)
    TUI.pushMenu(buildInstallProgressMenu())
    runInstall()
    TUI.setQuitEnabled(true)
    TUI.enableOption(progressBackItem, function()
        TUI.popMenu()
    end)
end

local function buildInstallMenu()
    return {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.textbox("Install Directory", updateInstallDir, install_dir),
        TUI.Components.option("Choose Components", function()
            TUI.pushMenu(buildComponentsMenu())
        end),
        TUI.Components.text(""),
        TUI.Components.checkbox("Install compressed (Release)", doRelease, function(newval)
            doRelease = newval
        end),
        TUI.Components.option("Begin Install / Update", beginInstallFlow),

        TUI.Components.separator(),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
    }
end
-- #endregion Main install page

-- Root installer menu
function updateBranch(branchname)
    git_branch = branchname
end

function openInstallMenu()
    TUI.pushMenu(buildInstallMenu())
end

function runSavedUpdate()
    if hasSavedPreferences() then
        local _, err = loadPreferences()
        if err then
            TUI.pushMenu({
                TUI.Components.info(label),
                TUI.Components.separator(),
                TUI.Components.text("Failed to load saved update preferences."),
                TUI.Components.info(tostring(err)),
                TUI.Components.separator(),
                TUI.Components.option("Back", function()
                    TUI.popMenu()
                end),
            })
            return
        end
    end

    beginInstallFlow()
end

TUI.run(buildRootMenu())
