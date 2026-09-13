return {
    id = "runtime.diff_render",
    description = "Checks changed text, added lines, and filler rows in the CCVim diff renderer.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")
        local mock = MockEnv.setup({ term_width = 32, term_height = 8 })

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Highlight = mock.loadModule("lib.highlight")
            local FrameTree = mock.loadModule("lib.frame")
            local Tabpage = mock.loadModule("layout.tabpage")

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("number", false, false, nil, nil, true)
            Options.set("relativenumber", false, false, nil, nil, true)
            Options.set("signcolumn", "no", false, nil, nil, true)
            Options.set("diffopt", "internal,filler,closeoff,linematch:40")

            local tab = tabpages[curtp]
            local left = windows[curwin]
            left.buffer.lines = { "same", "left", "tail" }
            left.buffer.loaded = true
            left.opts.diff = true
            left.opts.wrap = false

            local right_buffer = mock.create_buffer(2, "/tmp/diff-right", { "same", "right", "extra", "tail" })
            local right = mock.create_window(2, right_buffer, {})
            right.opts.diff = true
            right.opts.wrap = false
            Assert.eq("split succeeds", Tabpage.WinSplit(tab, left.winnr, right, true), true)
            tab:updateFrameview()

            local ids = {}
            local old_grid_line = screen.grid_line
            screen.grid_line = function(grid, row, col, cells, wrap)
                local current = 0
                ids[row + 1] = ids[row + 1] or {}
                local x = col + 1
                for i = 1, #cells do
                    local cell = cells[i]
                    if cell[2] ~= nil then current = cell[2] end
                    local repetitions = cell[3] or 1
                    for offset = 0, repetitions - 1 do ids[row + 1][x + offset] = current end
                    x = x + repetitions
                end
                return old_grid_line(grid, row, col, cells, wrap)
            end

            local left_x, left_y = FrameTree.GetXY(left.frame)
            left:render(left_x, left_y)
            local right_x, right_y = FrameTree.GetXY(right.frame)
            right:render(right_x, right_y)
            screen.grid_line = old_grid_line

            local left_text_x = select(2, left:textwidth())
            local right_text_x = select(2, right:textwidth())
            local diff_change = Highlight.GetId("DiffChange")
            local diff_text = Highlight.GetId("DiffText")
            local diff_add = Highlight.GetId("DiffAdd")
            local diff_delete = Highlight.GetId("DiffDelete")

            local add_attrs = Highlight.AttrsFor("DiffAdd", 0, true)
            local change_attrs = Highlight.AttrsFor("DiffChange", 0, true)
            local delete_attrs = Highlight.AttrsFor("DiffDelete", 0, true)
            local text_attrs = Highlight.AttrsFor("DiffText", 0, true)

            Assert.eq("DiffAdd foreground", add_attrs.fg, 0x111111)
            Assert.eq("DiffAdd background", add_attrs.bg, 0x57A64E)
            Assert.eq("DiffChange foreground", change_attrs.fg, nil)
            Assert.eq("DiffChange background", change_attrs.bg, 0x4C4C4C)
            Assert.eq("DiffDelete foreground", delete_attrs.fg, 0xCC4C4C)
            Assert.eq("DiffDelete background", delete_attrs.bg, nil)
            Assert.eq("DiffText foreground", text_attrs.fg, 0x111111)
            Assert.eq("DiffText background", text_attrs.bg, 0x4C99B2)

            Assert.eq("left changed text uses DiffText", ids[left_y + 1][left_x + left_text_x], diff_text)
            Assert.eq("left changed line padding uses DiffChange",
                ids[left_y + 1][left_x + left_text_x + 6], diff_change)
            Assert.eq("missing left line uses DiffDelete filler", ids[left_y + 2][left_x + left_text_x], diff_delete)
            Assert.eq("extra right line uses DiffAdd", ids[right_y + 2][right_x + right_text_x], diff_add)
        end)

        mock.cleanup()
        if not ok then error(err) end
    end,
}
