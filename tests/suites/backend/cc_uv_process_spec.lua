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
        local shell = {
            dir = function() return cwd end,
            setDir = function(path) cwd = path end,
            resolve = function(path) return path end,
            getRunningProgram = function() return "nvim.lua" end,
            execute = function(program, ...)
                seen = { program, ... }
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
        local env = setmetatable({
            term = term,
            window = window,
            shell = shell,
            colors = colors,
            keys = {},
            fs = {},
            os = {
                pullEvent = function() end,
                startTimer = function() return 1 end,
                cancelTimer = function() end,
                epoch = function() return 0 end,
            },
        }, { __index = _G })

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

        local killed
        local pending = CC.spawn("git", { args = { "status" } }, function(code, signal)
            killed = { code, signal }
        end)
        Assert.eq("pre-start kill succeeds", pending:kill("sigterm"), 0)
        Assert.deep_eq("pre-start kill reports signal", killed, { 0, 15 })
        Assert.truthy("killed timer cancelled", scheduled[2] == nil)
    end,
}
