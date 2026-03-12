return {
    id = "runtime.window_syntax_blit_render",
    description = "Ports window rendering of syntax blit colors through the real Window render path; lua-editor-only because it asserts CCVim terminal grid output rather than editor-visible text alone.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local FrameTree = mock.loadModule("lib.frame")
            local Syntax = mock.loadModule("lib.syntax")

            screen.width = 12
            screen.height = 4

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("number", false, false, nil, nil, true)
            Options.set("relativenumber", false, false, nil, nil, true)
            Options.set("linebreak", false, false, nil, nil, true)
            Options.set("wrap", false, false, nil, nil, true)
            Options.set("signcolumn", "no", false, nil, nil, true)

            local tab = tabpages[curtp]
            tab:updateFrameview()

            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/window-syntax-blit-render.txt"
            buf.lines = { "abc" }
            buf.loaded = true
            win.cursorx = 4
            win.cursory = 1

            local old_lines_to_blit = Syntax.LinesToBlit
            Syntax.LinesToBlit = function(_, first_line, last_line, _)
                local out = {}
                for ln = first_line, last_line do
                    if ln == 1 then
                        out[ln] = {
                            fg = "012",
                            bg = "fff",
                        }
                    end
                end
                return out
            end

            local frame_x, frame_y = FrameTree.GetXY(win.frame)
            local render_ok, render_err = pcall(function()
                win:render(frame_x, frame_y)
            end)

            Syntax.LinesToBlit = old_lines_to_blit

            Assert.eq("render succeeds", render_ok, true)
            if not render_ok then
                error(render_err)
            end

            local cells = mock.term_cells()
            Assert.eq("first cell text", cells[frame_y][frame_x].ch, "a")
            Assert.eq("second cell text", cells[frame_y][frame_x + 1].ch, "b")
            Assert.eq("third cell text", cells[frame_y][frame_x + 2].ch, "c")
            Assert.eq("first cell fg", cells[frame_y][frame_x].fg, "0")
            Assert.eq("second cell fg", cells[frame_y][frame_x + 1].fg, "1")
            Assert.eq("third cell fg", cells[frame_y][frame_x + 2].fg, "2")
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
