return {
    id = "runtime.mouse_events",
    description = "Ports default mouse event handling through CCVim's real event loop; lua-editor-only because it targets the internal ComputerCraft mouse bridge.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local epochs = { 1000, 1200, 1300, 3000, 3300 }
        local epoch_idx = 0

        local mock = MockEnv.setup()
        local cc_os = mock.globals().os

        cc_os.startTimer = function() return 1 end
        cc_os.cancelTimer = function() end
        cc_os.pullEvent = function() return "terminate" end
        cc_os.epoch = function()
            epoch_idx = epoch_idx + 1
            return epochs[epoch_idx] or epochs[#epochs]
        end

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Autocmd = mock.loadModule("lib.autocmd")
            local Event = mock.loadModule("lib.event")
            local Scopes = mock.loadModule("lib.luaapi.scopes")

            local autocmd_calls = {}
            Autocmd.CreateAutocommand({ "MenuPopup" }, { "*" }, function(info)
                autocmd_calls[#autocmd_calls + 1] = {
                    event = "MenuPopup",
                    ctx = info,
                }
            end, nil, 1, false, false)

            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/mouse.txt"
            buf.lines = { "one", "two", "three", "four", "five" }
            buf.loaded = true
            buf.opts.filetype = ""

            win.cursorx = 1
            win.cursory = 1
            win.scrollx = 3
            win.scrolly = { 1, 0 }

            local scroll_calls = {}
            local cursor_calls = {}
            win.textheight = function()
                return 5
            end
            win.textwidth = function()
                return 20, 5
            end
            win.cursorSetScreenRow = function(_, row_offset, opts)
                cursor_calls[#cursor_calls + 1] = {
                    row_offset = row_offset,
                    screen_col = opts and opts.screen_col or nil,
                }
                win.cursory = row_offset + 1
                win.cursorx = opts and opts.screen_col or win.cursorx
            end
            win.scroll = function(_, dx, dy)
                scroll_calls[#scroll_calls + 1] = { dx = dx, dy = dy }
            end

            vimmode = "normal"

            Options.set("mouse", "nvi", false, win, buf, true)
            Options.set("mousemodel", "popup_setpos", false, win, buf, true)
            Options.set("mousetime", 500, false, win, buf, true)
            Options.set("mousescroll", "ver:3,hor:6", false, win, buf, true)

            Event.LoadCommandModule()

            Event.ProcessEvent({ "mouse_click", 1, 10, 3 })
            Assert.eq("left click row offset", cursor_calls[#cursor_calls].row_offset, 2)
            Assert.eq("left click screen col", cursor_calls[#cursor_calls].screen_col, 8)

            Event.ProcessEvent({ "mouse_click", 2, 9, 2 })
            Assert.eq("right click popup event count", #autocmd_calls, 1)
            Assert.eq("right click popup event name", autocmd_calls[1].event, "MenuPopup")
            Assert.eq("right click popup clicks", autocmd_calls[1].ctx.data.clicks, 1)

            Event.ProcessEvent({ "mouse_click", 2, 9, 2 })
            Assert.eq("double right click popup event count", #autocmd_calls, 2)
            Assert.eq("double right click click-count", autocmd_calls[2].ctx.data.clicks, 2)

            Event.ProcessEvent({ "mouse_click", 2, 9, 2 })
            Assert.eq("mousetime timeout resets count", autocmd_calls[3].ctx.data.clicks, 1)

            Options.set("mousemodel", "popup", false, win, buf, true)
            local cursor_before_popup_only = #cursor_calls
            Event.ProcessEvent({ "mouse_click", 2, 12, 2 })
            Assert.eq("popup model does not move cursor", #cursor_calls, cursor_before_popup_only)
            Assert.eq("popup model still runs MenuPopup", autocmd_calls[#autocmd_calls].event, "MenuPopup")

            local scroll_before = #scroll_calls
            Event.ProcessEvent({ "mouse_scroll", "down", 12, 2 })
            Assert.eq("scroll down uses mousescroll amount", scroll_calls[scroll_before + 1].dy, 3)

            Event.ProcessEvent({ "key", keys.leftShift })
            Event.ProcessEvent({ "mouse_scroll", "up", 12, 2 })
            Assert.eq("shift+scroll uses page amount", scroll_calls[#scroll_calls].dy, -5)
            Event.ProcessEvent({ "key_up", keys.leftShift })

            local scroll_before_horizontal = #scroll_calls
            Event.ProcessEvent({ "mouse_scroll", "right", 12, 2 })
            Assert.eq("horizontal scroll uses hor amount", scroll_calls[scroll_before_horizontal + 1].dx, 6)

            Options.set("mouse", "nv", false, win, buf, true)
            Options.set("mousemodel", "extend", false, win, buf, true)
            Assert.eq("extend mousemodel applies", options.get("mousemodel"), "extend")
            mock.globals().vimmode = "normal"
            win.cursory = 1
            win.cursorx = 1
            win.scrollx = 1
            Event.ProcessEvent({ "mouse_click", 2, 9, 2 })
            Assert.eq("right click starts Visual mode in extend model", mock.globals().vimmode, "visual")
            Assert.deep_eq("right click keeps the old cursor as Visual anchor", win.visual_anchor, {
                lnum = 1,
                col = 1,
            })
            Assert.eq("right click moves the Visual endpoint row", win.cursory, 2)
            Assert.eq("right click moves the Visual endpoint column", win.cursorx, 5)

            Event.ProcessEvent({ "mouse_click", 1, 10, 3 })
            Assert.eq("left click cancels Visual mode", mock.globals().vimmode, "normal")

            mock.globals().vimmode = "normal"
            win.cursory = 1
            win.cursorx = 1
            Event.ProcessEvent({ "mouse_click", 1, 6, 1 })
            Event.ProcessEvent({ "mouse_drag", 1, 9, 2 })
            Assert.eq("left drag starts Visual mode in extend model", mock.globals().vimmode, "visual")
            Assert.deep_eq("left drag anchors at mouse-down position", win.visual_anchor, {
                lnum = 1,
                col = 2,
            })
            Assert.eq("left drag moves the Visual endpoint row", win.cursory, 2)
            Assert.eq("left drag moves the Visual endpoint column", win.cursorx, 5)
            Event.ProcessEvent({ "mouse_up", 1, 9, 2 })

            mock.globals().vimmode = "visual"
            win.visual_kind = "char"
            win.visual_anchor = { lnum = 1, col = 1 }
            win.cursory = 3
            win.cursorx = 3
            Event.ProcessEvent({ "mouse_click", 2, 6, 1 })
            Assert.deep_eq("right click moves the nearest Visual endpoint", win.visual_anchor, {
                lnum = 3,
                col = 3,
            })
            Assert.eq("right click moves the selected nearest endpoint row", win.cursory, 1)
            Assert.eq("right click moves the selected nearest endpoint column", win.cursorx, 2)
            Event.ProcessEvent({ "mouse_up", 2, 6, 1 })

            Options.set("mousemodel", "popup", false, win, buf, true)
            mock.globals().vimmode = "normal"
            win.cursory = 1
            win.cursorx = 1
            Event.ProcessEvent({ "key", keys.leftShift })
            Event.ProcessEvent({ "mouse_click", 1, 9, 2 })
            Event.ProcessEvent({ "key_up", keys.leftShift })
            Assert.eq("popup Shift-left starts Visual mode", mock.globals().vimmode, "visual")
            Assert.deep_eq("popup Shift-left anchors at the old cursor", win.visual_anchor, {
                lnum = 1,
                col = 1,
            })
            Assert.eq("popup Shift-left moves the Visual endpoint row", win.cursory, 2)
            Assert.eq("popup Shift-left moves the Visual endpoint column", win.cursorx, 5)
            Event.ProcessEvent({ "mouse_up", 1, 9, 2 })

            Options.set("mousemodel", "extend", false, win, buf, true)
            mock.globals().vimmode = "normal"
            win.cursory = 1
            win.cursorx = 1
            Event.ProcessEvent({ "key", keys.leftAlt })
            Event.ProcessEvent({ "mouse_click", 2, 9, 2 })
            Event.ProcessEvent({ "key_up", keys.leftAlt })
            Assert.eq("Alt-right starts blockwise Visual mode", win.visual_kind, "block")
            Event.ProcessEvent({ "mouse_up", 2, 9, 2 })

            Options.set("mousemodel", "popup_setpos", false, win, buf, true)
            mock.globals().vimmode = "visual"
            win.visual_kind = "char"
            win.visual_anchor = { lnum = 1, col = 1 }
            win.cursory = 1
            win.cursorx = 2
            Event.ProcessEvent({ "mouse_click", 2, 9, 3 })
            Assert.eq("popup_setpos right click outside selection exits Visual mode", mock.globals().vimmode, "normal")
            Event.ProcessEvent({ "mouse_up", 2, 9, 3 })

            Options.set("mousemodel", "extend", false, win, buf, true)
            mock.globals().vimmode = "normal"
            win.cursory = 1
            win.cursorx = 1
            Event.ProcessEvent({ "mouse_click", 2, 6, 1 })
            Event.ProcessEvent({ "mouse_up", 2, 9, 2 })
            Assert.eq("right release extends the Visual endpoint row", win.cursory, 2)
            Assert.eq("right release extends the Visual endpoint column", win.cursorx, 5)

            Options.set("mouse", "", false, win, buf, true)
            local cursor_before_disabled = #cursor_calls
            Event.ProcessEvent({ "mouse_click", 1, 10, 3 })
            Assert.eq("mouse disabled ignores click", #cursor_calls, cursor_before_disabled)

            Assert.eq("v:mouse_win populated", Scopes._v.mouse_win, win.winnr)
            Assert.truthy("v:mouse_col populated", type(Scopes._v.mouse_col) == "number", Scopes._v.mouse_col)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
