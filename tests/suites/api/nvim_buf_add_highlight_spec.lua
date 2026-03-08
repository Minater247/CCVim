return {
    id = "api.nvim_buf_add_highlight",
    description = "Ports nvim_buf_add_highlight coverage through public namespace/extmark APIs.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nvim_buf_add_highlight scenarios", [[
            local bufnr = vim.api.nvim_create_buf(true, false)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "first", "second" })

            local ns1 = vim.api.nvim_create_namespace("test1")
            local ret = vim.api.nvim_buf_add_highlight(bufnr, ns1, "ErrorMsg", 0, 1, 2)

            local full_end = { 1, -1 }
            local ext = vim.api.nvim_buf_get_extmarks(bufnr, ns1, { 0, 0 }, full_end, { details = true })

            local ns2 = vim.api.nvim_buf_add_highlight(bufnr, 0, "Search", 0, 0, 1)
            local ext2 = vim.api.nvim_buf_get_extmarks(bufnr, ns2, { 0, 0 }, full_end, { details = true })

            local ns3 = vim.api.nvim_buf_add_highlight(bufnr, 0, "", 0, 0, 1)
            local ext3 = vim.api.nvim_buf_get_extmarks(bufnr, ns3, { 0, 0 }, full_end, {})

            local before = vim.api.nvim_buf_get_extmarks(bufnr, -1, { 0, 0 }, full_end, {})
            vim.api.nvim_buf_add_highlight(bufnr, -1, "WarningMsg", 1, 0, -1)
            local after = vim.api.nvim_buf_get_extmarks(bufnr, -1, { 0, 0 }, full_end, {})

            return {
                ns1,
                ret,
                ext,
                ns2,
                ext2,
                ns3,
                ext3,
                #before,
                #after,
            }
        ]])

        Assert.truthy("namespace should be positive", result[1] > 0, result[1])
        Assert.eq("returned ns_id matches", result[2], result[1])
        Assert.eq("one extmark in namespace", #result[3], 1)
        Assert.eq("extmark hl_group", result[3][1][4].hl_group, "ErrorMsg")
        Assert.eq("extmark end_col", result[3][1][4].end_col, 2)

        Assert.truthy("new namespace allocated", result[4] > 0 and result[4] ~= result[1], result[4])
        Assert.eq("new namespace gets one mark", #result[5], 1)
        Assert.eq("new namespace hl_group", result[5][1][4].hl_group, "Search")

        Assert.truthy("empty hl_group still returns namespace", result[6] > 0, result[6])
        Assert.eq("no extmarks when hl_group is empty", #result[7], 0)

        Assert.eq("ungrouped highlight count increments", result[9], result[8] + 1)
    end,
}
