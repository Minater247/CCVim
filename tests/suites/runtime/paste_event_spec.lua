return {
    id = "runtime.paste_event",
    description = "Handles host paste events through Neovim's hook with literal option-independent insertion in normal, insert, Select, and command-line modes.", -- luacheck: ignore 631

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "paste event parity", [[
            local function feed(text)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(text, true, false, true), "xt", false)
            end

            local function paste(text)
                if _G.loadModule then
                    loadModule("lib.event").ProcessEvent({ "paste", text })
                else
                    vim.api.nvim_paste(text, true, -1)
                end
            end

            local function reset(lines, col)
                feed("<Esc>")
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { 1, col or 0 })
            end

            reset({ "abc" }, 0)
            paste("X\r\nY")
            local normal = {
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.api.nvim_win_get_cursor(0),
                vim.fn.getpos("'["),
                vim.fn.getpos("']"),
            }

            reset({ "root" }, 0)
            vim.bo.autoindent = true
            vim.bo.expandtab = true
            vim.bo.cindent = true
            vim.bo.softtabstop = 4
            vim.bo.textwidth = 4
            vim.bo.formatoptions = "tcqj"
            vim.bo.indentexpr = "8"
            vim.bo.indentkeys = "o,O,*<Return>"
            vim.o.smarttab = true
            vim.keymap.set("i", "x", "MAPPED", { buffer = true })
            local insert
            vim.keymap.set("i", "<F5>", function()
                paste("\tx\r\n\tbeta")
                insert = {
                    vim.fn.mode(),
                    vim.api.nvim_buf_get_lines(0, 0, -1, false),
                    vim.api.nvim_win_get_cursor(0),
                    vim.bo.autoindent,
                    vim.bo.expandtab,
                    vim.bo.cindent,
                    vim.bo.softtabstop,
                    vim.bo.textwidth,
                    vim.bo.formatoptions,
                    vim.bo.indentexpr,
                    vim.bo.indentkeys,
                    vim.o.smarttab,
                }
            end, { buffer = true })
            feed("i<F5><Esc>")

            reset({ "abcdef" }, 1)
            feed("gh<Right>")
            paste("X\nY")
            local select_mode = {
                vim.fn.mode(),
                vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.api.nvim_win_get_cursor(0),
            }

            reset({ "abc" }, 0)
            local default_paste = vim.paste
            vim.paste = function(lines, phase)
                for i = 1, #lines do lines[i] = lines[i]:upper() end
                return default_paste(lines, phase)
            end
            paste("x")
            vim.paste = default_paste
            local custom = vim.api.nvim_get_current_line()

            return { normal, insert, select_mode, custom }
        ]])

        ctx.assert.deep_eq("paste event parity", result, {
            {
                { "aX", "Ybc" },
                { 2, 0 },
                { 0, 1, 2, 0 },
                { 0, 2, 1, 0 },
            },
            {
                "i",
                { "\tx", "\tbetaroot" },
                { 2, 5 },
                true,
                true,
                true,
                4,
                4,
                "tcqj",
                "8",
                "o,O,*<Return>",
                true,
            },
            { "n", { "aX", "Ydef" }, { 2, 0 } },
            "aXbc",
        })

        if ctx.backend.name == "lua_editor" then
            local transfer = ctx.assert.eval_block(ctx.backend, "full text file transfer", [[
                vim.cmd("enew!")
                loadModule("lib.event").ProcessEvent({ "file_transfer", {
                    getFiles = function()
                        return {
                            { readAll = function() return "first\nsecond" end, close = function() end },
                            { readAll = function() return "third" end, close = function() end },
                        }
                    end,
                } })
                return vim.api.nvim_buf_get_lines(0, 0, -1, false)
            ]])
            ctx.assert.deep_eq("file transfer preserves all lines", transfer, { "first", "second", "third" })
        end

        local cmdline, cmdline_err = ctx.backend:eval_ui_block([[
            if _G.loadModule then
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(":", true, false, true), "mt", false)
                loadModule("lib.event").ProcessEvent({ "paste", "colorscheme\nquit" })
            else
                vim.keymap.set("c", "<F5>", function()
                    vim.api.nvim_paste("colorscheme\nquit", true, -1)
                end)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(":<F5>", true, false, true), "mt", false)
            end
        ]], [[
            return { vim.fn.getcmdtype(), vim.fn.getcmdline() }
        ]])
        ctx.assert.eq("command-line paste error", cmdline_err, nil)
        ctx.assert.deep_eq("command-line paste uses only first line", cmdline, { ":", "colorscheme" })
    end,
}
