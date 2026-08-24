return {
    id = "runtime.select_mode",
    description = "Defines documented Select-mode entry, editing, movement, register, and mapping behavior against Neovim.", -- luacheck: ignore 631

    run = function(ctx)
        local Assert = ctx.assert
        local result = Assert.eval_block(ctx.backend, "Select mode parity", [[
            local function feed(text)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(text, true, false, true), "xt", false)
            end

            local function reset(lines, col)
                feed("<Esc>")
                vim.cmd("enew!")
                vim.o.selectmode = ""
                vim.o.keymodel = ""
                vim.api.nvim_buf_set_lines(0, 0, -1, false,
                    type(lines) == "table" and lines or { lines })
                vim.api.nvim_win_set_cursor(0, { 1, col or 0 })
            end

            reset("alpha", 1)
            feed("gh<Right><Right>")
            local entry_char = { vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }
            feed("<C-G>")
            local ctrl_g_visual = vim.fn.mode()
            feed("<C-G>")
            local ctrl_g_select = vim.fn.mode()
            feed("<Esc>")
            local escape = vim.fn.mode()

            reset({ "alpha", "bravo" }, 0)
            feed("gH")
            local entry_line = vim.fn.mode()
            feed("<Esc>g<C-H>")
            local entry_block = vim.fn.mode()

            reset("alpha", 1)
            vim.o.selectmode = "cmd"
            feed("v<Right><Right>")
            local selectmode_cmd = vim.fn.mode()

            reset("alpha", 1)
            vim.o.keymodel = "startsel,stopsel"
            vim.o.selectmode = "key"
            feed("<S-Right>")
            local shift_start = { vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }
            feed("<S-Right>")
            local shift_extend = { vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }
            feed("<Left>")
            local unshift_stop = { vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }

            reset("alpha", 1)
            feed("gh<Right><Right>X<Esc>")
            local replace_char = {
                vim.fn.mode(), vim.api.nvim_get_current_line(),
                vim.fn.getreg('"'), vim.fn.getregtype('"'),
            }

            reset({ "alpha", "bravo", "charlie" }, 0)
            feed("gH<Down>X<Esc>")
            local replace_line = {
                vim.fn.mode(), vim.api.nvim_buf_get_lines(0, 0, -1, false),
                vim.fn.getregtype('"'),
            }

            reset("alpha", 1)
            feed("gh<Right><Right><CR><Esc>")
            local replace_cr = {
                vim.fn.mode(), vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            reset("alpha", 1)
            feed("gh<Right><Right><BS>")
            local backspace = {
                vim.fn.mode(), vim.api.nvim_get_current_line(),
                vim.fn.getreg('"'), vim.fn.getregtype('"'),
            }

            reset("alpha", 1)
            feed("gh<Right><Right><Del>")
            local delete = {
                vim.fn.mode(), vim.api.nvim_get_current_line(),
                vim.fn.getreg('"'), vim.fn.getregtype('"'),
            }

            reset("alpha", 1)
            vim.fn.setreg('"', "keep", "v")
            feed("gh<Right><Right><C-R>_X<Esc>")
            local blackhole = { vim.fn.mode(), vim.api.nvim_get_current_line(), vim.fn.getreg('"') }

            reset("alpha", 1)
            vim.fn.setreg('"', "keep", "v")
            vim.fn.setreg("a", "old", "v")
            feed("gh<Right><Right><C-R>aX<Esc>")
            local named_register = {
                vim.api.nvim_get_current_line(), vim.fn.getreg("a"),
                vim.fn.getreg('"'), vim.fn.getregtype("a"),
            }

            reset("alpha", 1)
            feed("gh<Right><Right><C-O>o")
            local ctrl_o = { vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }

            reset("alpha", 1)
            vim.g.select_seen_v = nil
            vim.g.select_seen_s = nil
            vim.keymap.set("v", "<F2>", function() vim.g.select_seen_v = vim.fn.mode() end)
            vim.keymap.set("s", "<F3>", function() vim.g.select_seen_s = vim.fn.mode() end)
            feed("gh<Right><Right><F2>")
            local vmap = { vim.g.select_seen_v, vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }
            feed("<F3>")
            local smap = { vim.g.select_seen_s, vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }
            vim.keymap.del("v", "<F2>")
            vim.keymap.del("s", "<F3>")

            reset("alpha", 1)
            vim.keymap.set("v", "<F4>", "<Esc>")
            feed("gh<Right><Right><F4>")
            local vmap_escape = { vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }
            vim.keymap.del("v", "<F4>")

            reset("alpha", 1)
            vim.keymap.set("s", "<F5>", "<Esc>")
            feed("gh<Right><Right><F5>")
            local smap_escape = { vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }
            vim.keymap.del("s", "<F5>")

            reset("alpha", 1)
            vim.keymap.set("v", "<F6>", "gV<Esc>")
            feed("gh<Right><Right><F6>")
            local vmap_gv = { vim.fn.mode(), vim.api.nvim_win_get_cursor(0) }
            vim.keymap.del("v", "<F6>")

            reset("alpha", 1)
            vim.o.selection = "exclusive"
            feed("gh<Right><Right>X<Esc>")
            local exclusive_forward = { vim.api.nvim_get_current_line(), vim.fn.getreg('"') }
            vim.o.selection = "inclusive"

            reset("alpha", 3)
            vim.o.selection = "exclusive"
            feed("gh<Left><Left>X<Esc>")
            local exclusive_backward = { vim.api.nvim_get_current_line(), vim.fn.getreg('"') }
            vim.o.selection = "inclusive"

            return {
                entry_char, ctrl_g_visual, ctrl_g_select, escape, entry_line, entry_block,
                selectmode_cmd, shift_start, shift_extend, unshift_stop, replace_char,
                replace_line, replace_cr, backspace, delete, blackhole, named_register,
                ctrl_o, vmap, smap, vmap_escape, smap_escape, vmap_gv,
                exclusive_forward, exclusive_backward,
            }
        ]])

        Assert.deep_eq("Select mode parity", result, {
            { "s", { 1, 3 } },
            "v",
            "s",
            "n",
            "S",
            string.char(19),
            "s",
            { "s", { 1, 2 } },
            { "s", { 1, 3 } },
            { "n", { 1, 2 } },
            { "n", "aXa", "lph", "v" },
            { "n", { "Xcharlie" }, "v" },
            { "n", { "a", "a" } },
            { "n", "aa", "lph", "v" },
            { "n", "aa", "lph", "v" },
            { "n", "aXa", "keep" },
            { "aXa", "lph", "lph", "v" },
            { "s", { 1, 1 } },
            { "v", "s", { 1, 3 } },
            { "s", "s", { 1, 3 } },
            { "s", { 1, 3 } },
            { "n", { 1, 3 } },
            { "n", { 1, 3 } },
            { "aXha", "lp" },
            { "aXha", "lp" },
        })
    end,
}
