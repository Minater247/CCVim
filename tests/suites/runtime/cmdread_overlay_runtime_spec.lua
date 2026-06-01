return {
    id = "runtime.cmdread_overlay",
    description = "Ports command-line takeover from Press ENTER and More overlays; lua-editor-only because it asserts CCVim's internal overlay handler stack.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local runs = {}
        local mock = MockEnv.setup({
            term_width = 24,
            term_height = 4,
            module_stubs = {
                ["lib.excmd.runtime"] = {
                    _FUNCS = {},
                    run = function(str, opts)
                        runs[#runs + 1] = {
                            str = str,
                            origin = opts and opts.origin and opts.origin.kind,
                        }
                        return true
                    end,
                },
            },
        })

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Key = mock.loadModule("lib.key")
            local Event = mock.loadModule("lib.event")
            local ExMsg = mock.loadModule("lib.excmd.exmsg")
            local CmdRead = mock.loadModule("lib.excmd.cmdread")

            Event.LoadCommandModule()

            local function flush_render()
                if need_redraw then
                    tabpages[curtp]:render()
                    need_redraw = false
                    what_redraw = {}
                    _G.what_redraw = what_redraw
                end
            end

            local function row_text(y)
                local cells = mock.term_cells()[y]
                local chars = {}
                for x = 1, #cells do
                    chars[x] = cells[x].ch
                end
                return table.concat(chars)
            end

            local function feed_keycode(keycode)
                Event.ProcessEvent({ "key", keycode })
                flush_render()
            end

            local function feed_seq(seq)
                for i = 1, #seq do
                    feed_keycode(seq[i].numeric)
                end
            end

            local function feed_text(text)
                feed_seq(Key.strtoseq(text))
            end

            local function press_colon()
                Event.ProcessEvent({ "key", keys.leftShift })
                Event.ProcessEvent({ "key", keys.semiColon or keys.semicolon })
                Event.ProcessEvent({ "key_up", keys.leftShift })
                flush_render()
            end

            local function press_enter()
                feed_keycode(keys.enter)
            end

            local function assert_cmdread_takes_over(label, lines, typed, expected_handler, expected_bottom)
                for i = 1, #lines do
                    ExMsg.echo(lines[i])
                end
                ExMsg.Finalize()
                flush_render()

                Assert.eq(label .. " overlay active before ':'", ExMsg.IsOverlayActive(), true)
                Assert.eq(
                    label .. " installs expected overlay handler",
                    loadModule("lib.command").emitter_names[#loadModule("lib.command").emitter_names],
                    expected_handler
                )

                press_colon()

                Assert.eq(label .. " activates cmdread", CmdRead.is_active(), true)
                Assert.eq(
                    label .. " top override handler becomes cmdread after ':'",
                    loadModule("lib.command").emitter_names[#loadModule("lib.command").emitter_names],
                    "CmdRead.handler"
                )
                Assert.truthy(
                    label .. " bottom row shows ':' instead of overlay prompt",
                    row_text(screen.height):find("^%s*:", 1) ~= nil,
                    row_text(screen.height)
                )

                feed_text(typed)
                Assert.eq(label .. " accepts typed keys after ':'", CmdRead.getline(), ":" .. typed)
                Assert.eq(
                    label .. " keeps cmdread on top while typing",
                    loadModule("lib.command").emitter_names[#loadModule("lib.command").emitter_names],
                    "CmdRead.handler"
                )
                Assert.truthy(
                    label .. " bottom row shows full cmdline",
                    row_text(screen.height):find(expected_bottom, 1, true) ~= nil,
                    row_text(screen.height)
                )

                press_enter()

                Assert.eq(label .. " leaves cmdread after Enter", CmdRead.is_active(), false)
                Assert.eq(label .. " records one runtime command", runs[#runs].str, ":" .. typed)
                Assert.eq(label .. " records user-cmdline origin", runs[#runs].origin, "user-cmdline")
            end

            Options.set("cmdheight", 1, false, nil, nil, true)

            assert_cmdread_takes_over(
                "press-enter",
                { "line one", "line two" },
                "echo",
                "ExMsg.readEnter",
                ":echo"
            )

            assert_cmdread_takes_over(
                "more",
                { "line one", "line two", "line three", "line four" },
                "pwd",
                "ExMsg.readMore",
                ":pwd"
            )
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
