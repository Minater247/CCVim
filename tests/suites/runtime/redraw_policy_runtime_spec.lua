return {
    id = "runtime.redraw_policy",
    description = "Ports redraw policy behavior on the real startup window and buffer; lua-editor-only because it asserts internal redraw flags.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Api = mock.loadModule("lib.luaapi.api")

            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/redraw_policy"
            buf.lines = { "a" }
            buf.loaded = true
            buf.refcount = 1
            win.cursorx = 1
            win.cursory = 1

            local function reset_redraw()
                need_redraw = false
                what_redraw = {}
                win.need_redraw = false
            end

            reset_redraw()
            Options.set("showcmd", false, false, win, buf, true)
            Assert.eq("global option change triggers full redraw", what_redraw.all, true)

            reset_redraw()
            Options.set("number", false, true, win, buf)
            Assert.eq("window-local option marks current window", win.need_redraw, true)
            Assert.truthy(
                "window-local option does not force full redraw",
                what_redraw.all ~= true,
                tostring(what_redraw.all)
            )

            reset_redraw()
            Options.set("number", true, false, win, buf, true)
            Assert.eq("setglobal on window-local option triggers full redraw", what_redraw.all, true)

            reset_redraw()
            Options.exset_token("number", "local", win, buf)
            Assert.eq(":setlocal option marks current window", win.need_redraw, true)
            Assert.truthy(
                ":setlocal option does not force full redraw",
                what_redraw.all ~= true,
                tostring(what_redraw.all)
            )

            reset_redraw()
            buf:set_lines(0, 1, false, { "b" })
            Assert.eq("buffer mutation triggers full redraw", what_redraw.all, true)

            reset_redraw()
            Api.nvim_buf_set_lines(buf.bufnr, 0, 1, false, { "c" })
            Assert.eq("nvim_buf_set_lines triggers full redraw", what_redraw.all, true)
            Assert.eq("nvim_buf_set_lines marks window redraw", win.need_redraw, true)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
