return {
    id = "runtime.event_resize_dispatch",
    description = "Ports resize event dispatch through the real CCVim event loop; lua-editor-only because it targets the internal ComputerCraft event bridge.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({ bootstrap_default_editor = true })

        local ok, err = pcall(function()
            local resize_calls = {}
            local pulled = 0
            local size_calls = 0

            local Error = mock.loadModule("lib.error")
            local Event = mock.loadModule("lib.event")
            local ExMsg = mock.loadModule("lib.excmd.exmsg")

            _G.apply_terminal_resize = function(w, h, source)
                resize_calls[#resize_calls + 1] = { w = w, h = h, source = source }
                if source == "monitor_resize" then
                    return false, Error(36)
                end
                return true
            end

            os.startTimer = function()
                return 99
            end
            os.cancelTimer = function() end
            os.pullEvent = function()
                pulled = pulled + 1
                if pulled == 1 then
                    return "term_resize"
                elseif pulled == 2 then
                    return "monitor_resize"
                elseif pulled == 3 then
                    return "timer", 99
                end
                error("unexpected pullEvent call: " .. tostring(pulled))
            end

            term.getSize = function()
                size_calls = size_calls + 1
                if size_calls == 1 then
                    return 120, 40
                end
                return 121, 41
            end

            Event.LoadCommandModule()
            Event.StartTimer(0, function()
                Event.HaltLoop()
            end)
            Event.RunLoop()

            Assert.eq("resize called twice", #resize_calls, 2)
            Assert.eq("first resize source", resize_calls[1].source, "term_resize")
            Assert.eq("first resize width", resize_calls[1].w, 120)
            Assert.eq("first resize height", resize_calls[1].h, 40)
            Assert.eq("second resize source", resize_calls[2].source, "monitor_resize")
            Assert.eq("second resize width", resize_calls[2].w, 121)
            Assert.eq("second resize height", resize_calls[2].h, 41)
            Assert.eq("failed resize logged once", #ExMsg.messages, 1)
            Assert.truthy(
                "error message contains E36",
                ExMsg.messages[1][2]:find("E36", 1, true) ~= nil,
                ExMsg.messages[1][2]
            )
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
