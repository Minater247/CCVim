return {
    id = "runtime.undo_parity",
    description = "Ports editor-visible undo/redo command behavior against Neovim reference semantics.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local undo_path = Assert.temp_path(backend, "undo-parity-undo", ".txt")
        local ctrlr_path = Assert.temp_path(backend, "undo-parity-ctrlr", ".txt")
        local u_path = Assert.temp_path(backend, "undo-parity-u", ".txt")

        Assert.write_file(backend, undo_path, "one\n")
        Assert.write_file(backend, ctrlr_path, "abc\n")
        Assert.write_file(backend, u_path, "abc\ndef\n")

        local result = Assert.eval_block(backend, "undo parity scenarios", string.format([[
            local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
            local ctrl_r = vim.api.nvim_replace_termcodes("<C-r>", true, false, true)

            local function open_file(path)
                vim.cmd("edit " .. vim.fn.fnameescape(path))
                vim.api.nvim_win_set_cursor(0, { 1, 0 })
            end

            open_file(%q)
            vim.cmd("normal! x")
            vim.cmd("undo")
            local undo_line = vim.api.nvim_get_current_line()
            vim.cmd("redo")
            local redo_line = vim.api.nvim_get_current_line()

            vim.cmd("enew!")
            local invalid_ok, invalid_err = pcall(vim.cmd, "undo nope")

            open_file(%q)
            vim.cmd("normal! x")
            vim.cmd("normal! u")
            vim.api.nvim_feedkeys(ctrl_r, "xt", false)
            vim.cmd("redraw")
            local raw_ctrl_r_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            local raw_ctrl_r_modified = vim.bo.modified

            open_file(%q)
            vim.cmd("normal! x")
            vim.cmd("normal! jx")
            vim.cmd("normal! kx")
            vim.cmd("normal! U")
            local noncontiguous_u_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            local noncontiguous_u_modified = vim.bo.modified

            return {
                undo_line,
                redo_line,
                invalid_ok,
                tostring(invalid_err or ""),
                raw_ctrl_r_lines,
                raw_ctrl_r_modified,
                noncontiguous_u_lines,
                noncontiguous_u_modified,
            }
        ]], undo_path, ctrlr_path, u_path))

        Assert.eq("ex undo restores line", result[1], "one")
        Assert.eq("ex redo reapplies line", result[2], "ne")
        Assert.eq("ex undo invalid arg fails", result[3], false)
        Assert.top_error_code("ex undo invalid arg uses E488", result[4], "E488")
        Assert.table_eq("normal raw ctrl-r redoes", result[5], { "bc" })
        Assert.eq("normal raw ctrl-r marks modified", result[6], true)
        Assert.table_eq("normal U noncontiguous parity", result[7], { "bc", "ef" })
        Assert.eq("normal U noncontiguous modified parity", result[8], true)
    end,
}
