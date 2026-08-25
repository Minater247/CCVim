return {
    id = "runtime.write_statusline",
    description = "Verifies that writing a modified buffer invalidates and refreshes its statusline; lua-editor-only because it asserts CCVim renderer state.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({ bootstrap_default_editor = true })
        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local G = mock.globals()

            local function rendered_text()
                local rows = mock.term_cells()
                local out = {}
                for y = 1, #rows do
                    local chars = {}
                    for x = 1, #rows[y] do
                        chars[x] = rows[y][x].ch
                    end
                    out[y] = table.concat(chars)
                end
                return table.concat(out, "\n")
            end

            screen.width = 20
            screen.height = 8

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 2, false, nil, nil, true)
            Options.set("statusline", "%m", false, nil, nil, true)

            local win = G.windows[G.curwin]
            local buf = win.buffer
            buf.name = "/tmp/write-statusline.txt"
            buf.lines = { "changed" }
            buf.opts.modified = true

            G.tabpages[G.curtp]:render()
            Assert.truthy(
                "modified buffer renders statusline marker before write",
                rendered_text():find("[+]", 1, true) ~= nil
            )

            need_redraw = false
            what_redraw = {}

            Assert.eq("writing modified buffer succeeds", buf:write(false), true)
            Assert.eq("writing clears modified flag", buf.opts.modified, false)
            Assert.eq("writing invalidates the statusline render", need_redraw, true)

            G.tabpages[G.curtp]:render()
            Assert.eq(
                "written buffer no longer renders modified marker",
                rendered_text():find("[+]", 1, true),
                nil
            )
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
