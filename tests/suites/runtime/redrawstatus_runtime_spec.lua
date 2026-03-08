return {
    id = "runtime.redrawstatus",
    description = "Ports redrawstatus and redrawtabline flagging on the real tabpage/window runtime objects; lua-editor-only because it asserts internal redraw flags.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Runtime = mock.loadModule("lib.excmd.runtime")
            local Tabpage = mock.loadModule("layout.tabpage")

            local tab = tabpages[curtp]
            local win1 = windows[curwin]
            local buf1 = win1.buffer
            buf1.name = "/tmp/redrawstatus_a"
            buf1.lines = { "a" }
            buf1.loaded = true
            buf1.refcount = 1

            local buf2 = mock.create_buffer(2, "/tmp/redrawstatus_b", { "b" }, { refcount = 1 })
            local win2 = mock.create_window(2, buf2, {})
            Assert.eq("real split creates second window", tab:WinSplit(win1.winnr, win2, true), true)

            local function run_script(script, script_ctx)
                local run_ok, rv = Runtime.run(script, { script_ctx = script_ctx })
                Assert.eq("runtime run " .. script_ctx, run_ok, true)
                if run_ok ~= true then
                    error(rv)
                end
            end

            local function reset_redraw()
                need_redraw = false
                what_redraw = {}
                win1.need_redraw = false
                win2.need_redraw = false
            end

            curwin = win1.winnr
            reset_redraw()
            run_script("redrawstatus", "/tmp/redrawstatus_runtime.vim")
            Assert.eq("redrawstatus marks current window", win1.need_redraw, true)
            Assert.eq("redrawstatus does not mark other window", win2.need_redraw, false)
            Assert.eq("redrawstatus marks commandline redraw", what_redraw.commandline, true)

            reset_redraw()
            run_script("redrawstatus!", "/tmp/redrawstatus_bang_runtime.vim")
            Assert.eq("redrawstatus! marks first window", win1.need_redraw, true)
            Assert.eq("redrawstatus! marks second window", win2.need_redraw, true)
            Assert.eq("redrawstatus! marks windows redraw", what_redraw.windows, true)
            Assert.eq("redrawstatus! marks commandline redraw", what_redraw.commandline, true)

            curwin = win1.winnr
            reset_redraw()
            run_script("redraws", "/tmp/redrawstatus_abbrev_runtime.vim")
            Assert.eq("redrawstatus abbreviation marks current window", win1.need_redraw, true)
            Assert.eq("redrawstatus abbreviation sets commandline redraw", what_redraw.commandline, true)

            reset_redraw()
            run_script("redrawtabline", "/tmp/redrawtabline_runtime.vim")
            Assert.eq("redrawtabline requests tabline redraw", what_redraw.tabline, true)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
