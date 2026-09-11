return {
    id = "runtime.incremental_search_render",
    description = "Checks live search movement, highlighting, cancellation, and search options in the CCVim grid",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")
        local mock = MockEnv.setup({ term_width = 24, term_height = 6 })

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Highlight = mock.loadModule("lib.highlight")
            local FrameTree = mock.loadModule("lib.frame")
            local Event = mock.loadModule("lib.event")
            local Key = mock.loadModule("lib.key")
            local CmdRead = mock.loadModule("lib.excmd.cmdread")

            Event.LoadCommandModule()
            mock.loadModule("lib.mappings", { immediate = true })
            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("number", false, false, nil, nil, true)
            Options.set("relativenumber", false, false, nil, nil, true)
            Options.set("wrap", false, false, nil, nil, true)
            Options.set("signcolumn", "no", false, nil, nil, true)

            local tab = tabpages[curtp]
            tab:updateFrameview()
            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/incremental-search.txt"
            buf.lines = {
                "alpha beta alpha",
                "Beta ALPHA beta",
                "third alpha line",
            }
            buf.loaded = true
            win:_set_cursor_raw(1, 1)

            local function flush()
                if need_redraw then
                    tab:render()
                    need_redraw = false
                    what_redraw = {}
                    _G.what_redraw = what_redraw
                end
            end

            local function feed_code(code)
                Event.ProcessEvent({ "key", code })
                flush()
            end

            local function feed_text(text)
                local seq = Key.strtoseq(text)
                for i = 1, #seq do feed_code(seq[i].numeric) end
            end

            local function start_forward()
                feed_code(keys.slash)
                Assert.eq("forward search prompt active", CmdRead.gettype(), "/")
            end

            local function render_ids()
                local ids = {}
                local old_grid_line = screen.grid_line
                screen.grid_line = function(grid, row, col, cells, wrap)
                    local current = 0
                    local x = col + 1
                    ids[row + 1] = ids[row + 1] or {}
                    for i = 1, #cells do
                        local cell = cells[i]
                        if cell[2] ~= nil then current = cell[2] end
                        local rep = cell[3] or 1
                        for offset = 0, rep - 1 do
                            ids[row + 1][x + offset] = current
                        end
                        x = x + rep
                    end
                    return old_grid_line(grid, row, col, cells, wrap)
                end
                local frame_x, frame_y = FrameTree.GetXY(win.frame)
                win:render(frame_x, frame_y)
                screen.grid_line = old_grid_line
                return ids, frame_x, frame_y
            end

            local search_id = Highlight.GetId("Search")
            local incsearch_id = Highlight.GetId("IncSearch")

            start_forward()
            feed_text("a")
            Assert.deep_eq("partial search moves immediately", { win.cursory, win.cursorx }, { 1, 5 })
            feed_text("l")
            Assert.deep_eq("extended search recomputes from origin", { win.cursory, win.cursorx }, { 1, 12 })

            local ids, frame_x, frame_y = render_ids()
            Assert.eq("other live match uses Search", ids[frame_y][frame_x + 1], search_id)
            Assert.eq("current live match uses IncSearch", ids[frame_y][frame_x + 12], incsearch_id)

            feed_text("z")
            Assert.deep_eq("nonmatch restores origin", { win.cursory, win.cursorx }, { 1, 1 })
            ids, frame_x, frame_y = render_ids()
            Assert.truthy("nonmatch clears live highlights", ids[frame_y][frame_x + 1] ~= search_id)

            feed_code(keys.backspace)
            Assert.deep_eq("backspace restores matching preview", { win.cursory, win.cursorx }, { 1, 12 })
            feed_text("<C-Tab>")
            Assert.deep_eq("Ctrl-Tab restores search origin", { win.cursory, win.cursorx }, { 1, 1 })
            Assert.eq("Ctrl-Tab closes search prompt", CmdRead.is_active(), false)

            Options.set("incsearch", false, false, nil, nil, true)
            start_forward()
            feed_text("al")
            Assert.deep_eq("noincsearch leaves cursor at origin", { win.cursory, win.cursorx }, { 1, 1 })
            ids, frame_x, frame_y = render_ids()
            Assert.truthy("noincsearch has no preview highlights", ids[frame_y][frame_x + 1] ~= search_id)
            feed_code(keys.enter)
            Assert.deep_eq("noincsearch moves after enter", { win.cursory, win.cursorx }, { 1, 12 })
            ids, frame_x, frame_y = render_ids()
            Assert.eq("completed search persists highlights", ids[frame_y][frame_x + 1], search_id)

            Options.set("incsearch", true, false, nil, nil, true)
            Options.set("hlsearch", false, false, nil, nil, true)
            win:cursorSet(1, 1)
            start_forward()
            feed_text("be")
            Assert.deep_eq("incsearch still moves with nohlsearch", { win.cursory, win.cursorx }, { 1, 7 })
            ids, frame_x, frame_y = render_ids()
            Assert.eq("current nohlsearch preview uses IncSearch", ids[frame_y][frame_x + 7], incsearch_id)
            Assert.truthy("nohlsearch omits other live matches", ids[frame_y + 1][frame_x + 12] ~= search_id)
            feed_code(keys.enter)
            ids, frame_x, frame_y = render_ids()
            Assert.truthy("nohlsearch omits completed highlights", ids[frame_y][frame_x + 7] ~= incsearch_id)

            Options.set("hlsearch", true, false, nil, nil, true)
            Event.ExecuteCommand(":nohlsearch")
            ids, frame_x, frame_y = render_ids()
            Assert.truthy("nohlsearch command suspends highlights", ids[frame_y][frame_x + 7] ~= search_id)
            Event.ExecuteCommand(":set hlsearch")
            ids, frame_x, frame_y = render_ids()
            Assert.eq("setting hlsearch restores highlights", ids[frame_y][frame_x + 7], search_id)
        end)

        mock.cleanup()
        if not ok then error(err) end
    end,
}
