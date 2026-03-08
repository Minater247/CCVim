return {
    id = "runtime.normal_bufhidden",
    description = "Ports :normal remap/range/bar semantics and bufhidden delete/hide/unload behavior against Neovim-visible buffer state.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "normal and bufhidden scenarios", [[
            local function fresh(lines)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { 1, 0 })
                return vim.api.nvim_get_current_buf()
            end

            vim.cmd("silent! nunmap x")

            fresh({ "abc" })
            vim.cmd("nnoremap x A-map<Esc>")
            vim.cmd("normal x")
            local remap_line = vim.api.nvim_get_current_line()

            fresh({ "abc" })
            vim.cmd("normal! x")
            local noremap_line = vim.api.nvim_get_current_line()
            vim.cmd("nunmap x")

            fresh({ "aa", "bb", "cc" })
            vim.cmd("2,3normal! x")
            local range_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

            fresh({ "first", "second", "third" })
            vim.cmd("unlet! g:normal_bar_split")
            vim.api.nvim_win_set_cursor(0, { 3, 0 })
            vim.cmd("normal! gg|let g:normal_bar_split = 1")
            local no_bar_cursor = vim.api.nvim_win_get_cursor(0)
            local no_bar_var = vim.g.normal_bar_split

            vim.o.hidden = false
            vim.cmd("enew!")
            vim.cmd("file /tmp/bufhidden_delete.txt")
            local delete_buf = vim.api.nvim_get_current_buf()
            vim.bo.bufhidden = "delete"
            vim.api.nvim_buf_set_lines(delete_buf, 0, -1, false, { "x" })
            vim.bo.modified = false
            local delete_ok, delete_err = pcall(vim.cmd, "enew")
            local delete_exists = vim.fn.bufexists(delete_buf)
            local delete_loaded = vim.fn.bufloaded(delete_buf)
            local delete_valid = vim.api.nvim_buf_is_valid(delete_buf)
            local delete_current_changed = vim.api.nvim_get_current_buf() ~= delete_buf

            vim.o.hidden = false
            vim.cmd("enew!")
            vim.cmd("file /tmp/bufhidden_hide.txt")
            local hide_buf = vim.api.nvim_get_current_buf()
            vim.bo.bufhidden = "hide"
            vim.api.nvim_buf_set_lines(hide_buf, 0, -1, false, { "x" })
            vim.bo.modified = true
            local hide_ok, hide_err = pcall(vim.cmd, "enew")
            local hide_exists = vim.fn.bufexists(hide_buf)
            local hide_valid = vim.api.nvim_buf_is_valid(hide_buf)
            local hide_loaded = vim.fn.bufloaded(hide_buf)
            local hide_modified = vim.fn.getbufvar(hide_buf, "&modified")
            local hide_current_changed = vim.api.nvim_get_current_buf() ~= hide_buf

            vim.o.hidden = false
            vim.cmd("enew!")
            vim.cmd("file /tmp/bufhidden_unload.txt")
            local unload_buf = vim.api.nvim_get_current_buf()
            vim.bo.bufhidden = "unload"
            vim.api.nvim_buf_set_lines(unload_buf, 0, -1, false, { "x" })
            vim.bo.modified = false
            local unload_ok, unload_err = pcall(vim.cmd, "enew")
            local unload_exists = vim.fn.bufexists(unload_buf)
            local unload_valid = vim.api.nvim_buf_is_valid(unload_buf)
            local unload_loaded = vim.fn.bufloaded(unload_buf)
            local unload_lines = vim.fn.getbufline(unload_buf, 1, "$")
            local unload_current_changed = vim.api.nvim_get_current_buf() ~= unload_buf

            return {
                remap_line,
                noremap_line,
                range_lines,
                no_bar_cursor,
                no_bar_var == nil,
                delete_ok,
                tostring(delete_err or ""),
                delete_exists,
                delete_loaded,
                delete_valid,
                delete_current_changed,
                hide_ok,
                tostring(hide_err or ""),
                hide_exists,
                hide_valid,
                hide_loaded,
                hide_modified,
                hide_current_changed,
                unload_ok,
                tostring(unload_err or ""),
                unload_exists,
                unload_valid,
                unload_loaded,
                unload_lines,
                unload_current_changed,
            }
        ]])

        Assert.eq("normal uses remap", result[1], "abc-map")
        Assert.eq("normal! uses noremap", result[2], "bc")
        Assert.table_eq("range normal! visits each line", result[3], { "aa", "b", "c" })
        Assert.table_eq("normal keeps full tail after |", result[4], { 1, 4 })
        Assert.eq("normal does not execute following let", result[5], true)

        Assert.eq("bufhidden=delete leave succeeds", result[6], true)
        Assert.eq("bufhidden=delete leave error", result[7], "")
        Assert.eq("bufhidden=delete keeps buffer entry", result[8], 1)
        Assert.eq("bufhidden=delete unloads buffer", result[9], 0)
        Assert.eq("bufhidden=delete keeps buffer handle valid", result[10], true)
        Assert.eq("bufhidden=delete switches to a new current buffer", result[11], true)

        Assert.eq("bufhidden=hide leave succeeds", result[12], true)
        Assert.eq("bufhidden=hide leave error", result[13], "")
        Assert.eq("bufhidden=hide keeps buffer entry", result[14], 1)
        Assert.eq("bufhidden=hide keeps buffer valid", result[15], true)
        Assert.eq("bufhidden=hide keeps buffer loaded", result[16], 1)
        Assert.eq("bufhidden=hide preserves modified flag", result[17], 1)
        Assert.eq("bufhidden=hide switches to a new current buffer", result[18], true)

        Assert.eq("bufhidden=unload leave succeeds", result[19], true)
        Assert.eq("bufhidden=unload leave error", result[20], "")
        Assert.eq("bufhidden=unload keeps buffer entry", result[21], 1)
        Assert.eq("bufhidden=unload keeps buffer valid", result[22], true)
        Assert.eq("bufhidden=unload marks buffer unloaded", result[23], 0)
        Assert.table_eq("bufhidden=unload clears loaded lines", result[24], {})
        Assert.eq("bufhidden=unload switches to a new current buffer", result[25], true)
    end,
}
