return {
    id = "runtime.undo",
    description = "Ports direct buffer undo history behavior on the real buffer/runtime path; lua-editor-only because it asserts CCVim's internal buffer undo methods directly.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            _G.options = Options
            local Runtime = mock.loadModule("lib.excmd.runtime")
            local Buffer = mock.loadModule("layout.buffer")
            mock.loadModule("lib.command")
            mock.loadModule("lib.mappings")

            screen.width = 80
            screen.height = 24

            local win = windows[curwin]
            curtp = win.tabpagenr
            vimmode = "normal"

            local function err_string(e)
                if type(e) == "table" and type(e.toString) == "function" then
                    return e:toString()
                end
                return tostring(e)
            end

            local function assert_lines(label, got, want)
                Assert.eq(label, table.concat(got, "\n"), table.concat(want, "\n"))
            end

            local function reset_buffer(lines)
                local buf = Buffer(true, false)
                buf.name = "/tmp/undo_runtime.txt"
                buf.lines = {}
                for i = 1, #lines do
                    buf.lines[i] = lines[i]
                end
                buf.refcount = 1
                buf.loaded = true
                buf.opts.modified = false
                buf:undo_clear()
                win.buffer = buf
                win.cursorx = 1
                win.cursory = 1
                return buf
            end

            local function run_script(script, script_ctx)
                local run_ok, rv = Runtime.run(script, { script_ctx = script_ctx })
                return run_ok, rv
            end

            do
                local buf = reset_buffer({ "one", "two" })
                buf:set_line(1, "ONE", true)
                Assert.eq("direct edit changed line", buf.lines[1], "ONE")
                Assert.truthy("undo returns true", buf:undo(win, 1), "undo failed")
                assert_lines("undo restores previous text", buf.lines, { "one", "two" })
                Assert.truthy("redo returns true", buf:redo(win, 1), "redo failed")
                assert_lines("redo reapplies change", buf.lines, { "ONE", "two" })
            end

            do
                local buf = reset_buffer({ "root" })
                buf:set_line(1, "a", true)
                buf:set_line(1, "b", true)
                Assert.truthy("undo branch step", buf:undo(win, 1), "undo failed")
                assert_lines("branch baseline after undo", buf.lines, { "a" })
                buf:set_line(1, "c", true)
                assert_lines("new branch text", buf.lines, { "c" })
                Assert.eq("redo unavailable after branching", buf:redo(win, 1), false)
            end

            do
                local buf = reset_buffer({ "x", "y" })
                buf:undo_begin(win)
                buf:set_line(1, "X", true)
                buf:set_line(2, "Y", true)
                buf:undo_end(win)
                assert_lines("grouped change applied", buf.lines, { "X", "Y" })
                Assert.truthy("grouped undo succeeds", buf:undo(win, 1), "group undo failed")
                assert_lines("grouped undo restores both lines", buf.lines, { "x", "y" })
            end

            do
                local buf = reset_buffer({ "persist" })
                Options.set("undolevels", -1, true, win, buf)
                buf:set_line(1, "nohistory", true)
                Assert.eq("undo disabled when undolevels=-1", buf:undo(win, 1), false)
                Options.set("undolevels", 1000, true, win, buf)
                buf:set_line(1, "history", true)
                Assert.truthy("undo re-enabled", buf:undo(win, 1), "undo did not resume")
                assert_lines("undo after re-enable", buf.lines, { "nohistory" })
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
