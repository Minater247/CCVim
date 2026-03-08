return {
    id = "runtime.signcolumn_render",
    description = "Ports signcolumn rendering through the real Window render path; lua-editor-only because it asserts CCVim terminal grid output.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Sign = mock.loadModule("lib.sign")
            local FrameTree = mock.loadModule("lib.frame")

            screen.width = 20
            screen.height = 6

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("number", false, false, nil, nil, true)
            Options.set("relativenumber", false, false, nil, nil, true)
            Options.set("linebreak", false, false, nil, nil, true)
            Options.set("wrap", false, false, nil, nil, true)
            Options.set("signcolumn", "auto", false, nil, nil, true)

            local tab = tabpages[curtp]
            tab:updateFrameview()

            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/signcolumn.txt"
            buf.lines = { "abc", "def" }
            buf.loaded = true
            win.cursorx = 1
            win.cursory = 1
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

            Assert.eq("define sign", Sign.define("WarnSign", { text = "!!" }), 0)
            Assert.eq("place sign", Sign.place(1, "", "WarnSign", buf.bufnr, { lnum = 1 }), 1)

            local _, text_x_before, _, _, _, sign_w_before = win:textwidth()
            Assert.eq("auto signcolumn reserves 2 cells when sign exists", sign_w_before, 2)
            Assert.eq("text starts after signcolumn", text_x_before, 3)

            local grid_before = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("sign text appears in signcolumn cell 1", grid_before[frame_y][frame_x], "!")
            Assert.eq("sign text appears in signcolumn cell 2", grid_before[frame_y][frame_x + 1], "!")
            Assert.eq("text shifts right when signcolumn is shown", grid_before[frame_y][frame_x + 2], "a")

            Assert.eq("unplace signs", Sign.unplace("*", { buffer = buf.bufnr }), 0)
            local _, text_x_after, _, _, _, sign_w_after = win:textwidth()
            Assert.eq("auto signcolumn collapses after last sign removed", sign_w_after, 0)
            Assert.eq("text starts at first column when signcolumn hidden", text_x_after, 1)

            local grid_after = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("buffer text now starts at first column", grid_after[frame_y][frame_x], "a")
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
