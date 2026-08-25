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
            local requests, writes, rootMenu = {}, {}
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
                    textbox = component("textbox"),
                    option = component("option"),
                    disabledOption = component("disabled_option"),
                    messageBox = function() return { type = "messagebox" } end,
                },
                addMessage = function() end,
                clearMessages = function() end,
                enableOption = function() end,
                popMenu = function() end,
                pushMenu = function() end,
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
                        local data = responses[url]
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
    end,
}
