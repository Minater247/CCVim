return {
    id = "runtime.program_loader_env_preservation",
    description = "Keeps vim.lua and nvim.lua local handoffs in the caller's program environment instead of routing through plain dofile.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({ bootstrap_default_editor = false })

        local ok, err = pcall(function()
            local globals = mock.globals()
            local saved_shell = _G.shell
            local env = setmetatable({
                arg = { [0] = "/vim.lua" },
            }, {
                __index = function(_, key)
                    local value = globals[key]
                    if value ~= nil then
                        return value
                    end
                    return _G[key]
                end,
            })

            _G.shell = nil

            local restored = false
            local function restore_shell()
                if restored then
                    return
                end
                _G.shell = saved_shell
                restored = true
            end

            env.dofile = function(path)
                restore_shell()
                error("plain dofile should not be used for local program handoffs: " .. tostring(path))
            end

            local chunk, load_err = loadfile("/vim.lua", "t", env)
            Assert.truthy("vim.lua loads inside program env", chunk ~= nil, load_err)

            local run_ok, run_err = pcall(chunk, "-h")
            restore_shell()

            Assert.eq("vim.lua startup completes without plain dofile", run_ok, true)
            if not run_ok then
                error(run_err)
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
