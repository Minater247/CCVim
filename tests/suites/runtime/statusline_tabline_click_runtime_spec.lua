return {
    id = "runtime.statusline_tabline_click",
    description = "Exercises statusline/tabline click zones on the real renderer and mouse bridge; lua-editor-only because it asserts CCVim's internal click metadata and event dispatch.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local function find_zone(zones, kind, tabnr)
            for i = 1, #(zones or {}) do
                local zone = zones[i]
                if zone.kind == kind and (tabnr == nil or zone.tabnr == tabnr) then
                    return zone
                end
            end
            return nil
        end

        local function run_tabline_case()
            local mock = MockEnv.setup({ bootstrap_default_editor = true })
            local ok, err = pcall(function()
                local Event = mock.loadModule("lib.event")
                local Options = mock.loadModule("lib.options")
                local G = mock.globals()

                local function row_text(y)
                    local cells = mock.term_cells()[y]
                    local chars = {}
                    for x = 1, #cells do
                        chars[x] = cells[x].ch
                    end
                    return table.concat(chars)
                end

                Event.LoadCommandModule()

                screen.width = 30
                screen.height = 8

                local win1 = G.windows[G.curwin]
                local buf1 = win1.buffer
                buf1.lines = { "one", "two", "three" }
                buf1.loaded = true
                buf1.refcount = 1

                local buf2 = mock.create_buffer(2, "/tmp/other.txt", { "alt" }, { refcount = 1 })
                local win2 = mock.create_window(2, buf2, { cursorx = 1, cursory = 1 })
                mock.create_tabpage(2, { win2 }, {})

                Options.set("cmdheight", 1, false, nil, nil, true)
                Options.set("showtabline", 2, false, nil, nil, true)
                Options.set("tabline", "", false, nil, nil, true)

                G.curtp = 1
                G.curwin = 1
                G.tabpages[G.curtp]:render()

                local default_row = row_text(1)
                Assert.truthy(
                    "default tabline renders [No Name] for unnamed current buffer",
                    default_row:find("%[No Name%]", 1) ~= nil,
                    default_row
                )

                buf1.name = "/tmp/current.txt"
                G.tabpages[G.curtp]:render()
                default_row = row_text(1)
                Assert.truthy(
                    "default tabline renders current buffer tail",
                    default_row:find("current.txt", 1, true) ~= nil,
                    default_row
                )
                Assert.truthy(
                    "default tabline renders close label",
                    default_row:find("close", 1, true) ~= nil,
                    default_row
                )

                local switch_zone = find_zone(G.tabpages[G.curtp].tabline_click_zones, "tab", 2)
                Assert.truthy("default tabline exposes click zone for second tab", switch_zone ~= nil)

                Event.ProcessEvent({ "mouse_click", 1, switch_zone.start_col, 1 })
                Assert.eq("left click tabline switches tab", G.curtp, 2)

                G.tabpages[G.curtp]:render()
                local close_zone = find_zone(G.tabpages[G.curtp].tabline_click_zones, "close_tab", 999)
                Assert.truthy("default tabline exposes close-current zone", close_zone ~= nil)

                Event.ProcessEvent({ "mouse_click", 1, close_zone.start_col, 1 })
                Assert.eq("close-current click returns to first tab", G.curtp, 1)
                Assert.eq("close-current click removes second tab", G.tabpages[2], nil)
            end)
            mock.cleanup()
            if not ok then
                error(err)
            end
        end

        local function run_statusline_case()
            local mock = MockEnv.setup({ bootstrap_default_editor = true })
            local ok, err = pcall(function()
                local Event = mock.loadModule("lib.event")
                local Options = mock.loadModule("lib.options")
                local Runtime = mock.loadModule("lib.excmd.runtime")
                local Scopes = mock.loadModule("lib.luaapi.scopes")
                local G = mock.globals()

                Event.LoadCommandModule()

                screen.width = 30
                screen.height = 8

                local define_ok, define_err = Runtime.run([[
function! TestStatusClick(minwid, clicks, button, mods)
  let g:statusline_click = [a:minwid, a:clicks, a:button, a:mods]
  return ''
endfunction
                ]], { script_ctx = "/tmp/statusline_click_runtime.vim" })
                Assert.eq("statusline click callback definition compiles", define_ok, true)
                if define_ok ~= true then
                    error(define_err)
                end

                Options.set("cmdheight", 1, false, nil, nil, true)
                Options.set("showtabline", 0, false, nil, nil, true)
                Options.set("statusline", "%7@TestStatusClick@click me%X", false, nil, nil, true)

                G.tabpages[G.curtp]:render()
                local zone = find_zone(G.windows[G.curwin].statusline_click_zones, "function", nil)
                Assert.truthy("statusline exposes function click zone", zone ~= nil)

                Event.ProcessEvent({ "mouse_click", 1, zone.start_col, G.windows[G.curwin].frame.height })
                Assert.table_eq(
                    "statusline callback receives click args",
                    Scopes._g.statusline_click,
                    { 7, 1, "l", "" }
                )
            end)
            mock.cleanup()
            if not ok then
                error(err)
            end
        end

        local function run_sparse_tabline_case()
            local mock = MockEnv.setup({ bootstrap_default_editor = true })
            local ok, err = pcall(function()
                local Options = mock.loadModule("lib.options")
                local Fn = mock.loadModule("lib.luaapi.fn")
                local G = mock.globals()

                local function row_text(y)
                    local cells = mock.term_cells()[y]
                    local chars = {}
                    for x = 1, #cells do
                        chars[x] = cells[x].ch
                    end
                    return table.concat(chars)
                end

                screen.width = 30
                screen.height = 8

                local win1 = G.windows[G.curwin]
                win1.buffer.name = "/tmp/current.txt"
                win1.buffer.loaded = true
                win1.buffer.refcount = 1

                local buf2 = mock.create_buffer(2, "/tmp/other.txt", { "alt" }, { refcount = 1 })
                local win2 = mock.create_window(2, buf2, { cursorx = 1, cursory = 1 })
                mock.create_tabpage(2, { win2 }, {})

                Options.set("cmdheight", 1, false, nil, nil, true)
                Options.set("showtabline", 2, false, nil, nil, true)
                Options.set("tabline", "", false, nil, nil, true)

                local close_ok = G.tabpages[1]:close(win1, false)
                Assert.eq("closing first tab succeeds", close_ok, true)
                Assert.eq("current tab moves to surviving sparse tab", G.curtp, 2)
                Assert.eq("closed tab is removed", G.tabpages[1], nil)
                Assert.eq("tab count reflects sparse storage", Fn.fn.tabpagenr("$"), 1)

                G.tabpages[G.curtp]:render()
                local default_row = row_text(1)
                Assert.truthy(
                    "surviving tabline renders remaining tab label",
                    default_row:find("other.txt", 1, true) ~= nil,
                    default_row
                )
                Assert.truthy(
                    "surviving tabline omits close label for one remaining tab",
                    default_row:find("close", 1, true) == nil,
                    default_row
                )
            end)
            mock.cleanup()
            if not ok then
                error(err)
            end
        end

        run_tabline_case()
        run_sparse_tabline_case()
        run_statusline_case()
    end,
}
