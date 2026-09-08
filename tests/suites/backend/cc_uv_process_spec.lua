return {
    id = "backend.cc_uv_process",
    description = "Runs the libuv process contract through the CraftOS backend with direct argument vectors and stream lifecycle.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local root = rawget(_G, "__CCVIM_TEST_ROOT") or "."
        local FakeUserdata = dofile(root .. "/lib/luaapi/fakeuserdata.lua")
        local current
        local parent = { getSize = function() return 60, 6 end }
        current = parent
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
                local lines = { "", "", "", "", "", "" }
                return {
                    getLine = function(y) return lines[y], "", "" end,
                    write = function(text) lines[1] = lines[1] .. tostring(text) end,
                    scroll = function(amount)
                        for _ = 1, amount do
                            table.remove(lines, 1)
                            lines[#lines + 1] = ""
                        end
                    end,
                }
            end,
        }
        local cwd = "before"
        local seen
        local run_multitasked = false
        local child_observations
        local env
        local shell = {
            dir = function() return cwd end,
            setDir = function(path) cwd = path end,
            resolve = function(path) return path end,
            getRunningProgram = function() return "nvim.lua" end,
            execute = function(program, ...)
                seen = { program, ... }
                if run_multitasked then
                    child_observations = {
                        custom = env._G.custom_fs_addon,
                        editor_only = env._G.editor_only,
                        cwd = cwd,
                        sleep_false_ok = pcall(env.sleep, false),
                    }
                    current.write("before ")
                    local event, value = env.os.pullEvent("http_success")
                    current.write(event .. " " .. value .. " ")
                    env.sleep(0)
                    current.write("after")
                    return true
                end
                current.write("process output")
                return false
            end,
            run = function() return true end,
        }
        local colors = {
            white = 1, orange = 2, magenta = 4, lightBlue = 8,
            yellow = 16, lime = 32, pink = 64, gray = 128,
            lightGray = 256, cyan = 512, purple = 1024, blue = 2048,
            brown = 4096, green = 8192, red = 16384, black = 32768,
        }
        local event_queue = {}
        local os_timer = 0
        local os_api = {
            pullEventRaw = function()
                local event = table.remove(event_queue, 1)
                if not event then error("event queue empty") end
                return table.unpack(event)
            end,
            startTimer = function()
                os_timer = os_timer + 1
                return os_timer
            end,
            cancelTimer = function() end,
            epoch = function() return 0 end,
        }
        os_api.pullEvent = function(filter)
            while true do
                local event = table.pack(os_api.pullEventRaw())
                if filter == nil or event[1] == filter then
                    return table.unpack(event, 1, event.n)
                end
            end
        end
        env = setmetatable({
            term = term,
            window = window,
            shell = shell,
            colors = colors,
            keys = {},
            fs = {},
            os = os_api,
            custom_fs_addon = { marker = "preserved" },
        }, { __index = _G })
        env._G = env

        local chunk, err = loadfile(root .. "/lib/backend/cc.lua", "t", env)
        Assert.truthy("cc backend loads", chunk ~= nil, err)
        local CC = chunk()
        local scheduled = {}
        local next_timer = 0
        local Event = {
            StartTimer = function(_, callback)
                next_timer = next_timer + 1
                scheduled[next_timer] = callback
                return next_timer
            end,
            CancelTimer = function(id)
                scheduled[id] = nil
            end,
        }
        CC.on_load_module_ready({
            loadModule = function(name)
                if name == "lib.event" then return Event end
                if name == "lib.luaapi.fakeuserdata" then return FakeUserdata end
                return {}
            end,
            LOG_DEBUG = function() end,
        })

        local stdout = CC.new_pipe(false)
        local stderr = CC.new_pipe(false)
        local stdout_events, stderr_events = {}, {}
        stdout:read_start(function(read_err, data)
            stdout_events[#stdout_events + 1] = { read_err, data == nil and "<eof>" or data }
        end)
        stderr:read_start(function(read_err, data)
            stderr_events[#stderr_events + 1] = { read_err, data == nil and "<eof>" or data }
        end)

        local exited
        local args = {
            "fetch", "--filter=blob:none", "--recurse-submodules", "--tags",
            "--force", "--progress", "-c", "core.autocrlf=false", "a b;$HOME", "",
        }
        local handle, pid = CC.spawn("git", {
            args = args,
            cwd = "/work tree",
            stdio = { nil, stdout, stderr },
        }, function(code, signal)
            exited = { code, signal }
        end)

        Assert.eq("process handle uses userdata API type", FakeUserdata.type(handle), "userdata")
        Assert.eq("pipe uses userdata API type", FakeUserdata.type(stdout), "userdata")
        Assert.truthy("process receives a positive pid", type(pid) == "number" and pid > 0)
        Assert.truthy("spawn returns before command execution", seen == nil)
        Assert.truthy("process initially active", handle:is_active())
        Assert.truthy("stdout read active", stdout:is_active())

        scheduled[1]()

        local expected = { "git" }
        for i = 1, #args do expected[#expected + 1] = args[i] end
        Assert.deep_eq("all argument forms remain separate and verbatim", seen, expected)
        Assert.eq("spawn cwd applied during execution", cwd, "before")
        Assert.deep_eq("stdout data and EOF delivered", stdout_events, {
            { nil, "process output" },
            { nil, "<eof>" },
        })
        Assert.deep_eq("empty stderr still delivers EOF", stderr_events, { { nil, "<eof>" } })
        Assert.deep_eq("exit status delivered", exited, { 1, 0 })
        Assert.eq("exited process is inactive", handle:is_active(), false)
        Assert.eq("process remains open until client closes it", handle:is_closing(), false)
        handle:close()
        stdout:close()
        stderr:close()
        Assert.truthy("closed process reports closing", handle:is_closing())
        Assert.truthy("closed stdout reports closing", stdout:is_closing())

        run_multitasked = true
        env.editor_only = "added after startup"
        local async_stdout = CC.new_pipe(false)
        local async_events = {}
        async_stdout:read_start(function(read_err, data)
            async_events[#async_events + 1] = { read_err, data == nil and "<eof>" or data }
        end)
        local async_exit
        local async_handle = CC.spawn("git", {
            args = { "clone", "repository" },
            cwd = "/work tree",
            stdio = { nil, async_stdout, nil },
        }, function(code, signal)
            async_exit = { code, signal }
        end)
        scheduled[2]()
        Assert.truthy("yielding process remains active", async_handle:is_active())
        Assert.eq("editor terminal restored after child yield", current, parent)
        Assert.eq("editor cwd restored after child yield", cwd, "before")
        Assert.eq("editor os table restored after child yield", env.os, os_api)
        Assert.eq("startup custom global inherited", child_observations.custom.marker, "preserved")
        Assert.eq("late editor global excluded", child_observations.editor_only, nil)
        Assert.eq("child cwd applied", child_observations.cwd, "work tree")
        Assert.eq("sleep rejects boolean timeout", child_observations.sleep_false_ok, false)

        event_queue[#event_queue + 1] = { "http_success", "response" }
        local editor_event, editor_value = CC.pull_event()
        Assert.eq("editor receives child wake event", editor_event, "http_success")
        Assert.eq("editor receives child wake payload", editor_value, "response")
        Assert.truthy("sleeping process remains active", async_handle:is_active())
        Assert.eq("editor terminal restored after child sleep", current, parent)
        Assert.eq("editor cwd restored after child sleep", cwd, "before")
        Assert.eq("editor os table restored after child sleep", env.os, os_api)

        event_queue[#event_queue + 1] = { "timer", os_timer }
        Assert.eq("editor receives child sleep timer", CC.pull_event(), "timer")
        Assert.deep_eq("multitasked process output", async_events, {
            { nil, "before http_success response after" },
            { nil, "<eof>" },
        })
        Assert.deep_eq("multitasked process exit", async_exit, { 0, 0 })
        Assert.eq("completed multitasked process inactive", async_handle:is_active(), false)

        local shared_results = {}
        shell.execute = function(program)
            local _, value = env.os.pullEvent("shared_event")
            shared_results[program] = value
            return true
        end
        local first_exit, second_exit
        CC.spawn("first", {}, function(code, signal)
            first_exit = { code, signal }
        end)
        CC.spawn("second", {}, function(code, signal)
            second_exit = { code, signal }
        end)
        scheduled[3]()
        scheduled[4]()
        event_queue[#event_queue + 1] = { "shared_event", "broadcast" }
        Assert.eq("editor receives broadcast event", CC.pull_event(), "shared_event")
        Assert.deep_eq("same event wakes every matching process", shared_results, {
            first = "broadcast",
            second = "broadcast",
        })
        Assert.deep_eq("first broadcast process exits", first_exit, { 0, 0 })
        Assert.deep_eq("second broadcast process exits", second_exit, { 0, 0 })

        local resumed_after_kill = false
        shell.execute = function()
            env.os.pullEvent("resume_killed")
            resumed_after_kill = true
            return true
        end
        local waiting_exit
        local waiting = CC.spawn("waiting", {}, function(code, signal)
            waiting_exit = { code, signal }
        end)
        scheduled[5]()
        Assert.eq("waiting process kill succeeds", waiting:kill("sigterm"), 0)
        Assert.deep_eq("waiting process kill reports signal", waiting_exit, { 0, 15 })
        event_queue[#event_queue + 1] = { "resume_killed" }
        Assert.eq("editor receives killed process event", CC.pull_event(), "resume_killed")
        Assert.eq("killed process is not resumed", resumed_after_kill, false)

        local killed
        local pending = CC.spawn("git", { args = { "status" } }, function(code, signal)
            killed = { code, signal }
        end)
        Assert.eq("pre-start kill succeeds", pending:kill("sigterm"), 0)
        Assert.deep_eq("pre-start kill reports signal", killed, { 0, 15 })
        Assert.truthy("killed timer cancelled", scheduled[6] == nil)
    end,
}
