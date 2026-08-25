local function cell_rows(mock)
    local cells = mock.term_cells()
    local rows = {}
    for y = 1, #cells do
        local row = {}
        for x = 1, #cells[y] do
            row[x] = cells[y][x].ch
        end
        rows[y] = table.concat(row)
    end
    return rows
end

local function contains(rows, text)
    for i = 1, #rows do
        local col = rows[i]:find(text, 1, true)
        if col then
            return i, col
        end
    end
end

return {
    id = "runtime.startup_intro_parity",
    description = "Matches startup intro layout, eligibility loss, suppression, and buffer redraw behavior against Neovim.", -- luacheck: ignore 631

    run = function(ctx)
        local Assert = ctx.assert

        if ctx.backend.name == "headless_nvim" then
            local function native_rows(setup)
                local result, err = ctx.backend:eval_ui_block(setup, [[
                    local rows = {}
                    for y = 1, vim.o.lines do
                        local row = {}
                        for x = 1, vim.o.columns do
                            row[x] = vim.fn.screenstring(y, x)
                        end
                        rows[y] = table.concat(row)
                    end
                    return rows
                ]])
                Assert.truthy("native intro screen", result ~= nil, err)
                return result
            end

            local rows = native_rows([[vim.opt.shortmess:remove("I")]])
            local open_row, open_col = contains(rows, "Nvim is open source and freely distributable")
            Assert.eq("native intro open-source row", open_row, 8)
            Assert.eq("native intro open-source centering", open_col, 19)
            Assert.eq("native intro preserves end-of-buffer marker", rows[open_row]:sub(1, 1), "~")
            Assert.truthy("native intro help line", contains(rows, "type  :help nvim<Enter>       if you are new!") ~= nil) -- luacheck: ignore 631

            local named = native_rows([[vim.opt.shortmess:remove("I"); vim.api.nvim_buf_set_name(0, "named.lua")]])
            Assert.eq("native named buffer suppresses intro", contains(named, "open source"), nil)

            local suppressed = native_rows([[vim.opt.shortmess:append("I")]])
            Assert.eq("native shortmess I suppresses intro", contains(suppressed, "open source"), nil)

            local split = native_rows([[vim.opt.shortmess:remove("I"); vim.cmd("split")]])
            Assert.eq("native split suppresses intro", contains(split, "open source"), nil)

            local lost = native_rows([[
                vim.opt.shortmess:remove("I")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x" })
                vim.cmd("redraw")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
            ]])
            Assert.eq("native intro does not return after editing", contains(lost, "open source"), nil)

            local dismissed, dismiss_err = ctx.backend:eval_ui_block([[
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(":intro<CR><CR>", true, false, true), "nt", false)
            ]], [[return { vim.v.errmsg, vim.api.nvim_buf_get_lines(0, 0, -1, false) }]])
            Assert.eq("native :intro dismissal error", dismiss_err, nil)
            Assert.eq("native :intro error message", dismissed[1], "")
            Assert.table_eq("native :intro preserves buffer", dismissed[2], { "" })
            return
        end

        local MockEnv = require("vim.tests.test_mocks")

        local function local_screen(mutate)
            local mock = MockEnv.setup({ bootstrap_default_editor = false, term_width = 80, term_height = 24 })
            local globals = mock.globals()
            if mutate then
                mutate(globals, mock)
            end
            globals.what_redraw.all = true
            globals.tabpages[globals.curtp]:render()
            local rows = cell_rows(mock)
            mock.cleanup()
            return rows
        end

        local rows = local_screen()
        local open_row, open_col = contains(rows, "CCVim is open source and freely distributable")
        Assert.eq("CCVim intro open-source row", open_row, 8)
        Assert.eq("CCVim intro open-source centering", open_col, 18)
        Assert.eq("CCVim intro preserves end-of-buffer marker", rows[open_row]:sub(1, 1), "~")
        Assert.truthy("CCVim intro help line", contains(rows, "type  :help nvim<Enter>       if you are new!") ~= nil)

        local named = local_screen(function(globals)
            globals.windows[globals.curwin].buffer.name = "named.lua"
        end)
        Assert.eq("CCVim named buffer suppresses intro", contains(named, "open source"), nil)

        local suppressed = local_screen(function(globals)
            globals.options.set("shortmess", globals.options.get("shortmess") .. "I")
        end)
        Assert.eq("CCVim shortmess I suppresses intro", contains(suppressed, "open source"), nil)

        local split = local_screen(function(globals, mock)
            local win = globals.windows[globals.curwin]
            local other = mock.loadModule("layout.window")(win.buffer)
            globals.tabpages[globals.curtp]:WinSplit(win.winnr, other, true)
        end)
        Assert.eq("CCVim split suppresses intro", contains(split, "open source"), nil)

        local resized = local_screen(function(globals, mock)
            mock.loadModule("lib.frame").ApplyTerminalResize(49, 24)
            globals.what_redraw.all = true
            globals.tabpages[globals.curtp]:render()
            Assert.eq("CCVim narrow screen defers intro", contains(cell_rows(mock), "open source"), nil)
            mock.loadModule("lib.frame").ApplyTerminalResize(80, 24)
        end)
        Assert.eq("CCVim intro appears after widening", contains(resized, "open source"), 8)

        local lost = local_screen(function(globals, mock)
            local tabpage = globals.tabpages[globals.curtp]
            local buffer = globals.windows[globals.curwin].buffer
            buffer.lines[1] = "x"
            globals.what_redraw.all = true
            tabpage:render()
            buffer.lines[1] = ""
            globals.what_redraw.all = true
            tabpage:render()
            local rows_after = cell_rows(mock)
            Assert.eq("CCVim intro does not return after editing", contains(rows_after, "open source"), nil)
        end)
        Assert.eq("CCVim remains clear after lost eligibility", contains(lost, "open source"), nil)

        local dismissed = local_screen(function(globals, mock)
            local tabpage = globals.tabpages[globals.curtp]
            globals.windows[globals.curwin].buffer.lines[1] = "underlying text"
            local ok, err = mock.loadModule("lib.excmd.runtime").run("intro")
            Assert.truthy("CCVim :intro command", ok, err)
            globals.what_redraw.all = true
            tabpage:render()
            local intro = cell_rows(mock)
            Assert.truthy("CCVim :intro redisplays intro", contains(intro, "CCVim is open source") ~= nil)
            Assert.truthy("CCVim :intro prompts for return", contains(intro, "Press ENTER or type command") ~= nil)
            mock.loadModule("lib.command").HandleKey(mock.loadModule("lib.key"):new(keys.enter))
            globals.what_redraw.all = true
            tabpage:render()
        end)
        Assert.truthy("CCVim :intro restores buffer", dismissed[1]:find("underlying text", 1, true) ~= nil)
    end,
}
