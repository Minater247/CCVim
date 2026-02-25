local TUI = require("instui")
assert(TUI)

local label = "CCVIM Installer v0.2"

local BASE_URL
local COMPRESSED_URL = "https://minater247.github.io/CCVim/"
local MANIFEST = "nvim.idx"

local install_dir = "/vim"
local git_branch = "rewrite-2026"

local manifest_tree

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

local function downloadFile(relPath)
    local url = BASE_URL .. relPath
    local localPath = fs.combine(install_dir, relPath)

    local dir = fs.getDir(localPath)
    if dir and dir ~= "" then
        fs.makeDir(dir)
    end

    local data, err

    if doRelease then
        data, err = httpGet(COMPRESSED_URL .. relPath)
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



--#region Components pages
local colorschemes = {}

local function buildColorschemesMenu()
    local tui = {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
        
        TUI.Components.separator(),
    }

    local color_names = {}
    for k, v in pairs(manifest_tree.runtime.colors) do
        if v == true then
            table.insert(color_names, k)
        end
    end
    table.sort(color_names)
    for _, k in ipairs(color_names) do
        if k:match("^[%w_%-]+%.vim$") and k ~= "default.vim" then
            table.insert(tui, TUI.Components.checkbox(k, colorschemes[k], function(newval)
                colorschemes[k] = newval
            end))
        end
    end

    return tui
end

local syntaxes = {
    ["lua.vim"] = true,
    ["vim.vim"] = true,
    ["help.vim"] = true,
    ["json.vim"] = true,
    ["tutor.vim"] = true,
    ["markdown.vim"] = true,
}

local function buildSyntaxesMenu()
    local tui = {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
        
        TUI.Components.separator(),
    }
    
    local syntax_names = {}
    for k, v in pairs(manifest_tree.runtime.syntax) do
        if v == true then
            table.insert(syntax_names, k)
        end
    end
    table.sort(syntax_names)
    for _, k in ipairs(syntax_names) do
        if k:match("^[%w_%-]+%.vim$") and k ~= "syntax.vim" and k ~= "synload.vim" then
            table.insert(tui, TUI.Components.checkbox(k, syntaxes[k], function(newval)
                syntaxes[k] = newval
            end))
        end
    end

    return tui
end

local ftplugins = {
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
    local tui = {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
        
        TUI.Components.separator(),
    }

    local ftplugin_names = {}
    for k, v in pairs(manifest_tree.runtime.ftplugin) do
        if v == true then
            table.insert(ftplugin_names, k)
        end
    end
    table.sort(ftplugin_names)
    for _, k in ipairs(ftplugin_names) do
        if (k:match("^[%w_%-]+%.vim$") or k:match("^[%w_%-]+%.lua$")) and k ~= "README.txt" then
            table.insert(tui, TUI.Components.checkbox(k, ftplugins[k], function(newval)
                ftplugins[k] = newval
            end))
        end
    end

    return tui
end

local indents = {
    ["lua.vim"] = true,
    ["vim.vim"] = true,
    ["json.vim"] = true,
}

local function buildIndentsMenu()
    local tui = {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
        
        TUI.Components.separator(),
    }

    local indents_names = {}
    for k, v in pairs(manifest_tree.runtime.indent) do
        if v == true then
            table.insert(indents_names, k)
        end
    end
    table.sort(indents_names)
    for _, k in ipairs(indents_names) do
        if (k:match("^[%w_%-]+%.vim$") or k:match("^[%w_%-]+%.lua$")) and k ~= "README.txt" and k ~= "Makefile" then
            table.insert(tui, TUI.Components.checkbox(k, indents[k], function(newval)
                indents[k] = newval
            end))
        end
    end

    return tui
end

-- These are either not applicable or unimplemented
local helpfiles = {
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
    local tui = {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
        
        TUI.Components.separator(),

        TUI.Components.option("Enable All", function()
            for k, _ in pairs(helpfiles) do
                helpfiles[k] = true
            end
            TUI.popMenu()
            TUI.pushMenu(buildHelpfilesMenu())
        end),
        TUI.Components.option("Disable All (breaks :help)", function()
            for k, _ in pairs(helpfiles) do
                helpfiles[k] = false
            end
            TUI.popMenu()
            TUI.pushMenu(buildHelpfilesMenu())
        end),
        
        TUI.Components.separator(),
    }

    local helpfile_names = {}
    for k, v in pairs(manifest_tree.runtime.doc) do
        if v == true then
            table.insert(helpfile_names, k)
        end
    end
    table.sort(helpfile_names)
    for _, k in ipairs(helpfile_names) do
        table.insert(tui, TUI.Components.checkbox(k, helpfiles[k], function(newval)
            helpfiles[k] = newval
        end))
    end

    return tui
end

local keymaps = {}

local function buildKeymapsMenu()
    local tui = {
        TUI.Components.info(label),
        
        TUI.Components.separator(),

        TUI.Components.text("These may or may not work. They have not been tested."),

        TUI.Components.option("Back", function()
            TUI.popMenu()
        end),
        
        TUI.Components.separator(),
    }

    local keymap_names = {}
    for k, v in pairs(manifest_tree.runtime.keymap) do
        if v == true then
            table.insert(keymap_names, k)
        end
    end
    table.sort(keymap_names)
    for _, k in ipairs(keymap_names) do
        table.insert(tui, TUI.Components.checkbox(k, keymaps[k], function(newval)
            keymaps[k] = newval
        end))
    end

    return tui
end

-- Unfortunately only ASCII is supported by ComputerCraft so ja/zh won't work
local install_tutor = true

local install_spellfiles = false

local function buildComponentsMenu()
    if not manifest_tree then
        local text, err = httpGet(BASE_URL .. MANIFEST)
        if not text then
            return {
                TUI.Components.text("Failed to download manifest: "),
                TUI.Components.info(tostring(err))
            }
        end

        manifest_tree = parseManifest(text)

        for k, v in pairs(manifest_tree.runtime.doc) do
            if v == true and helpfiles[k] == nil then
                helpfiles[k] = true
            end
        end
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
    if not manifest_tree then
        TUI.addMessage(installerBox, "Downloading manifest from:")
        TUI.addMessage(installerBox, BASE_URL .. MANIFEST)

        local text, err = httpGet(BASE_URL .. MANIFEST)
        if not text then
            TUI.addMessage(installerBox, "ERROR: Could not download manifest:")
            TUI.addMessage(installerBox, "        " .. tostring(err))
            return
        end

        manifest_tree = parseManifest(text)
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

    local base_count = 1 + countFiles(manifest_tree.lib) + countFiles(manifest_tree.layout)
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
    state.done = state.done + 1
    TUI.addMessage(installerBox, ("[%d/%d] %s"):format(state.done, base_count, "nvim.lua"))
    local ok, err = downloadFile("nvim.lua")
    if not ok then
        return failure(err)
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
    syntaxes["query.lua"] = true
    if syntaxes["tutor.vim"] then
        syntaxes["tutor.lua"] = true
    end
    if syntaxes["vim.vim"] then
        syntaxes["vim/generated.vim"] = true
    end
    -- Shared
    if syntaxes["deb822sources.vim"] or syntaxes["debchangelog.vim"] or syntaxes["debsources.vim"] or syntaxes["debversions.vim"] then
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
    -- single files
    for _, f in ipairs(core_single_files) do
        core_state.done = core_state.done + 1
        TUI.addMessage(installerBox, ("[%d/%d] %s"):format(core_state.done, core_total, f))
        ok, err = downloadFile(f)
        if not ok then return failure(err) end
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
    BASE_URL = "https://raw.githubusercontent.com/Minater247/CCVim/refs/heads/" .. git_branch .. "/"
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
        TUI.Components.option("Begin Installation", function()
            TUI.setQuitEnabled(false)
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