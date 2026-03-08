return {
    id = "runtime.extmark_text_render",
    description = "Ports extmark virtual text and virtual line rendering through the real Window render path; lua-editor-only because it asserts CCVim terminal grid output.",
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

            screen.width = 24
            screen.height = 8

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
            buf.name = "/tmp/extmark-text.txt"
            buf.lines = { "abc", "xyz" }
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

            local function row_text(grid, y, x, width)
                local out = {}
                for col = x, x + width - 1 do
                    out[#out + 1] = grid[y][col]
                end
                return table.concat(out)
            end

            local ns = api.nvim_create_namespace("extmark.text.render")

            local base_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("baseline text", row_text(base_grid, frame_y, frame_x, 6), "abc   ")

            api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 1, {
                virt_text = { { "X", "ErrorMsg" } },
                virt_text_pos = "overlay",
            })
            local overlay_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("overlay virt_text", row_text(overlay_grid, frame_y, frame_x, 6), "aXc   ")

            api.nvim_buf_clear_namespace(buf.bufnr, ns, 0, -1)
            api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 1, {
                virt_text = { { "ZZ", "ErrorMsg" } },
                virt_text_pos = "inline",
            })
            local inline_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("inline virt_text", row_text(inline_grid, frame_y, frame_x, 8), "aZZbc   ")

            api.nvim_buf_clear_namespace(buf.bufnr, ns, 0, -1)
            api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 3, {
                virt_text = { { "_H", "Comment" } },
                virt_text_pos = "eol",
            })
            local eol_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("eol virt_text", row_text(eol_grid, frame_y, frame_x, 8), "abc_H   ")

            api.nvim_buf_clear_namespace(buf.bufnr, ns, 0, -1)
            api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 0, {
                virt_lines = {
                    { { "vv", "Comment" } },
                },
            })
            local virt_lines_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("virt_lines draws below line", row_text(virt_lines_grid, frame_y + 1, frame_x, 6), "vv    ")

            api.nvim_buf_clear_namespace(buf.bufnr, ns, 0, -1)
            api.nvim_buf_set_extmark(buf.bufnr, ns, 0, 0, {
                hl_group = "Search",
                end_line = 0,
                end_col = 2,
            })
            local hl_grid = capture_grid(function()
                win:render(frame_x, frame_y)
            end)
            Assert.eq("hl_group extmark keeps text", row_text(hl_grid, frame_y, frame_x, 6), "abc   ")
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
