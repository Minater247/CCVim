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

        local square_brackets = Assert.eval_block(backend, "matchit handles Lua indexing brackets", [[
            vim.cmd("packadd matchit")
            vim.b.match_words = "\\<\\%(do\\|function\\|if\\)\\>:"
                .. "\\<\\%(return\\|else\\|elseif\\)\\>:\\<end\\>,"
                .. "\\<repeat\\>:\\<until\\>,\\%(--\\)\\=\\[\\(=*\\)\\[:]\\1]"
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "col, lnum = find_match_forward(",
                "    y, candidate_col, candidate_char, start2stop[candidate_char], candidate_parity",
                ")",
            })
            vim.api.nvim_win_set_cursor(0, { 2, 4 })
            vim.cmd("call matchit#Match_wrapper('',1,'n')")
            local forward = vim.api.nvim_win_get_cursor(0)
            vim.cmd("call matchit#Match_wrapper('',1,'n')")
            return {
                forward,
                vim.api.nvim_win_get_cursor(0),
                vim.fn.escape("(:),{:},[:]", "[$^.*~\\\\/?]"),
            }
        ]])

        Assert.table_eq(
            "matchit wrapper matches Lua indexing brackets",
            square_brackets[1],
            { 2, 63 }
        )
        Assert.table_eq(
            "matchit wrapper returns to Lua indexing opening bracket",
            square_brackets[2],
            { 2, 48 }
        )
        Assert.eq("escape handles matchpairs characters", square_brackets[3], "(:),{:},\\[:\\]")

        local physical_percent = Assert.eval_block(backend, "matchit physical percent key", [[
            vim.cmd("packadd matchit")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "prefix ( outer", "suffix )" })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            local Event = loadModule("lib.event")
            local function press_physical_percent()
                Event.ProcessEvent({ "key", keys.leftShift, false })
                Event.ProcessEvent({ "key", keys.five, false })
                Event.ProcessEvent({ "char", "%" })
                Event.ProcessEvent({ "key_up", keys.leftShift })
                Event.ProcessEvent({ "key_up", keys.five })
            end
            press_physical_percent()
            local forward = vim.api.nvim_win_get_cursor(0)
            press_physical_percent()
            return { forward, vim.api.nvim_win_get_cursor(0) }
        ]])

        Assert.deep_eq("matchit mapping handles physical percent key", physical_percent, {
            { 2, 7 },
            { 1, 7 },
        })
    end,
}
