return {
    id = "api.vim_setline",
    description = "Ports setline() builtin coverage from old tests without module stubs.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "setline scenarios", [[
            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })

            local r_numeric = vim.fn.setline(2, "TWO")
            local r_dollar = vim.fn.setline("$", "THREE")
            local r_append = vim.fn.setline(4, "FOUR")
            local r_dot = vim.fn.setline(".", "CUR")
            local r_list = vim.fn.setline(1, { 10, true })
            local r_extend = vim.fn.setline(4, { "x", "y", "z" })

            local before_empty = vim.fn.join(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
            local r_empty = vim.fn.setline(3, {})
            local after_empty = vim.fn.join(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            local before_invalid = vim.fn.join(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
            local r_low = vim.fn.setline(0, "bad")
            local after_low = vim.fn.join(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            local r_high = vim.fn.setline(vim.api.nvim_buf_line_count(0) + 2, "bad")
            local after_high = vim.fn.join(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            local final_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            return {
                r_numeric,
                r_dollar,
                r_append,
                r_dot,
                r_list,
                r_extend,
                r_empty,
                r_low,
                r_high,
                final_lines,
                before_empty,
                after_empty,
                before_invalid,
                after_low,
                after_high,
            }
        ]])

        for i = 1, 7 do
            Assert.eq("setline success return[" .. tostring(i) .. "]", result[i], 0)
        end
        Assert.eq("setline invalid low lnum", result[8], 1)
        Assert.eq("setline invalid high lnum", result[9], 1)
        Assert.table_eq("setline final lines", result[10], { "10", "v:true", "THREE", "x", "y", "z" })
        Assert.eq("setline empty list no-op", result[11], result[12])
        Assert.eq("setline invalid low no-op", result[13], result[14])
        Assert.eq("setline invalid high no-op", result[13], result[15])

        Assert.expect_error(backend, "setline too many args emits E118", 'vim.fn.setline(1, "x", "extra")', "E118")
    end,
}
