return {
    id = "runtime.installer_upgrade",
    description = "Checks interrupted self-updates and migration from both supported installer generations.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local sourceFile = assert(io.open("vim_installer.lua", "r"))
        local source = sourceFile:read("*a")
        sourceFile:close()

        local baseUrl = "https://raw.githubusercontent.com/Minater247/CCVim/refs/heads/main/"
        local versionUrl = baseUrl .. ".version"

        local function run(files, responses, preferences)
            local requests, writes, pushedMenus, rootMenu = {}, {}, {}, nil
            local restarted = false
            local fsApi = {}

            function fsApi.getDir(path)
                return tostring(path):match("^(.*)/[^/]+$") or ""
            end
            function fsApi.combine(a, b)
                return a == "" and b or a:gsub("/$", "") .. "/" .. b:gsub("^/", "")
            end
            function fsApi.exists(path)
                return files[path] ~= nil
            end
            function fsApi.makeDir() end
            function fsApi.open(path, mode)
                if mode == "r" then
                    if files[path] == nil then return nil, "missing" end
                    return { readAll = function() return files[path] end, close = function() end }
                end

                local chunks = {}
                return {
                    write = function(data) chunks[#chunks + 1] = data end,
                    close = function()
                        files[path] = table.concat(chunks)
                        writes[#writes + 1] = path
                    end,
                }
            end

            local function component(kind)
                return function(str, callback)
                    return { type = kind, str = str, callback = callback }
                end
            end

            local TUI = {
                Components = {
                    info = component("info"),
                    separator = component("separator"),
                    text = component("text"),
                    textbox = component("textbox"),
                    checkbox = function(str, checked, callback)
                        return { type = "checkbox", str = str, checked = checked, callback = callback }
                    end,
                    option = component("option"),
                    disabledOption = component("disabled_option"),
                    messageBox = function() return { type = "messagebox" } end,
                },
                addMessage = function() end,
                clearMessages = function() end,
                enableOption = function() end,
                popMenu = function() end,
                pushMenu = function(menu) pushedMenus[#pushedMenus + 1] = menu end,
                replaceMenu = function() end,
                setQuitEnabled = function() end,
                HaltLoop = function() end,
                run = function(menu) rootMenu = menu end,
            }

            local env = setmetatable({
                arg = { [0] = "/vim/vim_installer.lua" },
                colors = { black = 1, white = 2, gray = 3 },
                fs = fsApi,
                http = {
                    get = function(url)
                        requests[#requests + 1] = url
                        local data
                        if type(responses) == "function" then
                            data = responses(url)
                        else
                            data = responses[url]
                        end
                        if data == nil then return nil, "missing" end
                        return { readAll = function() return data end, close = function() end }
                    end,
                },
                os = {
                    exit = function() error("installer exited", 0) end,
                    pullEvent = function() return "char", "y" end,
                },
                print = function() end,
                term = {
                    clear = function() end,
                    setBackgroundColor = function() end,
                    setCursorPos = function() end,
                    setTextColor = function() end,
                },
                textutils = {
                    serialize = function() return "preferences" end,
                    unserialize = function() return preferences end,
                },
            }, { __index = _G })

            env.dofile = function(path)
                if path == "/vim/instui.lua" then return TUI end
                if path == "/vim/vim_installer.lua" then restarted = true; return end
                error("unexpected dofile: " .. path)
            end

            local chunk = assert(load(source, "@/vim/vim_installer.lua", "t", env))
            local ok, err = pcall(chunk)
            return {
                err = ok and nil or tostring(err),
                files = files,
                requests = requests,
                restarted = restarted,
                rootMenu = rootMenu,
                pushedMenus = pushedMenus,
                writes = writes,
            }
        end

        local responses = {
            [versionUrl] = "0.9\n0.3\n",
            [baseUrl .. "instui.lua"] = "new ui",
            [baseUrl .. "vim_installer.lua"] = "new installer",
        }
        local updated = run({
            ["/vim/.version"] = "0.8\n0.2\n",
            ["/vim/instui.lua"] = "old ui",
            ["/vim/vim_installer.lua"] = "old installer",
        }, responses)
        Assert.eq("self-update restarts", updated.restarted, true)
        Assert.eq("self-update preserves app version", updated.files["/vim/.version"], "0.8\n0.3\n")
        Assert.deep_eq("self-update commit order", updated.writes, {
            "/vim/instui.lua", "/vim/vim_installer.lua", "/vim/.version",
        })

        local interruptedResponses = {}
        for key, value in pairs(responses) do interruptedResponses[key] = value end
        interruptedResponses[baseUrl .. "vim_installer.lua"] = nil
        local interrupted = run({
            ["/vim/.version"] = "0.8\n0.2\n",
            ["/vim/instui.lua"] = "old ui",
            ["/vim/vim_installer.lua"] = "old installer",
        }, interruptedResponses)
        Assert.eq("failed update keeps old version", interrupted.files["/vim/.version"], "0.8\n0.2\n")
        Assert.deep_eq("failed update writes only dependency", interrupted.writes, { "/vim/instui.lua" })

        local currentFiles = {
            ["/vim/.version"] = "0.9\n0.3\n",
            ["/vim/instui.lua"] = "ui",
            ["/vim/vim.lua"] = "app",
            ["/vim/vim_installer.lua"] = "installer",
        }
        local legacy = run(currentFiles, { [versionUrl] = responses[versionUrl] })
        local legacyUpdate
        for i = 1, #legacy.rootMenu do
            if legacy.rootMenu[i].str == "Update CCVIM" then legacyUpdate = legacy.rootMenu[i] end
        end
        Assert.eq("main installer generation can update", legacyUpdate.type, "option")

        currentFiles["/vim/.installer_prefs"] = "preferences"
        local preferences = {
            install_dir = "/vim",
            git_branch = "rewrite-2026",
            doRelease = false,
            colorschemes = {}, syntaxes = {}, ftplugins = {}, indents = {}, helpfiles = {}, keymaps = {},
            install_tutor = false,
            install_spellfiles = false,
        }
        local recent = run(currentFiles, { [versionUrl] = responses[versionUrl] }, preferences)
        local recentUpdate
        for i = 1, #recent.rootMenu do
            if recent.rootMenu[i].str == "Update CCVIM" then recentUpdate = recent.rootMenu[i] end
        end
        recentUpdate.callback()
        Assert.eq("saved branch migrates to main", recent.requests[#recent.requests], baseUrl .. "nvim.idx")
        Assert.truthy("legacy main installer detects 0.3", tonumber("0.3") > tonumber("0.16"))

        local manifestFile = assert(io.open("nvim.idx", "r"))
        local manifest = manifestFile:read("*a")
        manifestFile:close()
        local function responseForFreshInstall(url)
            if url == baseUrl .. "nvim.idx" then return manifest end
            if url:sub(1, #baseUrl) ~= baseUrl then return nil end
            local file = io.open(url:sub(#baseUrl + 1), "rb")
            if not file then return nil end
            local contents = file:read("*a")
            file:close()
            return contents
        end

        local fresh = run({}, responseForFreshInstall)
        local installOption
        for i = 1, #fresh.rootMenu do
            if fresh.rootMenu[i].str == "Install CCVIM" then installOption = fresh.rootMenu[i] end
        end
        installOption.callback()
        local installMenu = fresh.pushedMenus[#fresh.pushedMenus]
        local function findOption(menu, name)
            for i = 1, #menu do
                if menu[i].str == name then return menu[i] end
            end
        end
        findOption(installMenu, "Choose Components").callback()
        local componentsMenu = fresh.pushedMenus[#fresh.pushedMenus]
        local componentMenus = {
            "Colorschemes",
            "Syntax Languages",
            "Filetype Plugins",
            "Indent Languages",
            "Helpfiles",
            "Keymaps",
        }
        for _, name in ipairs(componentMenus) do
            findOption(componentsMenu, name).callback()
            local menu = fresh.pushedMenus[#fresh.pushedMenus]
            Assert.eq(name .. " Select All is first", menu[3].str, "Select All")
            Assert.eq(name .. " Deselect All is second", menu[4].str, "Deselect All")
            if name == "Syntax Languages" then
                Assert.eq("core :syntax off file is hidden", findOption(menu, "nosyntax.vim"), nil)
                Assert.eq("core :syntax manual file is hidden", findOption(menu, "manual.vim"), nil)
            end
            if name == "Colorschemes" then
                menu[3].callback()
                local selectedMenu = fresh.pushedMenus[#fresh.pushedMenus]
                Assert.eq("Select All checks colorschemes", findOption(selectedMenu, "blue.vim").checked, true)
                fresh.pushedMenus[#fresh.pushedMenus][4].callback()
                selectedMenu = fresh.pushedMenus[#fresh.pushedMenus]
                Assert.eq("Deselect All clears colorschemes", findOption(selectedMenu, "blue.vim").checked, false)
            end
        end
        local beginInstall
        for i = 1, #installMenu do
            if installMenu[i].str == "Begin Install / Update" then beginInstall = installMenu[i] end
        end
        beginInstall.callback()

        local requested = {}
        for i = 1, #fresh.requests do requested[fresh.requests[i]] = true end
        local luaHighlights = baseUrl .. "runtime/queries/lua/highlights.scm"
        local vimHighlights = baseUrl .. "runtime/queries/vim/highlights.scm"
        local noSyntax = baseUrl .. "runtime/syntax/nosyntax.vim"
        local manualSyntax = baseUrl .. "runtime/syntax/manual.vim"
        Assert.eq("fresh install includes Lua queries", requested[luaHighlights], true)
        Assert.eq("fresh install includes Tree-sitter query dependencies", requested[vimHighlights], true)
        Assert.eq("fresh install includes :syntax off runtime", requested[noSyntax], true)
        Assert.eq("fresh install includes :syntax manual runtime", requested[manualSyntax], true)

        local lfs = require("lfs")
        local installRoot = ctx.backend.mock.tmp_root() .. "/bare-install"
        assert(lfs.mkdir(installRoot))
        local function writeInstalledFile(path, contents)
            local relative = path:match("^/vim/(.+)$")
            if not relative then return end
            local target = installRoot .. "/" .. relative
            local parent = target:match("^(.*)/[^/]+$")
            local parts = {}
            for part in parent:gmatch("[^/]+") do
                parts[#parts + 1] = part
                local dir = "/" .. table.concat(parts, "/")
                if not lfs.attributes(dir) then assert(lfs.mkdir(dir)) end
            end
            local file = assert(io.open(target, "wb"))
            file:write(contents)
            file:close()
        end
        for path, contents in pairs(fresh.files) do writeInstalledFile(path, contents) end

        local MockEnv = require("vim.tests.test_mocks")
        local quitEvents = {}
        local bare = MockEnv.setup({
            bootstrap_default_editor = false,
            ccvim_path = installRoot,
            no_cache = true,
            on_pull_event = function()
                return table.remove(quitEvents, 1) or { "terminate" }
            end,
        })
        local globals = bare.globals()
        quitEvents = {
            { "key", globals.keys.semiColon, false, true },
            { "key", globals.keys.q },
            { "key", globals.keys.a },
            { "key", globals.keys.enter },
        }
        local function writeSample(path, contents)
            local file = assert(globals.fs.open(path, "w"))
            file.write(contents)
            file.close()
        end
        writeSample("/sample.lua", "local value = table.insert")
        writeSample("/sample.json", '{"value": true}')

        local oldArg = arg
        arg = { [0] = installRoot .. "/nvim.lua", "/sample.lua", "/sample.json" }
        local chunk, loadErr = loadfile(installRoot .. "/nvim.lua")
        Assert.truthy("bare install loads nvim.lua", chunk ~= nil, loadErr)
        local bootOk, bootErr = pcall(chunk)
        arg = oldArg
        if not bootOk then
            bare.cleanup()
            error(bootErr)
        end

        local ScriptSource = bare.loadModule("lib.scriptsource")
        for _, path in ipairs({ "ftplugin.vim", "indent.vim", "filetype.lua", "syntax/syntax.vim" }) do
            local sourceOk, sourceErr = ScriptSource.source_runtime(path)
            if not sourceOk then
                bare.cleanup()
                error(sourceErr)
            end
        end
        local Args = bare.loadModule("lib.args")
        Assert.eq("bare install accepts Lua and JSON files", Args.parse({
            [0] = "nvim", "/sample.lua", "/sample.json",
        }), true)
        Args.load_pending_files()

        local function findBuffer(name)
            for _, buffer in pairs(globals.buffers) do
                if buffer.name == name then return buffer end
            end
        end
        local Options = bare.loadModule("lib.options", { immediate = true })
        local luaBuffer = findBuffer("/sample.lua")
        local jsonBuffer = findBuffer("/sample.json")
        Assert.eq("bare install Lua filetype", Options.get("filetype", nil, luaBuffer, true), "lua")
        Assert.eq("bare install JSON filetype", Options.get("filetype", nil, jsonBuffer, true), "json")
        Assert.eq("bare install JSON syntax", Options.get("syntax", nil, jsonBuffer, true), "json")
        local Treesitter = bare.loadModule("lib.luaapi.treesitter", { immediate = true })
        Assert.truthy("bare install has Lua queries", Treesitter.query.get("lua", "highlights"))
        bare.cleanup()
    end,
}
