return {
    id = "api.vim_keymap_callback_count",
    description = "Ports Neovim keymap callback count semantics: user callbacks read vim.v.count and vim.v.count1 instead of receiving count positionally.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.keymap callback count semantics", [[
            local function press(keys)
                vim.api.nvim_feedkeys(keys, "mx", true)
                pcall(vim.cmd, "redraw")
            end

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four", "five" })
            vim.cmd("normal! gg0")

            local callback_seen = {}
            vim.keymap.set("n", "Q", function(...)
                callback_seen = {
                    nargs = select("#", ...),
                    first = select(1, ...),
                    count = vim.v.count,
                    count1 = vim.v.count1,
                }
            end, { buffer = true })

            press("8Q")
            local with_count = {
                callback_seen.nargs,
                callback_seen.first == nil,
                callback_seen.count,
                callback_seen.count1,
            }

            callback_seen = {}
            press("Q")
            local without_count = {
                callback_seen.nargs,
                callback_seen.first == nil,
                callback_seen.count,
                callback_seen.count1,
            }

            vim.g.rhs_count = nil
            vim.g.rhs_count1 = nil
            vim.cmd("nnoremap <buffer> W <Cmd>let g:rhs_count = v:count <Bar> let g:rhs_count1 = v:count1<CR>")
            press("6W")
            local rhs_mapping = { vim.g.rhs_count, vim.g.rhs_count1 }

            vim.cmd("normal! gg0")
            press("3j")
            local builtin_motion_line = vim.fn.line(".")

            return {
                with_count,
                without_count,
                rhs_mapping,
                builtin_motion_line,
            }
        ]])

        Assert.table_eq("user callback with count reads vim.v", result[1], { 0, true, 8, 8 })
        Assert.table_eq("user callback without count gets vim.v.count1 default", result[2], { 0, true, 0, 1 })
        Assert.table_eq("rhs mapping sees vim v count variables", result[3], { 6, 6 })
        Assert.eq("builtin motion still uses count", result[4], 4)
    end,
}
