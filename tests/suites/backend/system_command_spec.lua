return {
    id = "backend.system_command",
    description = "Runs CraftOS system commands with verbatim arguments, captured output, cwd restoration, and failure status.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local current
        local parent = {
            getSize = function() return 40, 5 end,
        }
        current = parent
        local captures = {}
        local term = {
            current = function() return current end,
            redirect = function(target)
                local previous = current
                current = target
                return previous
            end,
            getPaletteColor = function() return 0, 0, 0 end,
        }
        local window = {
            create = function()
                local lines = { "", "", "", "", "" }
                local capture = {
                    getLine = function(y) return lines[y], "", "" end,
                    write = function(text) lines[1] = lines[1] .. tostring(text) end,
                    scroll = function(amount)
                        for _ = 1, amount do
                            table.remove(lines, 1)
                            lines[#lines + 1] = ""
                        end
                    end,
                }
                captures[#captures + 1] = capture
                return capture
            end,
        }
        local cwd = "before"
        local seen
        local shell = {
            dir = function() return cwd end,
            setDir = function(path) cwd = path end,
            resolve = function(path) return path end,
            getRunningProgram = function() return "nvim.lua" end,
            execute = function(program, ...)
                seen = { program, ... }
                current.write("captured output")
                return false
            end,
            run = function(command)
                seen = { command }
                current.write("shell output")
                for _ = 1, 7 do current.scroll(1) end
                current.write("tail")
                return true
            end,
        }
        local colors = {
            white = 1, orange = 2, magenta = 4, lightBlue = 8,
            yellow = 16, lime = 32, pink = 64, gray = 128,
            lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
            brown = 4096, green = 8192, red = 16384, black = 32768,
        }
        local event_queue = {}
        local next_timer = 0
        local os_api = {}
        function os_api.pullEventRaw()
            local ev = table.remove(event_queue, 1)
            if not ev then error("event queue empty") end
            return table.unpack(ev)
        end
        function os_api.pullEvent(filter)
            while true do
                local ev = { os_api.pullEventRaw() }
                if filter == nil or ev[1] == filter then
                    return table.unpack(ev)
                end
            end
        end
        function os_api.queueEvent(name, ...)
            event_queue[#event_queue + 1] = { name, ... }
        end
        function os_api.startTimer()
            next_timer = next_timer + 1
            return next_timer
        end
        function os_api.cancelTimer() end
        function os_api.epoch() return 0 end
        local env = setmetatable({
            term = term,
            window = window,
            shell = shell,
            colors = colors,
            keys = {},
            fs = {},
            os = os_api,
        }, { __index = _G })

        local root = rawget(_G, "__CCVIM_TEST_ROOT") or "."
        local chunk, err = loadfile(root .. "/lib/backend/cc.lua", "t", env)
        Assert.truthy("cc backend loads", chunk ~= nil, err)
        local CC = chunk()
        local result = CC.system({ "tool", "--value=a b", "literal" }, { cwd = "/work" })

        Assert.eq("program passed directly", seen[1], "tool")
        Assert.eq("argument with whitespace remains one argument", seen[2], "--value=a b")
        Assert.eq("literal argument remains separate", seen[3], "literal")
        Assert.eq("failed command status", result.code, 1)
        Assert.eq("captured stdout", result.stdout, "captured output")
        Assert.eq("cwd restored", cwd, "before")
        Assert.eq("terminal restored", current, parent)

        result = CC.system("tool 'two words' plain\\ value", {})
        Assert.eq("string command delegated to CraftOS shell", seen[1], "tool 'two words' plain\\ value")
        Assert.eq("string command status", result.code, 0)
        Assert.eq("scrolled output retained", result.stdout,
            table.concat({ "shell output", "", "", "", "", "", "", "tail" }, "\n"))

        local parent_timer = CC.start_timer(1)
        os_api.queueEvent("timer", parent_timer)
        os_api.queueEvent("http_success", "request")
        local original_pull = os_api.pullEvent
        local original_pull_raw = os_api.pullEventRaw
        shell.execute = function()
            local name, request = os_api.pullEvent("http_success")
            Assert.eq("child receives requested event", name, "http_success")
            Assert.eq("child receives requested event payload", request, "request")
            return true
        end

        result = CC.system({ "networked" }, {})
        Assert.eq("networked command succeeds", result.code, 0)
        Assert.eq("pullEvent restored after command", os_api.pullEvent, original_pull)
        Assert.eq("pullEventRaw restored after command", os_api.pullEventRaw, original_pull_raw)
        local event, timer_id = CC.pull_event()
        Assert.eq("parent timer event preserved", event, "timer")
        Assert.eq("parent timer id preserved", timer_id, parent_timer)
    end,
}
