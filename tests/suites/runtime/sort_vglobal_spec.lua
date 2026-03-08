return {
    id = "runtime.sort_vglobal",
    description = "Ports sort and vglobal command behavior through real Ex execution.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "sort and vglobal scenarios", [[
            local function set_lines(lines, cursor_line)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { cursor_line or 1, 0 })
            end

            local function lines()
                return vim.api.nvim_buf_get_lines(0, 0, -1, false)
            end

            set_lines({ "hdr", "003 cc", "001 aa", "002 bb" }, 1)
            vim.cmd("2,$sort")
            local range_sort_lines = lines()

            set_lines({ "003 cc", "001 aa", "002 bb" }, 2)
            vim.cmd("sort")
            local default_sort_lines = lines()

            set_lines({ "hdr", "001 aa", "002 bb", "003 cc" }, 1)
            vim.cmd("2,$sort!")
            local reverse_sort_lines = lines()

            set_lines({ "a/", "b", "c." }, 1)
            vim.cmd("1,$v+[./]+s/^/X/")
            local vglobal_lines = lines()

            return {
                range_sort_lines,
                default_sort_lines,
                reverse_sort_lines,
                vglobal_lines,
            }
        ]])

        Assert.table_eq("range sort orders addressed lines", result[1], { "hdr", "001 aa", "002 bb", "003 cc" })
        Assert.table_eq("default sort uses whole buffer", result[2], { "001 aa", "002 bb", "003 cc" })
        Assert.table_eq("range reverse sort orders addressed lines", result[3], { "hdr", "003 cc", "002 bb", "001 aa" })
        Assert.table_eq("vglobal applies command to non-matches", result[4], { "a/", "Xb", "c." })
    end,
}
