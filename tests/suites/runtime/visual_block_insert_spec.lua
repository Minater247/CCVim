return {
    id = "runtime.visual_block_insert",
    description = "Checks simple documented Visual-block insert, append, and change behavior against Neovim.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Visual-block insertion parity", [[
            local function feed(text)
                local keys = vim.api.nvim_replace_termcodes(text, true, false, true)
                vim.api.nvim_feedkeys(keys, "xt", false)
            end

            local function reset()
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "bravo", "charlie" })
                vim.api.nvim_win_set_cursor(0, { 1, 2 })
            end

            reset()
            feed("<C-v>jIX<Esc>")
            local block_insert = {
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                visualmode = vim.fn.visualmode(),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            reset()
            feed("<C-v>jlAX<Esc>")
            local block_append = {
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                visualmode = vim.fn.visualmode(),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            reset()
            feed("<C-v>jCX<Esc>")
            local block_change_to_eol = {
                cursor = vim.api.nvim_win_get_cursor(0),
                start = vim.fn.getpos("'<"),
                finish = vim.fn.getpos("'>"),
                register = vim.fn.getreg('"'),
                register_type = vim.fn.getregtype('"'),
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }

            return { block_insert, block_append, block_change_to_eol }
        ]])

        Assert.deep_eq("block I inserts on every selected row", result[1], {
            cursor = { 1, 2 },
            start = { 0, 1, 3, 0 },
            finish = { 0, 2, 3, 0 },
            visualmode = string.char(22),
            lines = { "alXpha", "brXavo", "charlie" },
        })
        Assert.deep_eq("block A appends after the rectangle", result[2], {
            cursor = { 1, 2 },
            start = { 0, 1, 3, 0 },
            finish = { 0, 2, 4, 0 },
            visualmode = string.char(22),
            lines = { "alphXa", "bravXo", "charlie" },
        })
        Assert.deep_eq("block C changes through end of line", result[3], {
            cursor = { 1, 2 },
            start = { 0, 1, 3, 0 },
            finish = { 0, 2, 3, 0 },
            register = "pha\navo",
            register_type = string.char(22) .. "3",
            lines = { "alX", "brX", "charlie" },
        })
    end,
}
