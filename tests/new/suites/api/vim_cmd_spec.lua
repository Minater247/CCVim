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
        Assert.eq("vim.cmd bad command errors", result[22], false)
        Assert.truthy("vim.cmd bad command reports E492", result[23]:find("E492", 1, true) ~= nil, result[23])
        Assert.eq("vim.cmd bad command leaves v:errmsg empty", result[24], "")
    end,
}
