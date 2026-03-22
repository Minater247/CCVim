return {
    id = "runtime.backend_key_modifier_flags",
    description = "Applies backend-supplied key modifier flags when processing key events.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Event = mock.loadModule("lib.event")
            Event.LoadCommandModule()

            setMode("insert")
            Event.ProcessEvent({ "key", keys.a, false, true, false })
            Event.ProcessEvent({ "key", keys.semiColon or keys.semicolon, false, true, false })
            Event.ProcessEvent({ "key", keys.one, false, true, false })
            Event.ProcessEvent({ "key", keys.leftBracket, true, false, false })

            local buf = windows[curwin].buffer
            Assert.eq("shifted key flag inserts uppercase letter", buf.lines[1], "A:!")
            Assert.eq("ctrl-leftBracket leaves insert mode", vimmode, "normal")

            setMode("insert")
            mock.queueEvent("key", keys.leftShift, false)
            mock.queueEvent("key", keys.a, false)
            Event.PullAndProcess("key")
            Event.PullAndProcess("key")

            Assert.eq("cc key events still honor tracked modifier state", buf.lines[1], "A:A!")
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
