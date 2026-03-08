return {
    id = "api.vim_cmd",
    description = "Ports vim.cmd invocation styles and related public table helpers.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.cmd and helper scenarios", [[
            local mt = getmetatable(vim.cmd)
            local rv_string = vim.cmd("set number")
            local number_enabled = vim.wo.number

            local vals = vim.tbl_values({ a = 1, b = 2 })
            table.sort(vals)

            local keys = vim.tbl_keys({ a = 1, b = 2 })
            table.sort(keys)

            local dst = { 1 }
            local out = vim.list_extend(dst, { 2, 3, 4 }, 2, 3)

            local dict_dst = { a = 1 }
            vim.list_extend(dict_dst, { 9 })

            local dict_src_target = { 1 }
            vim.list_extend(dict_src_target, { a = 2 })

            local ok_dst_type = pcall(function()
                vim.list_extend("x", { 1 })
            end)
            local ok_src_type = pcall(function()
                vim.list_extend({ 1 }, "x")
            end)
            local ok_start_type = pcall(function()
                vim.list_extend({ 1 }, { 2 }, "x")
            end)
            local ok_finish_type = pcall(function()
                vim.list_extend({ 1 }, { 2 }, 1, "x")
            end)

            local trim1 = vim.trim("  x  ")
            local trim2 = vim.trim(" \t\r\n ")
            local ok_trim_type = pcall(function()
                vim.trim(42)
            end)

            local rv_indexed = vim.cmd.highlight("clear")
            local rv_indexed_table = vim.cmd.highlight({ "clear", bang = true })
            local rv_table = vim.cmd({
                cmd = "highlight",
                args = { "clear" },
            })

            vim.cmd("enew!")
            vim.cmd("file cmd_close_one")
            vim.cmd("split")
            vim.cmd("enew!")
            vim.cmd("file cmd_close_two")
            vim.cmd("split")
            vim.cmd("enew!")
            vim.cmd("file cmd_close_three")
            vim.cmd("1wincmd w")

            local close_before = {}
            local close_before_wins = vim.api.nvim_tabpage_list_wins(0)
            for i = 1, #close_before_wins do
                close_before[i] = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(close_before_wins[i]))
            end
            local close_before_current = vim.fn.winnr()

            vim.cmd.close({ count = 2 })

            local close_after = {}
            local close_after_wins = vim.api.nvim_tabpage_list_wins(0)
            for i = 1, #close_after_wins do
                close_after[i] = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(close_after_wins[i]))
            end
            local close_after_current = vim.fn.winnr()

            local ok_count_disallowed, err_count_disallowed = pcall(function()
                vim.cmd.echo({ "x", count = 2 })
            end)
            local ok_range_disallowed, err_range_disallowed = pcall(function()
                vim.cmd.echo({ "x", range = { 1, 2 } })
            end)

            vim.v.errmsg = ""
            local ok_bad, err_bad = pcall(vim.cmd, "badcmd")

            return {
                type(vim.cmd),
                type(mt and mt.__call),
                rv_string,
                number_enabled,
                vals,
                keys,
                out == dst,
                dst,
                dict_dst.a,
                dict_dst[1],
                dict_src_target,
                ok_dst_type,
                ok_src_type,
                ok_start_type,
                ok_finish_type,
                trim1,
                trim2,
                ok_trim_type,
                rv_indexed,
                rv_indexed_table,
                rv_table,
                close_before,
                close_before_current,
                close_after,
                close_after_current,
                ok_count_disallowed,
                tostring(err_count_disallowed or ""),
                ok_range_disallowed,
                tostring(err_range_disallowed or ""),
                ok_bad,
                tostring(err_bad),
                vim.v.errmsg,
            }
        ]])

        Assert.eq("vim.cmd is table", result[1], "table")
        Assert.eq("vim.cmd has __call", result[2], "function")
        Assert.eq("vim.cmd string call returns empty string", result[3], "")
        Assert.eq("vim.cmd string call executes", result[4], true)
        Assert.table_eq("vim.tbl_values returns values", result[5], { 1, 2 })
        Assert.table_eq("vim.tbl_keys returns keys", result[6], { "a", "b" })
        Assert.eq("vim.list_extend returns destination table", result[7], true)
        Assert.table_eq("vim.list_extend appends selected range", result[8], { 1, 3, 4 })
        Assert.eq("vim.list_extend preserves existing dict keys", result[9], 1)
        Assert.eq("vim.list_extend allows dict-like dst", result[10], 9)
        Assert.table_eq("vim.list_extend with dict-like src is no-op", result[11], { 1 })
        Assert.eq("vim.list_extend validates dst type", result[12], false)
        Assert.eq("vim.list_extend validates src type", result[13], false)
        Assert.eq("vim.list_extend validates start type", result[14], false)
        Assert.eq("vim.list_extend validates finish type", result[15], false)
        Assert.eq("vim.trim trims outer whitespace", result[16], "x")
        Assert.eq("vim.trim all-whitespace yields empty", result[17], "")
        Assert.eq("vim.trim validates input type", result[18], false)
        Assert.eq("indexed vim.cmd call returns empty string", result[19], "")
        Assert.eq("indexed table vim.cmd call returns empty string", result[20], "")
        Assert.eq("table-form vim.cmd call returns empty string", result[21], "")
        Assert.eq("vim.cmd.close count starts on first window", result[23], 1)
        Assert.eq("vim.cmd.close count starts with three windows", #result[22], 3)
        Assert.eq("vim.cmd.close count leaves two windows", #result[24], 2)
        Assert.eq("vim.cmd.close count keeps current window", result[25], 1)
        Assert.eq("vim.cmd.close count keeps first window", result[24][1], result[22][1])
        Assert.eq("vim.cmd.close count removes second window", result[24][2], result[22][3])
        Assert.eq("vim.cmd structured count rejects echo", result[26], false)
        Assert.truthy(
            "vim.cmd structured count error message",
            result[27]:find("Command cannot accept count: echo", 1, true) ~= nil,
            result[27]
        )
        Assert.eq("vim.cmd structured range rejects echo", result[28], false)
        Assert.truthy(
            "vim.cmd structured range error message",
            result[29]:find("Command cannot accept range: echo", 1, true) ~= nil,
            result[29]
        )
        Assert.eq("vim.cmd bad command errors", result[30], false)
        Assert.top_error_code("vim.cmd bad command reports E492", result[31], "E492")
        Assert.eq("vim.cmd bad command leaves v:errmsg empty", result[32], "")
    end,
}
