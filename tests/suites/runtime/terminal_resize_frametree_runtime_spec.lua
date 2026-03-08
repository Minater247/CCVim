return {
    id = "runtime.terminal_resize_frametree",
    description = "Ports terminal resize behavior on the real frametree and autocmd runtime; lua-editor-only because it asserts CCVim internal layout state.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local FrameTree = mock.loadModule("lib.frame")
            local Tabpage = mock.loadModule("layout.tabpage")
            local Autocmd = mock.loadModule("lib.autocmd")

            screen.width = 80
            screen.height = 24

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("winminwidth", 1, false, nil, nil, true)
            Options.set("winminheight", 1, false, nil, nil, true)

            local vim_resized = 0
            local win_resized = 0
            local last_winresized = nil

            Autocmd.CreateAutocommand({ "VimResized" }, { "*" }, function()
                vim_resized = vim_resized + 1
            end, nil, 1, false, false)
            Autocmd.CreateAutocommand({ "WinResized" }, { "*" }, function(info)
                win_resized = win_resized + 1
                last_winresized = info
            end, nil, 1, false, false)

            local tab1 = tabpages[curtp]
            local win1 = windows[curwin]
            local buf1 = win1.buffer
            buf1.name = "/tmp/resize_a"
            buf1.lines = { "a" }
            buf1.loaded = true

            local buf2 = mock.create_buffer(2, "/tmp/resize_b", { "b" }, { refcount = 1 })
            local win2 = mock.create_window(2, buf2, {})
            Assert.eq("split tab1 with real second window", tab1:WinSplit(win1.winnr, win2, true), true)

            local buf3 = mock.create_buffer(3, "/tmp/resize_c", { "c" }, { refcount = 1 })
            local win3 = mock.create_window(3, buf3, {})
            local tab2 = Tabpage:new(win3)

            curtp = tab1.tabnr
            curwin = win1.winnr

            local ok_resize, changed = FrameTree.ApplyTerminalResize(100, 30, "term_resize")
            Assert.eq("resize success", ok_resize, true)
            Assert.eq("resize changed flag", changed, true)
            Assert.eq("screen width updated", screen.width, 100)
            Assert.eq("screen height updated", screen.height, 30)
            Assert.eq("columns updated", Options.get("columns"), 100)
            Assert.eq("lines updated", Options.get("lines"), 30)
            Assert.eq("tab1 width updated", tab1.tree.width, 100)
            Assert.eq("tab2 width updated", tab2.tree.width, 100)
            Assert.eq("tab1 height updated", tab1.tree.height, 29)
            Assert.eq("tab2 height updated", tab2.tree.height, 29)
            Assert.eq("VimResized fired once", vim_resized, 1)
            Assert.eq("WinResized fired once", win_resized, 1)
            Assert.truthy("WinResized payload present", type(last_winresized) == "table", "missing WinResized ctx")
            Assert.truthy(
                "WinResized windows list populated",
                #(last_winresized.data.windows or {}) >= 1,
                "expected changed window ids"
            )

            vim_resized = 0
            win_resized = 0
            last_winresized = nil
            need_redraw = false
            what_redraw = {}

            ok_resize, changed = FrameTree.ApplyTerminalResize(100, 30, "term_resize")
            Assert.eq("same-size resize succeeds", ok_resize, true)
            Assert.eq("same-size changed flag false", changed, false)
            Assert.eq("same-size emits no VimResized", vim_resized, 0)
            Assert.eq("same-size emits no WinResized", win_resized, 0)
            Assert.eq("same-size does not mark redraw", need_redraw, false)

            vim_resized = 0
            win_resized = 0
            Options.set("winminwidth", 70, false, nil, nil, true)
            need_redraw = false
            what_redraw = {}

            ok_resize, err = FrameTree.ApplyTerminalResize(80, 30, "term_resize")
            Assert.eq("strict failure returns false", ok_resize, false)
            Assert.truthy(
                "strict failure returns E36",
                type(err) == "table" and err.code == 36,
                tostring(err)
            )
            Assert.eq("strict failure keeps authoritative screen width", screen.width, 80)
            Assert.eq("strict failure keeps authoritative columns", Options.get("columns"), 80)
            Assert.eq("strict failure keeps old tree width (no fallback)", tab1.tree.width, 100)
            Assert.eq("strict failure still fires VimResized", vim_resized, 1)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
