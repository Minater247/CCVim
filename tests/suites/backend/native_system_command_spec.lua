return {
    id = "backend.native_system_command",
    description = "Validates native system command forms, stdin, output streams, cwd, and exit status.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local quiet_io = setmetatable({
            write = function() end,
            flush = function() end,
            popen = io.popen,
        }, { __index = io })
        local env = setmetatable({ io = quiet_io }, { __index = _G })
        local Native = assert(loadfile("lib/backend/native.lua", "t", env))()

        local commands = Native.list_commands()
        local has_sh = false
        for i = 1, #commands do
            if commands[i] == "sh" then has_sh = true end
            if i > 1 then Assert.truthy("native commands are unique and sorted", commands[i - 1] < commands[i]) end
        end
        Assert.truthy("native command discovery scans PATH", has_sh)
        Assert.truthy("native locale discovery returns a list", type(Native.list_locales()) == "table")
        Assert.truthy("native user discovery reads the host namespace", #Native.list_users() > 0)

        local result = Native.system({ "/bin/sh", "-c", "printf '%s' \"$1\"", "sh", "a b;$HOME" })
        Assert.eq("list command bypasses shell reinterpretation", result.stdout, "a b;$HOME")
        Assert.eq("list command succeeds", result.code, 0)

        result = Native.system("printf 'first'; printf 'second'", {})
        Assert.eq("string command uses native shell", result.stdout, "firstsecond")
        Assert.eq("string shell succeeds", result.code, 0)

        result = Native.system({ "/bin/sh", "-c", "pwd; cat; printf problem >&2; exit 7" }, {
            cwd = "/private/tmp",
            input = { "one", "two" },
        })
        Assert.eq("stdin list and cwd forwarded", result.stdout, "/private/tmp\none\ntwo\n")
        Assert.eq("stderr captured separately", result.stderr, "problem")
        Assert.eq("nonzero status returned", result.code, 7)

        result = Native.system({}, {})
        Assert.eq("empty command rejected", result.code, 1)

        local stdout, stderr = Native.new_pipe(false), Native.new_pipe(false)
        local stdout_parts, stderr_parts = {}, {}
        local stdout_done, stderr_done, exited = false, false, false
        local exit_code, exit_signal
        local args = {
            "-c", "printf '%s\\n' \"$@\"; printf '%s' \"$ONLY\" >&2; exit 7", "sh",
            "fetch", "--filter=blob:none", "--recurse-submodules", "--tags",
            "--force", "--progress", "-c", "core.autocrlf=false", "a b;$HOME", "",
        }
        local handle, pid = Native.spawn("/bin/sh", {
            args = args,
            cwd = "/private/tmp",
            env = { "ONLY=stderr" },
            stdio = { nil, stdout, stderr },
        }, function(code, signal)
            exit_code, exit_signal, exited = code, signal, true
        end)
        Assert.truthy("native spawn returns handle", handle ~= nil)
        Assert.truthy("native spawn returns pid", type(pid) == "number" and pid > 0)
        stdout:read_start(function(read_err, data)
            Assert.eq("native stdout read error", read_err, nil)
            if data then stdout_parts[#stdout_parts + 1] = data else stdout_done = true end
        end)
        stderr:read_start(function(read_err, data)
            Assert.eq("native stderr read error", read_err, nil)
            if data then stderr_parts[#stderr_parts + 1] = data else stderr_done = true end
        end)
        while not (exited and stdout_done and stderr_done) do
            Native.uv.run("once")
        end
        handle:close()
        stdout:close()
        stderr:close()
        Assert.eq("native spawn preserves complete argv", table.concat(stdout_parts),
            table.concat({
                "fetch", "--filter=blob:none", "--recurse-submodules", "--tags",
                "--force", "--progress", "-c", "core.autocrlf=false", "a b;$HOME", "", "",
            }, "\n"))
        Assert.eq("native spawn forwards environment", table.concat(stderr_parts), "stderr")
        Assert.eq("native spawn exit code", exit_code, 7)
        Assert.eq("native spawn exit signal", exit_signal, 0)
        Assert.truthy("native process closes explicitly", handle:is_closing())
    end,
}
