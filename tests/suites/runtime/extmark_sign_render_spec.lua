return {
    id = "runtime.extmark_sign_render",
    description = "Ports extmark sign rendering through the real Window render path; lua-editor-only because it asserts CCVim terminal grid output.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            _G.options = Options
            local api = mock.loadModule("lib.luaapi.api")
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
            buf.name = "/tmp/extmark-sign.txt"
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

            local ns = api.nvim_create_namespace("extmark.sign.test")
            local mark_id = api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 0, {})
            api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 0, {
                id = mark_id,
                sign_text = "!!",
                sign_hl_group = "ErrorMsg",
                line_hl_group = "Search",
                invalidate = true,
            })

            local marks = api.nvim_buf_get_extmarks(buf.bufnr, ns, { 0, 0 }, { 0, -1 }, { details = true })
            Assert.eq("one extmark returned", #marks, 1)
            Assert.eq("extmark id preserved", marks[1][1], mark_id)
            Assert.eq("extmark sign text in details", marks[1][4].sign_text, "!!")

            local _, text_x, _, _, _, sign_w = win:textwidth()
            Assert.eq("signcolumn visible for extmark signs", sign_w, 2)
            Assert.eq("text starts after extmark signcolumn", text_x, 3)

            local bang_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("extmark sign first cell", bang_grid[frame_y][frame_x], "!")
            Assert.eq("extmark sign second cell", bang_grid[frame_y][frame_x + 1], "!")

            api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 0, {
                id = mark_id,
                sign_text = "✓",
                sign_hl_group = "ErrorMsg",
                line_hl_group = "Search",
                invalidate = true,
            })

            local check_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("unicode check sign maps to ascii fallback", check_grid[frame_y][frame_x], "v")
            Assert.eq("unicode check sign keeps padding", check_grid[frame_y][frame_x + 1], " ")

            api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 0, {
                id = mark_id,
                sign_text = "✗",
                sign_hl_group = "ErrorMsg",
                line_hl_group = "Search",
                invalidate = true,
            })

            local cross_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("unicode cross sign maps to ascii fallback", cross_grid[frame_y][frame_x], "x")
            Assert.eq("unicode cross sign keeps padding", cross_grid[frame_y][frame_x + 1], " ")
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
