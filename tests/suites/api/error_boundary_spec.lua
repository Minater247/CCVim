return {
    id = "api.error_boundary",
    description = "Keeps structured editor errors internal while exposing ordinary Lua error strings.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local mock = ctx.backend.mock
        local Error = mock.loadModule("lib.error")
        local Options = mock.loadModule("lib.options")
        local Scopes = mock.loadModule("lib.luaapi.scopes")
        local RawApi = mock.loadModule("lib.luaapi.api")

        local internal_ok, internal_err = pcall(Options.set, "compatible", true)
        Assert.eq("internal option error raises", internal_ok, false)
        Assert.truthy("internal option error uses Error", Error.IsError(internal_err))
        Assert.eq("internal option error code", internal_err.code, 519)

        local api = ctx.backend:api_build()
        local user_ok, user_err = pcall(api.vim.api.nvim_set_option_value, "compatible", true, {})
        Assert.eq("userspace option error raises", user_ok, false)
        Assert.eq("userspace option error is a string", type(user_err), "string")
        Assert.truthy("userspace option error contains E519", user_err:find("E519", 1, true) ~= nil)

        RawApi.nvim_error_after_nil = function()
            return nil, Error(730)
        end
        local later_ok, later_err = pcall(api.vim.api.nvim_error_after_nil)
        RawApi.nvim_error_after_nil = nil
        Assert.eq("later return error raises", later_ok, false)
        Assert.eq("later return error is a string", type(later_err), "string")
        Assert.truthy("later return error contains E730", later_err:find("E730", 1, true) ~= nil)

        Assert.eq("lock setup succeeds", Scopes.LockTable(Scopes._g, "error_boundary", 1), true)
        local scope_ok, scope_err = pcall(function()
            api.vim.g.error_boundary = 2
        end)
        Assert.eq("userspace scope error raises", scope_ok, false)
        Assert.eq("userspace scope error is a string", type(scope_err), "string")
        Assert.truthy("userspace scope error contains E741", scope_err:find("E741", 1, true) ~= nil)
    end,
}
