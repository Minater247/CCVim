return {
    id = "runtime.matchit_autoload",
    description = "Loads matchit and resolves its autoloaded Match_wrapper function.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "matchit Match_wrapper autoloads", [[
            vim.cmd("packadd matchit")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(x)" })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            vim.cmd("call matchit#Match_wrapper('',1,'n')")
            return {
                vim.fn.exists("*matchit#Match_wrapper"),
                vim.api.nvim_win_get_cursor(0),
            }
        ]])

        Assert.eq("matchit autoload function exists after call", result[1], 1)
        Assert.table_eq("matchit wrapper moves to matching paren", result[2], { 1, 2 })

        local c_braces = Assert.eval_block(backend, "matchit moves backward from C closing brace", [[
            vim.cmd("packadd matchit")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "int main(int argc, char **argv) {",
                "",
                "}",
            })
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            vim.cmd("call matchit#Match_wrapper('',1,'n')")
            return vim.api.nvim_win_get_cursor(0)
        ]])

        Assert.table_eq("matchit wrapper moves backward to opening brace", c_braces, { 1, 32 })
    end,
}
