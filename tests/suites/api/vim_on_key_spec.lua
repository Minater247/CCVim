return {
    id = "api.vim_on_key",
    description = "Ports public vim.on_key registration, dispatch, consume, removal, and recursion behavior.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.on_key scenarios", [[
            local count_starts = vim.on_key()
            local seen = {}
            local ns = vim.on_key(function(key, typed)
                seen[#seen + 1] = { key, typed }
            end)

            local count_after_register = vim.on_key()
            vim.api.nvim_feedkeys("a", "nx", true)
            pcall(vim.cmd, "redraw")

            local cr_seen = nil
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "nx", true)
            pcall(vim.cmd, "redraw")
            cr_seen = seen[#seen]

            local nl_seen = nil
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-j>", true, false, true), "nx", true)
            pcall(vim.cmd, "redraw")
            nl_seen = seen[#seen]

            local consume_hits = 0
            local consume_ns = vim.on_key(function()
                consume_hits = consume_hits + 1
                return ""
            end)
            vim.api.nvim_feedkeys("b", "nx", true)
            pcall(vim.cmd, "redraw")
            vim.on_key(nil, consume_ns)

            local bad_ns = vim.on_key(function()
                return "not-empty"
            end)
            vim.api.nvim_feedkeys("c", "nx", true)
            pcall(vim.cmd, "redraw")
            local count_after_bad = vim.on_key()

            local err_ns = vim.on_key(function()
                error("boom")
            end)
            vim.api.nvim_feedkeys("d", "nx", true)
            pcall(vim.cmd, "redraw")
            local count_after_err = vim.on_key()

            local nested_calls = 0
            local rec_ns = vim.on_key(function()
                nested_calls = nested_calls + 1
                vim.api.nvim_feedkeys("z", "nx", true)
            end)
            vim.api.nvim_feedkeys("e", "nx", true)
            pcall(vim.cmd, "redraw")
            local count_before_cleanup = vim.on_key()

            vim.on_key(nil, bad_ns)
            vim.on_key(nil, err_ns)
            vim.on_key(nil, rec_ns)
            vim.on_key(nil, ns)

            return {
                count_starts,
                ns,
                count_after_register,
                #seen,
                seen[1],
                cr_seen,
                nl_seen,
                consume_hits,
                count_after_bad,
                count_after_err,
                nested_calls,
                count_before_cleanup,
                vim.on_key(),
            }
        ]])

        Assert.eq("vim.on_key count starts at zero", result[1], 0)
        Assert.truthy("vim.on_key namespace allocated", result[2] > 0, result[2])
        Assert.eq("vim.on_key count after registration", result[3], 1)
        Assert.truthy("vim.on_key callback fired", result[4] >= 1, result[4])
        Assert.eq("vim.on_key first key", result[5][1], "a")
        Assert.eq("vim.on_key CR key", result[6][1], "\r")
        Assert.eq("vim.on_key NL key", result[7][1], "\n")
        Assert.truthy("vim.on_key consume callback fired", result[8] >= 1, result[8])
        Assert.eq("vim.on_key invalid return callback removed", result[9], 1)
        Assert.eq("vim.on_key erroring callback removed", result[10], 1)
        Assert.eq("vim.on_key recursive dispatch suppressed", result[11], 1)
        Assert.eq("vim.on_key callback count before cleanup", result[12], 2)
        Assert.eq("vim.on_key callbacks removed", result[13], 0)
    end,
}
