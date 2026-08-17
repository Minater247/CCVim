return {
    id = "runtime.visual_mode",
    description = "Defines Visual mode behavior against Neovim for selection state, mappings, marks, and operators.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual mode parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset(lines, row, col)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { row or 1, col or 0 })
            end

            reset({ "alpha", "bravo", "charlie" }, 1, 1)
            feed("vll")
            local active_charwise = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }
            feed("<Esc>")
            local exited_charwise = {
                mode = vim.api.nvim_get_mode().mode,
                visualmode = vim.fn.visualmode(),
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset({ "alpha" }, 1, 1)
            feed("vl<C-Tab>")
            local exited_with_ctrl_tab = {
                mode = vim.api.nvim_get_mode().mode,
                visualmode = vim.fn.visualmode(),
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset({ "alpha", "bravo", "charlie" }, 1, 1)
            feed("vlly")
            local charwise_yank = {
                mode = vim.api.nvim_get_mode().mode,
                visualmode = vim.fn.visualmode(),
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
            }

            reset({ "alpha", "bravo", "charlie" }, 1, 2)
            feed("vjld")
            local charwise_multiline_delete = {
                mode = vim.api.nvim_get_mode().mode,
                visualmode = vim.fn.visualmode(),
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            reset({ "alpha" }, 1, 1)
            feed("vllcX<Esc>")
            local charwise_change = {
                mode = vim.api.nvim_get_mode().mode,
                visualmode = vim.fn.visualmode(),
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            reset({ "012345" }, 1, 2)
            feed("vlcX<Esc>")
            local forward_charwise_change = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            reset({ "012345" }, 1, 3)
            feed("vhcX<Esc>")
            local reverse_charwise_change = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            vim.cmd("inoremap <C-Tab> <Esc>")
            reset({ "" }, 1, 0)
            feed("itype<Space>this<C-Tab>v<Left><Left><Left>cX<Esc>")
            local insert_to_reverse_visual_change = {
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                register = vim.fn.getreg('"'),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset({ "alpha", "bravo", "charlie" }, 1, 2)
            feed("VjcX<Esc>")
            local linewise_change = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            reset({ "alpha", "bravo", "charlie" }, 1, 2)
            feed("<C-v>jlcX<Esc>")
            local blockwise_change = {
                mode = vim.api.nvim_get_mode().mode,
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            reset({ "alpha", "bravo", "charlie" }, 1, 1)
            feed("Vjy")
            local linewise_yank = {
                mode = vim.api.nvim_get_mode().mode,
                visualmode = vim.fn.visualmode(),
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
            }

            reset({ "alpha", "bravo", "charlie" }, 1, 2)
            feed("<C-v>jld")
            local blockwise_delete = {
                mode = vim.api.nvim_get_mode().mode,
                visualmode = vim.fn.visualmode(),
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            reset({ "abcdef", "x", "uvwxyz" }, 1, 2)
            feed("<C-v>jlly")
            local short_line_blockwise_yank = {
                visualmode = vim.fn.visualmode(),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_list = vim.fn.getreg('"', 1, 1),
                register_type = vim.fn.getregtype('"'),
            }

            vim.cmd("xnoremap q y")
            reset({ "alpha" }, 1, 1)
            feed("vlq")
            local visual_mapping = {
                mode = vim.api.nvim_get_mode().mode,
                visualmode = vim.fn.visualmode(),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
            }
            local maxcol = {
                vim.v.maxcol,
                vim.api.nvim_eval("v:maxcol"),
            }

            return {
                active_charwise,
                exited_charwise,
                exited_with_ctrl_tab,
                charwise_yank,
                charwise_multiline_delete,
                charwise_change,
                forward_charwise_change,
                reverse_charwise_change,
                insert_to_reverse_visual_change,
                linewise_change,
                blockwise_change,
                linewise_yank,
                blockwise_delete,
                short_line_blockwise_yank,
                visual_mapping,
                maxcol,
            }
        ]])

        Assert.table_eq("active characterwise mode and cursor", result[1], {
            mode = "v",
            cursor = { 1, 3 },
            start = { 0, 0, 0, 0 },
            finish = { 0, 0, 0, 0 },
        })
        Assert.table_eq("exiting characterwise mode persists marks", result[2], {
            mode = "n",
            visualmode = "v",
            cursor = { 1, 3 },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 4, 0 },
        })
        Assert.table_eq("Ctrl-Tab exits characterwise mode", result[3], {
            mode = "n",
            visualmode = "v",
            cursor = { 1, 2 },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 3, 0 },
        })
        Assert.table_eq("characterwise yank is inclusive", result[4], {
            mode = "n",
            visualmode = "v",
            cursor = { 1, 1 },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 4, 0 },
            register = "lph",
            register_type = "v",
        })
        Assert.table_eq("multiline characterwise delete", result[5], {
            mode = "n",
            visualmode = "v",
            cursor = { 1, 2 },
            start = { 0, 1, 3, 0 },
            finish = { 0, 2, 4, 0 },
            register = "pha\nbrav",
            register_type = "v",
            lines = { "alo", "charlie" },
        })
        Assert.table_eq("characterwise change", result[6], {
            mode = "n",
            visualmode = "v",
            cursor = { 1, 1 },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 4, 0 },
            register = "lph",
            register_type = "v",
            lines = { "aXa" },
        })
        Assert.table_eq("forward characterwise change preserves prefix", result[7], { "01X45" })
        Assert.table_eq("reverse characterwise change preserves prefix", result[8], { "01X45" })
        Assert.table_eq("Insert-to-reverse-Visual change", result[9], {
            lines = { "type X" },
            register = "this",
            start = { 0, 1, 6, 0 },
            finish = { 0, 1, 9, 0 },
        })
        Assert.table_eq("linewise change", result[10], {
            mode = "n",
            cursor = { 1, 0 },
            start = { 0, 1, 1, 0 },
            finish = { 0, 2, 2147483647, 0 },
            register = "alpha\nbravo\n",
            register_type = "V",
            lines = { "X", "charlie" },
        })
        Assert.table_eq("blockwise change", result[11], {
            mode = "n",
            cursor = { 1, 2 },
            start = { 0, 1, 3, 0 },
            finish = { 0, 2, 4, 0 },
            register = "ph\nav",
            register_type = string.char(22) .. "2",
            lines = { "alXa", "brXo", "charlie" },
        })
        Assert.table_eq("linewise yank shape", result[12], {
            mode = "n",
            visualmode = "V",
            cursor = { 1, 0 },
            start = { 0, 1, 1, 0 },
            finish = { 0, 2, 2147483647, 0 },
            register = "alpha\nbravo\n",
            register_type = "V",
        })
        Assert.table_eq("blockwise delete shape", result[13], {
            mode = "n",
            visualmode = string.char(22),
            cursor = { 1, 2 },
            start = { 0, 1, 3, 0 },
            finish = { 0, 2, 4, 0 },
            register = "ph\nav",
            register_type = string.char(22) .. "2",
            lines = { "ala", "bro", "charlie" },
        })
        Assert.table_eq("short block line preserves width", result[14], {
            visualmode = string.char(22),
            start = { 0, 1, 3, 0 },
            finish = { 0, 2, 2, 0 },
            register = "bc\n",
            register_list = { "bc", "" },
            register_type = string.char(22) .. "2",
        })
        Assert.table_eq("visual mapping dispatch", result[15], {
            mode = "n",
            visualmode = "v",
            register = "lp",
            register_type = "v",
        })
        Assert.table_eq("v:maxcol", result[16], { 2147483647, 2147483647 })
    end,
}
