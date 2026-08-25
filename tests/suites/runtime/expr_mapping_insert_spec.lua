return {
    id = "runtime.expr_mapping_insert",
    description = "Keeps insert-mode expr mappings feeding their returned keys back into editing, including the default <Tab> fallback path.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "insert expr mapping behavior", [[
            local function press(keys)
                local termcoded = vim.api.nvim_replace_termcodes(keys, true, false, true)
                vim.api.nvim_feedkeys(termcoded, "xt", false)
            end

            vim.cmd("enew!")
            vim.bo.expandtab = true
            vim.bo.shiftwidth = 4
            vim.bo.tabstop = 4
            press("i<Tab><Esc>")
            local default_tab = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0)[2],
            }

            vim.cmd("enew!")
            vim.keymap.set("i", "<C-l>", "'xy'", { buffer = true, expr = true })
            press("i<C-l><Esc>")
            local string_expr = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0)[2],
            }

            vim.cmd("enew!")
            vim.cmd("inoremap <expr> <F2> 'xy'")
            press("i<F2><Esc>")
            local ex_expr = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0)[2],
            }

            vim.cmd("enew!")
            vim.keymap.set("i", "<F3>", function()
                return true
            end, { buffer = true, expr = true })
            press("i<F3><Esc>")
            local callback_bool_expr = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0)[2],
            }

            vim.cmd("enew!")
            vim.cmd("inoremap <expr> <F4> v:true")
            press("i<F4><Esc>")
            local ex_true_bool_expr = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0)[2],
            }

            vim.cmd("enew!")
            vim.cmd("inoremap <expr> <F5> v:false")
            press("i<F5><Esc>")
            local ex_false_bool_expr = {
                vim.api.nvim_get_current_line(),
                vim.api.nvim_win_get_cursor(0)[2],
            }

            vim.cmd("enew!")
            vim.g.insert_expr_cmd_mode = nil
            vim.keymap.set("i", "<F6>", function()
                return "<Cmd>let g:insert_expr_cmd_mode = mode()<CR>"
            end, { buffer = true, expr = true })
            press("i<F6>Z<Esc>")
            local insert_cmd_expr = {
                vim.api.nvim_get_current_line(),
                vim.g.insert_expr_cmd_mode,
            }

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha" })
            vim.api.nvim_win_set_cursor(0, { 1, 1 })
            vim.g.select_expr_cmd_mode = nil
            vim.keymap.set("s", "<F7>", function()
                return "<Cmd>let g:select_expr_cmd_mode = mode()<CR>"
            end, { buffer = true, expr = true })
            press("gh<Right><F7>X<Esc>")
            local select_cmd_expr = {
                vim.api.nvim_get_current_line(),
                vim.g.select_expr_cmd_mode,
            }

            return {
                default_tab,
                string_expr,
                ex_expr,
                callback_bool_expr,
                ex_true_bool_expr,
                ex_false_bool_expr,
                insert_cmd_expr,
                select_cmd_expr,
            }
        ]])

        Assert.table_eq("default insert tab expr inserts indentation", result[1], { "    ", 3 })
        Assert.table_eq("string expr mapping inserts returned text", result[2], { "xy", 1 })
        Assert.table_eq("Ex expr mapping inserts evaluated text", result[3], { "xy", 1 })
        Assert.table_eq("callback expr boolean stays empty", result[4], { "", 0 })
        Assert.table_eq("Ex expr v:true stringifies like Vim", result[5], { "v:true", 5 })
        Assert.table_eq("Ex expr v:false stringifies like Vim", result[6], { "v:false", 6 })
        Assert.table_eq("insert expr <Cmd> executes without inserting its command", result[7], { "Z", "i" })
        Assert.table_eq("Select expr <Cmd> preserves selection", result[8], { "aXha", "s" })
    end,
}
