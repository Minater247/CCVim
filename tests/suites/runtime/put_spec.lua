return {
    id = "runtime.put",
    description = "Ports put command behavior for registers, expressions, addresses, and errors.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local named_path = Assert.temp_path(backend, "put-current-name", ".txt")
        local result = Assert.eval_block(backend, "put scenarios", string.format([[
            local function set_lines(lines, name, cursor_line)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { cursor_line or 1, 0 })
                if name ~= nil and name ~= "" then
                    vim.cmd("file " .. vim.fn.fnameescape(name))
                end
            end

            local function lines()
                return vim.api.nvim_buf_get_lines(0, 0, -1, false)
            end

            set_lines({ "one", "two" }, nil, 1)
            vim.fn.setreg('"', { "u1", "u2" }, "l")
            vim.cmd("put")
            local default_lines = lines()
            local default_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "one", "two" }, nil, 2)
            vim.fn.setreg('"', { "b1", "b2" }, "l")
            vim.cmd("put!")
            local bang_lines = lines()
            local bang_cursor = vim.api.nvim_win_get_cursor(0)

            set_lines({ "base" }, nil, 1)
            vim.cmd("put ='first'")
            vim.cmd("put ='second'")
            local seq_lines = lines()

            set_lines({ "one", "two" }, nil, 1)
            vim.fn.setreg("a", { "A" }, "l")
            vim.cmd("1pu a")
            local addressed_lines = lines()

            set_lines({ "one", "two" }, nil, 1)
            vim.fn.setreg("a", { "TOP" }, "l")
            vim.cmd("0put a")
            local zero_lines = lines()

            set_lines({ "one" }, nil, 1)
            vim.cmd("put ='x' .. 'y'")
            local expr_lines = lines()

            set_lines({ "one" }, nil, 1)
            vim.cmd("put ='keep'")
            vim.cmd("$put =")
            local expr_reuse_lines = lines()

            set_lines({ "one" }, nil, 1)
            vim.fn.setreg("a", "c1\nc2", "c")
            vim.cmd("put a")
            local charwise_lines = lines()

            set_lines({ "one" }, %q, 1)
            vim.cmd("put %%")
            local percent_lines = lines()

            set_lines({ "one" }, nil, 1)
            local missing_ok, missing_err = pcall(vim.cmd, "put z")

            set_lines({ "one" }, nil, 1)
            local bad_ok, bad_err = pcall(vim.cmd, "put aa")

            return {
                default_lines,
                default_cursor,
                bang_lines,
                bang_cursor,
                seq_lines,
                addressed_lines,
                zero_lines,
                expr_lines,
                expr_reuse_lines,
                charwise_lines,
                percent_lines,
                missing_ok,
                tostring(missing_err or ""),
                bad_ok,
                tostring(bad_err or ""),
            }
        ]], named_path))

        Assert.table_eq("put default inserts below current line", result[1], { "one", "u1", "u2", "two" })
        Assert.table_eq("put default moves cursor to last inserted line", result[2], { 3, 0 })
        Assert.table_eq("put! inserts before current line", result[3], { "one", "b1", "b2", "two" })
        Assert.table_eq("put! moves cursor to last inserted line", result[4], { 3, 0 })
        Assert.table_eq("sequential put preserves order", result[5], { "base", "first", "second" })
        Assert.table_eq("line address inserts after addressed line", result[6], { "one", "A", "two" })
        Assert.table_eq("0put inserts before first line", result[7], { "TOP", "one", "two" })
        Assert.table_eq("put expression inserts evaluated result", result[8], { "one", "xy" })
        Assert.table_eq("put expression reuses previous expression", result[9], { "one", "keep", "keep" })
        Assert.table_eq("put charwise register splits newlines", result[10], { "one", "c1", "c2" })
        Assert.table_eq("put %% inserts current buffer name", result[11], { "one", named_path })
        Assert.eq("put missing register fails", result[12], false)
        Assert.top_error_code("put missing register uses E353", result[13], "E353")
        Assert.eq("put invalid arg fails", result[14], false)
        Assert.top_error_code("put invalid arg uses E488", result[15], "E488")
    end,
}
