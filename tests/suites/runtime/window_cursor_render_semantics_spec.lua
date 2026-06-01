return {
    id = "runtime.window_cursor_render_semantics",
    description = "Ports deferred-wrap cursor rendering semantics through the real Window render path; lua-editor-only because it asserts CCVim terminal grid output.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()
        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Highlight = mock.loadModule("lib.highlight")
            local FrameTree = mock.loadModule("lib.frame")
            local Tabpage = mock.loadModule("layout.tabpage")
            local CmdRead = mock.loadModule("lib.excmd.cmdread")

            screen.width = 16
            screen.height = 6

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("number", false, false, nil, nil, true)
            Options.set("relativenumber", false, false, nil, nil, true)
            Options.set("linebreak", false, false, nil, nil, true)

            local tab = tabpages[curtp]
            local win1 = windows[curwin]
            local buf = win1.buffer
            buf.name = "/tmp/window_cursor_render.txt"
            buf.loaded = true

            Options.set("linebreak", false, true, win1, buf)
            Options.set("wrap", true, true, win1, buf)

            local win2 = mock.create_window(2, buf, {})
            Assert.eq("real split creates second window", Tabpage.WinSplit(tab, win1.winnr, win2, true), true)
            tab:updateFrameview()
            Options.set("linebreak", false, true, win2, buf)
            Options.set("wrap", true, true, win2, buf)

            local text_w = select(1, win1:textwidth())
            Assert.truthy("split window has visible text width", text_w > 0, text_w)
            buf.lines = { string.rep("x", text_w) }
            win1.cursory = 1
            win1.cursorx = text_w + 1
            win2.cursory = 1
            win2.cursorx = text_w + 1

            local function render_cursor_count(win)
                local cursor_writes = 0
                local frame_x, frame_y = FrameTree.GetXY(win.frame)
                local cursor_id = Highlight.GetId("Cursor")
                local text_x = select(2, win:textwidth())
                local target_row = frame_y
                local target_col = frame_x + text_x - 2

                local old_grid_line = screen.grid_line

                screen.grid_line = function(grid, row, col, cells)
                    local cx = col
                    for i = 1, #cells do
                        local cell = cells[i]
                        local rep = cell[3] or 1
                        if row == target_row and cell[2] == cursor_id
                            and target_col >= cx and target_col < (cx + rep)
                        then
                            cursor_writes = cursor_writes + (cell[3] or 1)
                        end
                        cx = cx + rep
                    end
                    return old_grid_line(grid, row, col, cells)
                end

                local render_ok, render_err = pcall(function()
                    win:render(frame_x, frame_y)
                end)

                screen.grid_line = old_grid_line

                Assert.eq("render succeeds", render_ok, true)
                if not render_ok then
                    error(render_err)
                end

                return cursor_writes
            end

            curwin = win1.winnr
            vimmode = "insert"
            Assert.truthy(
                "current window draws deferred-wrap cursor when cmdline inactive",
                render_cursor_count(win1) > 0
            )
            Assert.eq("non-current window does not draw cursor", render_cursor_count(win2), 0)

            CmdRead.read()
            Assert.eq("cmdline-active current window suppresses cursor draw", render_cursor_count(win1), 0)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
