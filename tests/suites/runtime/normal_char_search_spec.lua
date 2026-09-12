return {
    id = "runtime.normal_char_search",
    description = "Checks f, F, t, T, repeats, counts, visual motion, and operator-pending behavior",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "character search motions", [[
            local function feed(keys)
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
            end

            local function reset(line, col)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
                vim.api.nvim_win_set_cursor(0, { 1, col - 1 })
            end

            local positions = {}
            reset("a b a b a b", 1)
            feed("2fb")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)
            feed(";")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)
            feed(",")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)

            reset("012x45x789x", 1)
            feed("2tx")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)
            feed(";")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)
            feed(",")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)

            reset("012x45x789x", 11)
            feed("2Fx")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)
            vim.api.nvim_win_set_cursor(0, { 1, 10 })
            feed("Tx")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)

            reset("axxx", 1)
            feed("tx;")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)
            vim.o.cpoptions = vim.o.cpoptions .. ";"
            reset("axxx", 1)
            feed("tx;")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)

            reset("012x45x789x", 1)
            feed("v2fx")
            positions[#positions + 1] = vim.api.nvim_win_get_cursor(0)
            feed("<C-Tab>")

            local operators = {}
            local function operate(keys, line, col)
                reset(line, col)
                vim.fn.setreg('"', "")
                feed(keys)
                operators[#operators + 1] = {
                    vim.api.nvim_get_current_line(),
                    vim.api.nvim_win_get_cursor(0),
                    vim.fn.getreg('"'),
                    vim.fn.getregtype('"'),
                    vim.api.nvim_get_mode().mode,
                }
            end

            operate("dfx", "012x45x789x", 1)
            operate("d2fx", "012x45x789x", 1)
            operate("dtx", "012x45x789x", 1)
            operate("dFx", "012x45x789x", 11)
            operate("dTx", "012x45x789x", 11)
            operate("cfx<C-Tab>", "012x45x789x", 1)
            operate("ctx<C-Tab>", "012x45x789x", 1)
            operate("yfx", "012x45x789x", 1)
            operate("yFx", "012x45x789x", 11)
            operate("df<C-Tab>", "012x45x789x", 1)

            reset("012x45x789x", 1)
            feed("fx")
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            vim.fn.setreg('"', "")
            feed("d;")
            operators[#operators + 1] = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0),
                vim.fn.getreg('"'),
                vim.fn.getregtype('"'),
                vim.api.nvim_get_mode().mode,
            }

            reset("012x45x789x", 1)
            feed("fx")
            vim.api.nvim_win_set_cursor(0, { 1, 10 })
            vim.fn.setreg('"', "")
            feed("d,")
            operators[#operators + 1] = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0),
                vim.fn.getreg('"'),
                vim.fn.getregtype('"'),
                vim.api.nvim_get_mode().mode,
            }

            return { positions, operators }
        ]])

        ctx.assert.deep_eq("character search positions", result[1], {
            { 1, 6 },
            { 1, 10 },
            { 1, 6 },
            { 1, 5 },
            { 1, 9 },
            { 1, 7 },
            { 1, 3 },
            { 1, 7 },
            { 1, 1 },
            { 1, 0 },
            { 1, 6 },
        })
        ctx.assert.deep_eq("character search operators", result[2], {
            { "45x789x", { 1, 0 }, "012x", "v", "n" },
            { "789x", { 1, 0 }, "012x45x", "v", "n" },
            { "x45x789x", { 1, 0 }, "012", "v", "n" },
            { "012x45x", { 1, 6 }, "x789", "v", "n" },
            { "012x45xx", { 1, 7 }, "789", "v", "n" },
            { "45x789x", { 1, 0 }, "012x", "v", "n" },
            { "x45x789x", { 1, 0 }, "012", "v", "n" },
            { "012x45x789x", { 1, 0 }, "012x", "v", "n" },
            { "012x45x789x", { 1, 6 }, "x789", "v", "n" },
            { "012x45x789x", { 1, 0 }, "", "v", "n" },
            { "45x789x", { 1, 0 }, "012x", "v", "n" },
            { "012x45x", { 1, 6 }, "x789", "v", "n" },
        })
    end,
}
