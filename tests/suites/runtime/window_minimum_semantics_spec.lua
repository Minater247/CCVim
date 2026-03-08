return {
    id = "runtime.window_minimum_semantics",
    description = "Ports internal window minimum width/height calculations on the real CCVim window objects; lua-editor-only because it asserts Window:minwidth()/minheight() directly.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({ bootstrap_default_editor = false })

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            _G.options = Options

            local buf1 = mock.create_buffer(1, "/tmp/window-minimum-a.txt", { "" }, { refcount = 1 })
            local buf2 = mock.create_buffer(2, "/tmp/window-minimum-b.txt", { "" }, { refcount = 1 })
            local win1 = mock.create_window(1, buf1, { style = nil })
            local win2 = mock.create_window(2, buf2, { style = nil })

            curwin = 1

            Options.set("winminwidth", 3, false, nil, nil, true)
            Options.set("winminheight", 2, false, nil, nil, true)
            Options.set("winwidth", 20, false, nil, nil, true)
            Options.set("winheight", 9, false, nil, nil, true)

            Options.set("number", false, true, win1)
            Options.set("relativenumber", false, true, win1)
            Options.set("number", false, true, win2)
            Options.set("relativenumber", false, true, win2)

            Assert.eq("current window minwidth uses winminwidth", win1:minwidth(), 3)
            Assert.eq("non-current window minwidth uses winminwidth", win2:minwidth(), 3)
            Assert.eq("current window minheight uses winminheight", win1:minheight(), 2)
            Assert.eq("non-current window minheight uses winminheight", win2:minheight(), 2)

            Options.set("number", true, true, win2)
            Options.set("numberwidth", 6, true, win2)
            Assert.eq("number column floor still applies", win2:minwidth(), 7)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
