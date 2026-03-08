return {
    id = "runtime.mouse_mapping",
    description = "Ports mapped mouse events through CCVim's real event loop; lua-editor-only because it targets the internal ComputerCraft mouse bridge.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local epochs = { 1000, 1100, 1200, 1300, 1400, 1500 }
        local epoch_idx = 0

        local mock = MockEnv.setup()
        os.startTimer = function() return 1 end
        os.cancelTimer = function() end
        os.pullEvent = function() return "terminate" end
        os.epoch = function()
            epoch_idx = epoch_idx + 1
            return epochs[epoch_idx] or epochs[#epochs]
        end

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Autocmd = mock.loadModule("lib.autocmd")
            local Event = mock.loadModule("lib.event")
            local Command = mock.loadModule("lib.command")
            local Key = mock.loadModule("lib.key")

            _G.options = Options

            local popup_calls = 0
            Autocmd.CreateAutocommand({ "MenuPopup" }, { "*" }, function()
                popup_calls = popup_calls + 1
            end, nil, 1, false, false)

            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/mouse-mapping.txt"
            buf.lines = { "one", "two", "three", "four", "five" }
            buf.loaded = true
            win.cursorx = 1
            win.cursory = 1
            win.scrollx = 1

            local cursor_calls = 0
            local scroll_calls = 0
            win.textheight = function()
                return 5
            end
            win.textwidth = function()
                return 20, 1
            end
            win.cursorSetScreenRow = function(_, row_offset, opts)
                cursor_calls = cursor_calls + 1
                win.cursory = row_offset + 1
                win.cursorx = opts and opts.screen_col or win.cursorx
            end
            win.scroll = function(_, _, _)
                scroll_calls = scroll_calls + 1
            end

            vimmode = "normal"

            Options.set("mouse", "nvi", false, win, buf, true)
            Options.set("mousemodel", "popup_setpos", false, win, buf, true)
            Options.set("mousetime", 500, false, win, buf, true)
            Options.set("mousescroll", "ver:3,hor:6", false, win, buf, true)

            Event.LoadCommandModule()

            local left_hits = 0
            local right_hits = 0
            local dbl_right_hits = 0
            local drag_hits = 0
            local release_hits = 0
            local wheel_up_hits = 0
            local shifted_wheel_down_hits = 0

            Command.clear_mappings({
                "normal",
                "visual",
                "select",
                "operator",
                "insert",
                "lang",
                "cmdline",
                "terminal",
            })

            Command.map_callback("normal", Key.strtoseq("<LeftMouse>"), function()
                left_hits = left_hits + 1
            end)
            Command.map_callback("normal", Key.strtoseq("<RightMouse>"), function()
                right_hits = right_hits + 1
            end)
            Command.map_callback("normal", Key.strtoseq("<2-RightMouse>"), function()
                dbl_right_hits = dbl_right_hits + 1
            end)
            Command.map_callback("normal", Key.strtoseq("<LeftDrag>"), function()
                drag_hits = drag_hits + 1
            end)
            Command.map_callback("normal", Key.strtoseq("<LeftRelease>"), function()
                release_hits = release_hits + 1
            end)
            Command.map_callback("normal", Key.strtoseq("<ScrollWheelUp>"), function()
                wheel_up_hits = wheel_up_hits + 1
            end)
            Command.map_callback("normal", Key.strtoseq("<S-ScrollWheelDown>"), function()
                shifted_wheel_down_hits = shifted_wheel_down_hits + 1
            end)

            Event.ProcessEvent({ "mouse_click", 1, 8, 3 })
            Assert.eq("left click mapping executed", left_hits, 1)
            Assert.eq("mapped left click suppresses default cursor move", cursor_calls, 0)

            Event.ProcessEvent({ "mouse_click", 2, 8, 3 })
            Event.ProcessEvent({ "mouse_click", 2, 8, 3 })
            Assert.eq("right click mapping executed", right_hits, 1)
            Assert.eq("double right click mapping executed", dbl_right_hits, 1)
            Assert.eq("mapped double right click suppresses popup", popup_calls, 0)

            Event.ProcessEvent({ "mouse_drag", 1, 9, 3 })
            Assert.eq("left drag mapping executed", drag_hits, 1)
            Assert.eq("mapped left drag suppresses default cursor move", cursor_calls, 0)

            Event.ProcessEvent({ "mouse_up", 1, 9, 3 })
            Assert.eq("left release mapping executed", release_hits, 1)

            Event.ProcessEvent({ "mouse_scroll", -1, 8, 3 })
            Assert.eq("scroll-up mapping executed", wheel_up_hits, 1)
            Assert.eq("mapped scroll-up suppresses default scroll", scroll_calls, 0)

            Event.ProcessEvent({ "key", keys.leftShift })
            Event.ProcessEvent({ "mouse_scroll", 1, 8, 3 })
            Event.ProcessEvent({ "key_up", keys.leftShift })
            Assert.eq("shifted scroll-down mapping executed", shifted_wheel_down_hits, 1)
            Assert.eq("mapped shifted scroll suppresses default scroll", scroll_calls, 0)

            local emitted = Key.replace_termcodes("<LeftMouse>", true, true)
            Command.execute_normal_keys(Key.strtoseq(emitted), { remap = true })
            Assert.eq("script-emitted <LeftMouse> triggers mapping", left_hits, 2)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
