return {
    id = "runtime.insert_exit_key_by_backend",
    description = "Selects insert-mode exit key by backend kind: Ctrl-Tab on cc, Esc on native.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local function assert_exit_behavior(kind, keycode, ctrl, expected_mode, label)
            local mock = MockEnv.setup({ bootstrap_default_editor = false })
            local ok, err = pcall(function()
                local globals = mock.globals()
                globals.backend.kind = kind

                local Event = mock.loadModule("lib.event")
                Event.LoadCommandModule()
                mock.loadModule("lib.mappings", { immediate = true })

                setMode("insert")
                Event.ProcessEvent({ "key", keycode, ctrl == true, false, false })
                Assert.eq(label, vimmode, expected_mode)
            end)
            mock.cleanup()
            if not ok then
                error(err)
            end
        end

        assert_exit_behavior("cc", keys.tab, true, "normal", "cc backend exits insert with Ctrl-Tab")
        assert_exit_behavior("cc", keys.leftBracket, true, "normal", "cc backend accepts Neovim Escape")
        assert_exit_behavior("native", keys.leftBracket, true, "normal", "native backend exits insert with Esc")
    end,
}
