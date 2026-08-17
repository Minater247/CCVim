return {
    id = "runtime.visual_join",
    description = "Checks Visual J and gJ against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual join parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset()
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one  ", "   two", "three" })
                vim.api.nvim_win_set_cursor(0, { 1, 1 })
            end

            reset()
            feed("vjJ")
            local join = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            reset()
            feed("vjgJ")
            local raw_join = {
                cursor = vim.api.nvim_win_get_cursor(0),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
            }

            return { join, raw_join }
        ]])

        Assert.deep_eq("Visual J joins with whitespace normalization", result[1], {
            cursor = { 1, 5 },
            lines = { "one  two", "three" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 6, 0 },
        })
        Assert.deep_eq("Visual gJ joins without whitespace normalization", result[2], {
            cursor = { 1, 5 },
            lines = { "one     two", "three" },
            start = { 0, 1, 2, 0 },
            finish = { 0, 1, 7, 0 },
        })
    end,
}
