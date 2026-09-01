return {
    id = "api.system_function",
    description = "Implements system() and systemlist() normalization, argument semantics, and v:shell_error propagation.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local mock = ctx.backend.mock
        local globals = mock.globals()
        local seen
        globals.backend.system = function(argv, opts)
            seen = { argv = argv, opts = opts }
            return {
                code = 7,
                stdout = "one\r\ntwo\0three\n",
                stderr = "",
            }
        end
        local Fn = mock.loadModule("lib.luaapi.fn").fn
        local Error = mock.loadModule("lib.error")
        local Scopes = mock.loadModule("lib.luaapi.scopes")

        local command_ok, command_err = pcall(Fn.system, 42)
        Assert.eq("invalid command raises", command_ok, false)
        Assert.truthy("invalid command uses Error", Error.IsError(command_err))
        Assert.eq("invalid command error code", command_err.code, 730)

        local api = ctx.backend:api_build()
        local user_ok, user_err = pcall(api.vim.fn.system, 42)
        Assert.eq("vim.fn invalid command raises", user_ok, false)
        Assert.eq("vim.fn error is a string", type(user_err), "string")
        Assert.truthy("vim.fn error contains E730", user_err:find("E730", 1, true) ~= nil)

        local nvim_ok, nvim_err = pcall(api.vim.api.nvim_call_function, "system", { 42 })
        Assert.eq("nvim_call_function invalid command raises", nvim_ok, false)
        Assert.eq("nvim_call_function error is a string", type(nvim_err), "string")
        Assert.truthy("nvim_call_function error contains E730", nvim_err:find("E730", 1, true) ~= nil)

        local output = Fn.system({ "tool", "--value=a b", 42 }, "stdin")
        Assert.deep_eq("list command remains direct", seen.argv, { "tool", "--value=a b", "42" })
        Assert.eq("input forwarded", seen.opts.input, "stdin")
        Assert.eq("CRLF and NUL normalized", output, "one\ntwo\1three\n")
        Assert.eq("shell error propagated", Scopes._v.shell_error, 7)

        local lines = Fn.systemlist({ "tool" }, nil, 1)
        Assert.deep_eq("systemlist maps NUL to line break and preserves final empty item", lines, {
            "one", "two", "three", "",
        })

        globals.backend.system = function(argv)
            seen = { argv = argv }
            return { code = 0, stdout = "prefix", stderr = "fallback" }
        end
        Assert.eq("stderr merged into system output", Fn.system("tool 'two words'"), "prefixfallback")
        Assert.eq("string command passed to backend", seen.argv, "tool 'two words'")
        Assert.eq("successful shell error", Scopes._v.shell_error, 0)
    end,
}
