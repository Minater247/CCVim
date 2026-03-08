return {
    id = "runtime.decoration_provider",
    description = "Ports decoration provider callbacks and ephemeral extmark cleanup on CCVim's runtime decoration path; lua-editor-only because it drives the internal redraw cycle directly to inspect per-cycle provider state.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local api = mock.loadModule("lib.luaapi.api")
            local Decoration = mock.loadModule("lib.decoration")
            local tab = tabpages[curtp]
            local win1 = windows[curwin]
            local Tabpage = mock.loadModule("layout.tabpage")

            local buf = win1.buffer
            buf.name = "/tmp/decoration-provider.txt"
            buf.lines = { "abc" }
            buf.loaded = true

            local win2 = mock.create_window(2, buf, {})
            Assert.eq("real split creates second window", Tabpage.WinSplit(tab, win1.winnr, win2, true), true)
            Assert.eq("tab now has two real windows", #tab.windows, 2)

            local calls = {}
            local on_buf_calls = 0
            local skipped_on_line_calls = 0

            local ns = api.nvim_create_namespace("decor.provider.test")
            api.nvim_set_decoration_provider(ns, {
                on_start = function(_, tick)
                    calls[#calls + 1] = "start:" .. tostring(tick)
                end,
                on_buf = function(_, bufnr, tick)
                    on_buf_calls = on_buf_calls + 1
                    calls[#calls + 1] = ("buf:%d:%d"):format(bufnr, tick)
                end,
                on_win = function(_, winid, bufnr, topline, botline)
                    calls[#calls + 1] = ("win:%d:%d:%d:%d"):format(winid, bufnr, topline, botline)
                end,
                on_line = function(_, _, bufnr, row)
                    calls[#calls + 1] = "line:" .. tostring(row)
                    api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
                        end_col = 1,
                        hl_group = "Search",
                        ephemeral = true,
                    })
                end,
                on_end = function(_, tick)
                    calls[#calls + 1] = "end:" .. tostring(tick)
                end,
            })

            local ns_skip = api.nvim_create_namespace("decor.provider.skip")
            api.nvim_set_decoration_provider(ns_skip, {
                on_win = function()
                    return false
                end,
                on_line = function()
                    skipped_on_line_calls = skipped_on_line_calls + 1
                end,
            })

            Decoration.begin_redraw()
            Decoration.on_window(win1, 0, 0)
            Decoration.on_line(win1, 0)
            Decoration.on_window(win2, 0, 0)
            Decoration.on_line(win2, 0)

            local ext_during = api.nvim_buf_get_extmarks(buf.bufnr, ns, { 0, 0 }, { 0, -1 }, {})
            Assert.eq("ephemeral marks visible during redraw", #ext_during, 2)

            Decoration.end_redraw()

            local ext_after = api.nvim_buf_get_extmarks(buf.bufnr, ns, { 0, 0 }, { 0, -1 }, {})
            Assert.eq("ephemeral marks cleared after redraw", #ext_after, 0)
            Assert.eq("on_buf called once per buffer per cycle", on_buf_calls, 1)
            Assert.eq("on_line skipped when on_win returns false", skipped_on_line_calls, 0)
            Assert.truthy("on_start fired first", calls[1] and calls[1]:match("^start:"), tostring(calls[1]))
            Assert.truthy("on_end fired last", calls[#calls] and calls[#calls]:match("^end:"), tostring(calls[#calls]))

            api.nvim_set_decoration_provider(ns, nil)
            calls = {}
            Decoration.begin_redraw()
            Decoration.on_window(win1, 0, 0)
            Decoration.on_line(win1, 0)
            Decoration.end_redraw()
            Assert.eq("provider removed", #calls, 0)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
