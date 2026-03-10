return {
    id = "api.vim_mapping_precedence",
    description = "Ports builtin mapping precedence through real mappings, unmap, mapclear, and operator behavior.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "mapping precedence scenarios", [=[
            local function press(keys)
                vim.api.nvim_feedkeys(keys, "mx", true)
                pcall(vim.cmd, "redraw")
            end

            local function reset_buffer(lines)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.cmd("normal! gg0")
                pcall(vim.cmd, "nmapclear")
                pcall(vim.cmd, "nmapclear <buffer>")
            end

            reset_buffer({ "abc" })
            vim.g.map_last = nil
            vim.cmd([[nnoremap x <Cmd>let g:map_last = 'user-x'<CR>]])
            press("x")
            local user_shadow = { vim.g.map_last, vim.api.nvim_get_current_line() }

            vim.cmd("nunmap x")
            vim.g.map_last = nil
            vim.cmd("normal! gg0")
            press("x")
            local unmap_restore = { vim.g.map_last == nil, vim.api.nvim_get_current_line() }

            reset_buffer({ "abc" })
            vim.g.map_last = nil
            vim.cmd([[nnoremap x <Cmd>let g:map_last = 'user-x'<CR>]])
            vim.cmd("nmapclear")
            press("x")
            local mapclear_restore = { vim.g.map_last == nil, vim.api.nvim_get_current_line() }

            reset_buffer({ "abc" })
            vim.g.map_last = nil
            vim.cmd([[nnoremap x <Cmd>let g:map_last = 'global-x'<CR>]])
            vim.cmd([[nnoremap <buffer> x <Cmd>let g:map_last = 'local-x'<CR>]])
            press("x")
            local local_shadow = { vim.g.map_last, vim.api.nvim_get_current_line() }

            vim.cmd("nmapclear <buffer>")
            vim.g.map_last = nil
            vim.cmd("normal! gg0")
            press("x")
            local local_clear_restore = { vim.g.map_last, vim.api.nvim_get_current_line() }

            vim.cmd("nunmap x")
            vim.g.map_last = nil
            vim.cmd("normal! gg0")
            press("x")
            local global_unmap_restore = { vim.g.map_last == nil, vim.api.nvim_get_current_line() }

            reset_buffer({ "abc def" })
            vim.cmd([[nnoremap q <Cmd>let g:unused = 1<CR>]])
            vim.cmd("nunmap q")
            press("dw")
            local operator_after_unmap = vim.api.nvim_get_current_line()

            reset_buffer({ "abc def" })
            vim.cmd([[nnoremap r <Cmd>let g:unused = 1<CR>]])
            vim.cmd("nmapclear")
            press("dw")
            local operator_after_mapclear = vim.api.nvim_get_current_line()

            return {
                user_shadow,
                unmap_restore,
                mapclear_restore,
                local_shadow,
                local_clear_restore,
                global_unmap_restore,
                operator_after_unmap,
                operator_after_mapclear,
            }
        ]=])

        Assert.table_eq("user mapping shadows builtin", result[1], { "user-x", "abc" })
        Assert.table_eq("unmap restores builtin", result[2], { true, "bc" })
        Assert.table_eq("mapclear preserves builtin and removes user map", result[3], { true, "bc" })
        Assert.table_eq("buffer-local user shadows global user", result[4], { "local-x", "abc" })
        Assert.table_eq("clearing local user restores global user", result[5], { "global-x", "abc" })
        Assert.table_eq("clearing global user restores builtin", result[6], { true, "bc" })
        Assert.eq("builtin operator survives unrelated unmap", result[7], "def")
        Assert.eq("builtin operator survives mapclear", result[8], "def")
    end,
}
