return {
    id = "runtime.write_quit_parity",
    description = "Ports fileformat-aware writes and last-window quit refusal when another hidden buffer is still modified.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local unix_path = Assert.temp_path(backend, "write-unix", ".txt")
        local dos_path = Assert.temp_path(backend, "write-dos", ".txt")
        local mac_path = Assert.temp_path(backend, "write-mac", ".txt")
        local quit_current = Assert.temp_path(backend, "quit-current", ".txt")
        local quit_hidden = Assert.temp_path(backend, "quit-hidden", ".txt")
        local wq_current = Assert.temp_path(backend, "wq-current", ".txt")
        local wq_hidden = Assert.temp_path(backend, "wq-hidden", ".txt")

        local result = Assert.eval_block(backend, "write and quit parity", string.format([[
            local function write_with_ff(path, ff, lines)
                vim.cmd("enew!")
                vim.cmd("file " .. vim.fn.fnameescape(path))
                vim.bo.fileformat = ff
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.cmd("write!")
                return vim.fn.readfile(path, "b")
            end

            local unix_lines = write_with_ff(%q, "unix", { "unix-a", "unix-b" })
            local dos_lines = write_with_ff(%q, "dos", { "dos-a", "dos-b" })
            local mac_lines = write_with_ff(%q, "mac", { "mac-a", "mac-b" })

            vim.o.hidden = true
            vim.o.autowriteall = false

            vim.cmd("enew!")
            vim.cmd("file " .. vim.fn.fnameescape(%q))
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "current" })
            vim.bo.modified = false
            local quit_current_buf = vim.api.nvim_get_current_buf()

            vim.cmd("enew!")
            vim.cmd("file " .. vim.fn.fnameescape(%q))
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hidden" })
            local quit_hidden_buf = vim.api.nvim_get_current_buf()

            vim.cmd("buffer " .. quit_current_buf)
            local quit_ok, quit_err = pcall(vim.cmd, "quit")
            local quit_surfaced_hidden = vim.api.nvim_get_current_buf() == quit_hidden_buf
            local quit_hidden_modified = vim.fn.getbufvar(quit_hidden_buf, "&modified")

            vim.bo.modified = false

            vim.cmd("enew!")
            vim.cmd("file " .. vim.fn.fnameescape(%q))
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "wq-current" })
            local wq_current_buf = vim.api.nvim_get_current_buf()

            vim.cmd("enew!")
            vim.cmd("file " .. vim.fn.fnameescape(%q))
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "wq-hidden" })
            local wq_hidden_buf = vim.api.nvim_get_current_buf()

            vim.cmd("buffer " .. wq_current_buf)
            local wq_ok, wq_err = pcall(vim.cmd, "wq")

            return {
                unix_lines,
                dos_lines,
                mac_lines,
                quit_ok,
                tostring(quit_err or ""),
                quit_surfaced_hidden,
                quit_hidden_modified,
                wq_ok,
                tostring(wq_err or ""),
                vim.fn.readfile(%q, "b"),
                vim.api.nvim_get_current_buf() == wq_hidden_buf,
                vim.bo.modified,
                vim.fn.getbufvar(wq_hidden_buf, "&modified"),
            }
        ]], unix_path, dos_path, mac_path, quit_current, quit_hidden, wq_current, wq_hidden, wq_current))

        Assert.table_eq("unix write uses LF with terminal EOL", result[1], { "unix-a", "unix-b", "" })
        Assert.table_eq("dos write uses CRLF with terminal EOL", result[2], { "dos-a\r", "dos-b\r", "" })
        Assert.table_eq("mac write uses CR with terminal EOL", result[3], { "mac-a\rmac-b\r" })
        Assert.eq("quit on last window with hidden modified buffer fails", result[4], false)
        Assert.top_error_code("quit on last window with hidden modified buffer uses E37", result[5], "E37")
        Assert.eq("quit refusal surfaces the hidden modified buffer", result[6], true)
        Assert.eq("quit refusal preserves hidden modified buffer", result[7], 1)
        Assert.eq("wq on last window with hidden modified buffer fails", result[8], false)
        Assert.top_error_code("wq on last window with hidden modified buffer uses E37", result[9], "E37")
        Assert.table_eq("wq still writes the current buffer before refusal", result[10], { "wq-current", "" })
        Assert.eq("wq refusal surfaces the hidden modified buffer", result[11], true)
        Assert.eq("wq refusal leaves the surfaced hidden buffer modified", result[12], true)
        Assert.eq("wq refusal preserves hidden modified buffer", result[13], 1)
    end,
}
