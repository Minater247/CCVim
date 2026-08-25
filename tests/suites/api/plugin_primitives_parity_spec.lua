return {
    id = "api.plugin_primitives_parity",
    description = "Checks Neovim primitives used by completion plugins.",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "plugin primitives", [[
            local old = vim.o.winborder
            vim.o.winborder = "rounded"
            local changed = vim.o.winborder
            vim.o.winborder = old
            return {
                vim.stricmp("alpha", "ALPHA"),
                vim.stricmp("alpha", "beta") < 0,
                vim.stricmp("beta", "alpha") > 0,
                vim.api.__definitely_not_an_api == nil,
                old,
                changed,
            }
        ]])

        ctx.assert.table_eq("plugin primitives", result, { 0, true, true, true, "", "rounded" })

        result = ctx.assert.eval_block(ctx.backend, "snippet primitives", [[
            vim.bo.tabstop = 4
            vim.bo.shiftwidth = 0
            local inherited = { vim.fn.shiftwidth(), vim.fn.shiftwidth(20) }
            vim.bo.shiftwidth = 3

            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "aéz", "second" })
            local utf8 = vim.api.nvim_buf_get_text(0, 0, 1, 0, 3, {})
            local multiline = vim.api.nvim_buf_get_text(0, 0, 3, 1, 3, {})
            vim.api.nvim_buf_set_text(0, 0, 1, 0, 3, { "X" })
            local edited = vim.api.nvim_get_current_line()

            local ns = vim.api.nvim_create_namespace("snippet-primitives")
            local id = vim.api.nvim_buf_set_extmark(0, ns, 0, 1, {
                end_line = 1,
                end_col = 2,
            })
            local mark = vim.api.nvim_buf_get_extmark_by_id(0, ns, id, { details = true })
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            local snippet_ok, snippet_err = pcall(vim.snippet.expand, "call(${1:value})$0")
            vim.wait(100)
            return {
                inherited = inherited,
                explicit = vim.fn.shiftwidth(),
                utf8 = utf8,
                multiline = multiline,
                edited = edited,
                mark = { mark[1], mark[2], mark[3].end_row, mark[3].end_col,
                    mark[3].right_gravity, mark[3].end_right_gravity, mark[3].ns_id == ns },
                missing = vim.api.nvim_buf_get_extmark_by_id(0, ns, id + 1, {}),
                snippet = { snippet_ok, tostring(snippet_err), vim.api.nvim_get_current_line(),
                    vim.snippet.active({ direction = 1 }) },
            }
        ]])

        ctx.assert.deep_eq("snippet primitives", result, {
            inherited = { 4, 4 },
            explicit = 3,
            utf8 = { "é" },
            multiline = { "z", "sec" },
            edited = "aXz",
            mark = { 0, 1, 1, 2, true, false, true },
            missing = {},
            snippet = { true, "nil", "call(value)", true },
        })
    end,
}
