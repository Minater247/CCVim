return {
    id = "runtime.undo",
    description = "Ports undo and redo behavior on the real buffer/runtime path; lua-editor-only because it asserts CCVim buffer undo internals and normal-mode execution details.",
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

            do
                local buf = reset_buffer({ "one" })
                buf:set_line(1, "two", true)
                local run_ok, rv = run_script("undo", "/tmp/undo_cmd.vim")
                Assert.truthy("ex undo command runs", run_ok == true, err_string(rv))
                assert_lines("ex undo restores line", buf.lines, { "one" })
                run_ok, rv = run_script("redo", "/tmp/redo_cmd.vim")
                Assert.truthy("ex redo command runs", run_ok == true, err_string(rv))
                assert_lines("ex redo reapplies line", buf.lines, { "two" })
            end

            do
                local buf = reset_buffer({ "one" })
                buf:set_line(1, "two", true)
                buf:set_line(1, "three", true)
                buf:set_line(1, "four", true)
                local run_ok, rv = run_script("undo 2", "/tmp/undo_jump_cmd.vim")
                Assert.truthy("ex undo change-id jump runs", run_ok == true, err_string(rv))
                assert_lines("ex undo change-id jumps to target state", buf.lines, { "three" })
                run_ok, rv = run_script("redo 1", "/tmp/redo_count_cmd.vim")
                Assert.truthy("ex redo count runs", run_ok == true, err_string(rv))
                assert_lines("ex redo count reapplies one", buf.lines, { "four" })
            end

            do
                reset_buffer({ "one" })
                local run_ok, rv = run_script("undo nope", "/tmp/undo_bad_arg.vim")
                Assert.truthy(
                    "ex undo invalid arg fails E474",
                    run_ok == false and err_string(rv):find("E474", 1, true) ~= nil,
                    err_string(rv)
                )
            end

            do
                local buf = reset_buffer({ "abc" })
                local run_ok, rv = run_script([[
normal! x
normal! u
normal! <C-r>
                ]], "/tmp/undo_normal_angle_ctrlr.vim")
                Assert.truthy("normal angle ctrl-r script runs", run_ok == true, err_string(rv))
                assert_lines("normal angle ctrl-r is literal (no redo)", buf.lines, { "abc" })
                Assert.eq("normal angle ctrl-r keeps clean modified", buf.opts.modified, false)
            end

            do
                local buf = reset_buffer({ "abc" })
                local run_ok, rv = run_script([[
normal! x
normal! u
execute "normal! \x12"
                ]], "/tmp/undo_normal_raw_ctrlr.vim")
                Assert.truthy("normal raw ctrl-r script runs", run_ok == true, err_string(rv))
                assert_lines("normal raw ctrl-r redoes", buf.lines, { "bc" })
                Assert.eq("normal raw ctrl-r marks modified", buf.opts.modified, true)
            end

            do
                local buf = reset_buffer({ "abc" })
                local run_ok, rv = run_script([[
normal! x
normal! x
normal! U
normal! u
                ]], "/tmp/undo_normal_u_contiguous.vim")
                Assert.truthy("normal U contiguous script runs", run_ok == true, err_string(rv))
                assert_lines("normal U contiguous parity", buf.lines, { "abc" })
                Assert.eq("normal U contiguous modified parity", buf.opts.modified, false)
            end

            do
                local buf = reset_buffer({ "abc", "def" })
                local run_ok, rv = run_script([[
normal! x
normal! jx
normal! kx
normal! U
                ]], "/tmp/undo_normal_u_noncontiguous.vim")
                Assert.truthy("normal U noncontiguous script runs", run_ok == true, err_string(rv))
                assert_lines("normal U noncontiguous parity", buf.lines, { "bc", "ef" })
                Assert.eq("normal U noncontiguous modified parity", buf.opts.modified, true)
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
