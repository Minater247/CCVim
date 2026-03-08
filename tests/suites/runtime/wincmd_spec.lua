return {
    id = "runtime.wincmd",
    description = "Ports :wincmd count forms through real window selection behavior.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "wincmd count forms", [[
            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one" })

            vim.cmd("split")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "two" })

            vim.cmd("split")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "three" })

            local ids = {
                vim.fn.win_getid(1),
                vim.fn.win_getid(2),
                vim.fn.win_getid(3),
            }

            vim.cmd("1wincmd w")
            local first = vim.fn.win_getid()

            vim.cmd("wincmd w")
            local no_count = vim.fn.win_getid()

            vim.cmd("1wincmd w")
            vim.cmd("3wincmd w")
            local range_three = vim.fn.win_getid()

            vim.cmd("1wincmd w")
            vim.cmd("wincmd 2w")
            local inline_two = vim.fn.win_getid()

            return {
                ids,
                first,
                no_count,
                range_three,
                inline_two,
            }
        ]])

        Assert.eq("window 1 selected by 1wincmd", result[2], result[1][1])
        Assert.eq("wincmd w without count advances to next window", result[3], result[1][2])
        Assert.eq("range count selects numbered window", result[4], result[1][3])
        Assert.eq("inline count selects numbered window", result[5], result[1][2])
    end,
}
