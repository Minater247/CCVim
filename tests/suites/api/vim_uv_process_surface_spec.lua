return {
    id = "api.vim_uv_process_surface",
    description = "Exposes libuv process operations through backend delegation and reports the editor environment.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local mock = ctx.backend.mock
        local globals = mock.globals()
        local pipe_token = {}
        local process_token = {}
        local seen = {}
        globals.backend.new_pipe = function(ipc)
            seen.ipc = ipc
            return pipe_token
        end
        globals.backend.spawn = function(path, opts, on_exit)
            seen.path, seen.opts, seen.on_exit = path, opts, on_exit
            return process_token, 42
        end

        local EnvVars = mock.loadModule("lib.envvars")
        EnvVars.set("UV_PROCESS_TEST", "present")
        local loop = mock.loadModule("lib.luaapi.loop")
        Assert.eq("new_pipe result delegated", loop.new_pipe(true), pipe_token)
        Assert.eq("new_pipe ipc delegated", seen.ipc, true)

        local opts = {
            args = { "fetch", "--tags", "--force", "a b" },
            cwd = "/work tree",
            env = { "MODE=test" },
            stdio = { nil, pipe_token, pipe_token },
        }
        local callback = function() end
        local handle, pid = loop.spawn("git", opts, callback)
        Assert.eq("spawn handle delegated", handle, process_token)
        Assert.eq("spawn pid delegated", pid, 42)
        Assert.eq("spawn path delegated", seen.path, "git")
        Assert.eq("spawn options delegated without rewriting", seen.opts, opts)
        Assert.eq("spawn callback delegated", seen.on_exit, callback)

        local environment = loop.os_environ()
        Assert.eq("os_environ includes overrides", environment.UV_PROCESS_TEST, "present")
        Assert.truthy("os_environ includes editor defaults", environment.VIMRUNTIME ~= nil)

        local api = ctx.backend:api_build()
        local fn_environment = api.vim.fn.environ()
        Assert.eq("environ includes overrides", fn_environment.UV_PROCESS_TEST, "present")
        Assert.truthy("environ includes editor defaults", fn_environment.VIMRUNTIME ~= nil)
    end,
}
