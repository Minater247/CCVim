return {
    id = "runtime.stage5_match_query",
    description = "Complements the public stage5 parity suite with CCVim-internal syntax render and reset behavior.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Syntax = mock.loadModule("lib.syntax")
            local Runtime = mock.loadModule("lib.excmd.runtime")
            local Compiler = mock.loadModule("lib.excmd.compiler")
            local Scopes = mock.loadModule("lib.luaapi.scopes")
            local Highlight = mock.loadModule("lib.highlight")

            local durable_by_ctx = {}
            local function run_compiled(script, script_ctx)
                local key = script_ctx or "__default"
                local durable = durable_by_ctx[key]
                if not durable then
                    durable = Runtime.CaptureDurableScriptState({ script_ctx = script_ctx }) or { s = {}, funcs = {} }
                    durable.g = durable.g or Scopes._g
                    durable_by_ctx[key] = durable
                end

                local state = Runtime.MakeRuntimeState(durable)
                state.g = durable.g
                local runtime = Runtime.new(state)

                local code, compile_err = Compiler.compile_script(script, { state = state })
                Assert.truthy("compile script " .. script_ctx, code ~= nil, compile_err)

                local env = setmetatable({ runtime = runtime, _G = _G }, { __index = _G })
                local chunk, load_err = load(code, "excmd_compiled", "t", env)
                Assert.truthy("load script " .. script_ctx, chunk ~= nil, load_err)

                local fn = chunk()
                return pcall(fn, state, runtime)
            end

            local function assert_contains(label, list, needle)
                for i = 1, #list do
                    if tostring(list[i]):find(needle, 1, true) then
                        return
                    end
                end
                error(label .. ": expected to contain " .. tostring(needle))
            end

            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/stage5.txt"
            buf.lines = { "foo bar", "zzz" }
            buf.loaded = true
            buf.refcount = 1

            local buf2 = mock.create_buffer(2, "/tmp/stage5_b.txt", { "abc" }, { modified = false })
            buf2.leave = function() return true end
            buf2.Load = function() return true end
            buf2.refcount = 0

            win.cursorx = 1
            win.cursory = 1
            win.scrolly = { 1, 0 }
            win.scrollx = 1

            do
                local run_ok, rv = run_compiled("2match Search /foo/", "/tmp/stage5_match_set.vim")
                Assert.eq("2match set executes", run_ok, true)
                if run_ok ~= true then
                    error(tostring(rv))
                end

                local state = win.syntax_match_state
                Assert.truthy("match state exists", state ~= nil)
                Assert.truthy("slot 2 set", state.slots[2] ~= nil)
                Assert.eq("slot 2 group", state.slots[2].group, "Search")

                run_ok, rv = run_compiled("2match none", "/tmp/stage5_match_clear.vim")
                Assert.eq("2match clear executes", run_ok, true)
                if run_ok ~= true then
                    error(tostring(rv))
                end
                Assert.eq("slot 2 cleared", state.slots[2], nil)
            end

            do
                local match_ok, emsg = Syntax.MatchCommand(win, 1, "Search /foo/")
                Assert.eq("match command accepted", match_ok, true)
                if match_ok ~= true then
                    error(tostring(emsg))
                end

                local blits = Syntax.LinesToBlit(buf, 1, 1, win)
                local blit = blits[1]
                Assert.truthy("match-only line blit exists", blit ~= nil)

                local search_fg = colors.toBlit(Highlight.For("Search")[1])
                Assert.eq("match overlay fg at f", blit.fg:sub(1, 1), search_fg)
                Assert.eq("match overlay fg at o", blit.fg:sub(2, 2), search_fg)
                Assert.eq("match overlay fg at o2", blit.fg:sub(3, 3), search_fg)
            end

            do
                Syntax.OwnSyntax(win, "lua")
                Assert.truthy("ownsyntax creates override", win.syntax_ctx_override ~= nil)
                Syntax.OnWindowBufferChanged(win)
                Assert.eq("ownsyntax override cleared on buffer change", win.syntax_ctx_override, nil)
            end

            do
                win.buffer = buf
                local run_ok, rv = run_compiled("ownsyntax lua\nbuffer 2", "/tmp/stage5_ownsyntax_switch.vim")
                Assert.eq("ownsyntax + buffer executes", run_ok, true)
                if run_ok ~= true then
                    error(tostring(rv))
                end
                Assert.eq("window switched to buffer 2", win.buffer, buf2)
                Assert.eq("ownsyntax override cleared after :buffer", win.syntax_ctx_override, nil)
                Assert.eq("w:current_syntax cleared after :buffer", Scopes.w.current_syntax, nil)
            end

            do
                win.buffer = buf
                local run_ok, rv = run_compiled("ownsyntax lua\nedit", "/tmp/stage5_ownsyntax_edit.vim")
                Assert.eq("ownsyntax + edit executes", run_ok, true)
                if run_ok ~= true then
                    error(tostring(rv))
                end
                Assert.eq("ownsyntax override cleared after :edit", win.syntax_ctx_override, nil)
                Assert.eq("w:current_syntax cleared after :edit", Scopes.w.current_syntax, nil)
            end

            do
                local shared = mock.create_buffer(3, "/tmp/stage5_shared.txt", { "foo" }, { modified = false })
                shared.leave = function() return true end
                shared.Load = function() return true end
                shared.refcount = 2

                local win_a = mock.create_window(3, shared, {})
                local win_b = mock.create_window(4, shared, {})

                Syntax.ExecuteCommand(win_a, "keyword Comment foo")
                Syntax.OwnSyntax(win_b, "lua")
                Syntax.ExecuteCommand(win_b, "keyword String foo")

                local blit_a = Syntax.LineToBlit(shared, 1, win_a)
                local blit_b = Syntax.LineToBlit(shared, 1, win_b)
                local comment_fg = colors.toBlit(Highlight.For("Comment")[1])
                local string_fg = colors.toBlit(Highlight.For("String")[1])

                Assert.eq("shared buffer regular window keeps buffer syntax", blit_a.fg:sub(1, 1), comment_fg)
                Assert.eq("shared buffer ownsyntax window uses override syntax", blit_b.fg:sub(1, 1), string_fg)
            end

            do
                local syntime_buf = mock.create_buffer(5, "/tmp/stage5_syntime.txt", { "foo bar", "zzz" }, { modified = false })
                syntime_buf.loaded = true
                syntime_buf.refcount = 1
                local syntime_win = mock.create_window(5, syntime_buf, {})

                Syntax.ExecuteCommand(syntime_win, "match Comment /foo/")
                Syntax.SyntimeClear(syntime_win)
                Syntax.SyntimeSet(syntime_win, true)
                Syntax.LineToBlit(syntime_buf, 1, syntime_win)
                local lines = Syntax.SyntimeReport(syntime_win)

                Assert.truthy("syntime report has lines", #lines >= 2)
                assert_contains("syntime report total", lines, "total: calls=")
                assert_contains("syntime report header", lines, "TOTAL(ms)")
                assert_contains("syntime report row", lines, "foo")
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
