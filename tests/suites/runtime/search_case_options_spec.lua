return {
    id = "runtime.search_case_options",
    description = "Checks search case rules and hlsearch suspension against Neovim",

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "search case options", [[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {
                "alpha",
                "ALPHA",
                "Alpha",
            })

            local function find(pattern, ignorecase, smartcase)
                vim.o.ignorecase = ignorecase
                vim.o.smartcase = smartcase
                vim.api.nvim_win_set_cursor(0, { 1, 0 })
                vim.fn.search(pattern)
                return vim.api.nvim_win_get_cursor(0)
            end

            vim.o.hlsearch = true
            vim.cmd("nohlsearch")
            local suspended = { vim.o.hlsearch, vim.v.hlsearch }
            vim.o.hlsearch = true
            local restored = { vim.o.hlsearch, vim.v.hlsearch }

            return {
                find("alpha", false, false),
                find("alpha", true, false),
                find("alpha", true, true),
                find("Alpha", true, true),
                find("alpha\\C", true, false),
                find("Alpha\\c", false, false),
                suspended,
                restored,
            }
        ]])

        ctx.assert.deep_eq("search case and highlight options", result, {
            { 1, 0 },
            { 2, 0 },
            { 2, 0 },
            { 3, 0 },
            { 1, 0 },
            { 2, 0 },
            { true, 0 },
            { true, 1 },
        })
    end,
}
