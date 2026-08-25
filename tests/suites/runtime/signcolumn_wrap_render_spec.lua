return {
    id = "runtime.signcolumn_wrap_render",
    description = "Ports wrapped signcolumn rendering through the real Window render path; lua-editor-only because it asserts CCVim terminal grid output.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Sign = mock.loadModule("lib.sign")
            local FrameTree = mock.loadModule("lib.frame")

            screen.width = 10
            screen.height = 6

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("linebreak", false, false, nil, nil, true)
            Options.set("signcolumn", "auto", false, nil, nil, true)

            local tab = tabpages[curtp]
            tab:updateFrameview()

            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/signcolumn-wrap.txt"
            buf.lines = { "abcdefghi" }
            buf.loaded = true
            win.cursorx = 1
            win.cursory = 1
            Options.set("number", true, true, win, buf)
            Options.set("relativenumber", false, true, win, buf)
            Options.set("numberwidth", 4, true, win, buf)
            Options.set("wrap", true, true, win, buf)
            local frame_x, frame_y = FrameTree.GetXY(win.frame)

            local function capture_grid(render_fn)
                local grid = {}
                for y = 1, screen.height do
                    grid[y] = {}
                    for x = 1, screen.width do
                        grid[y][x] = " "
                    end
                end

                local cx, cy = 1, 1
                local old_set_cursor = term.setCursorPos
                local old_write = term.write
                local old_blit = term.blit

                local function write_text(text)
                    for i = 1, #text do
                        if grid[cy] and grid[cy][cx] then
                            grid[cy][cx] = text:sub(i, i)
                        end
                        cx = cx + 1
                    end
                end

                term.setCursorPos = function(x, y)
                    cx, cy = x, y
                end
                term.write = function(text)
                    write_text(text)
                end
                term.blit = function(text)
                    write_text(text)
                end

                local render_ok, render_err = pcall(render_fn)

                term.setCursorPos = old_set_cursor
                term.write = old_write
                term.blit = old_blit

                Assert.eq("render succeeds", render_ok, true)
                if not render_ok then
                    error(render_err)
                end

                return grid
            end

            Assert.eq("define sign", Sign.define("WrapSign", { text = "!!" }), 0)
            Assert.eq("place sign", Sign.place(1, "", "WrapSign", buf.bufnr, { lnum = 1 }), 1)

            local text_w, text_x, _, _, _, sign_w = win:textwidth()
            Assert.eq("signcolumn width", sign_w, 2)
            Assert.eq("text starts after sign+number columns", text_x, 7)
            Assert.eq("wrap width reduced by reserved columns", text_w, 4)

            local grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)

            Assert.eq("row1 sign column cell 1", grid[frame_y][frame_x], "!")
            Assert.eq("row1 sign column cell 2", grid[frame_y][frame_x + 1], "!")
            Assert.eq("row1 wrapped text starts at shifted column", grid[frame_y][frame_x + 6], "a")
            Assert.eq("row1 wrapped text chunk end", grid[frame_y][frame_x + 9], "d")

            Assert.eq("row2 continuation keeps sign column blank cell 1", grid[frame_y + 1][frame_x], " ")
            Assert.eq("row2 continuation keeps sign column blank cell 2", grid[frame_y + 1][frame_x + 1], " ")
            Assert.eq("row2 wrapped continuation starts at shifted column", grid[frame_y + 1][frame_x + 6], "e")
            Assert.eq("row2 wrapped continuation chunk end", grid[frame_y + 1][frame_x + 9], "h")

            Assert.eq("row3 final wrapped part starts at shifted column", grid[frame_y + 2][frame_x + 6], "i")
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
