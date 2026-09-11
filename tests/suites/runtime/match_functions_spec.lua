return {
    id = "runtime.match_functions",
    description = "Checks Vim match-family builtin parity.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "matchend parity", [[
            return {
                vim.fn.matchend("testing", "ing"),
                vim.fn.matchend("testing", "ing", 2),
                vim.fn.matchend("testing", "ing", 5),
                vim.fn.matchend({ "x", "testing" }, "ing"),
            }
        ]])

        Assert.table_eq("matchend results", result, { 7, 7, -1, 1 })

        local string_results = Assert.eval_block(backend, "match family string spans", [[
            local whole = "    value[index]"
            local anchored = "^.*\\%16c\\zs]$"
            return {
                vim.fn.match("testing", "..", 0, 2),
                vim.fn.matchstr("testing", "..", 0, 2),
                vim.fn.matchstrpos("testing", "..", 0, 2),
                vim.fn.match("abc", "^", 1),
                vim.fn.match("abc", "^", 1, 1),
                vim.fn.match("abc", ".", 0, 0),
                vim.fn.matchstrpos(whole, anchored),
            }
        ]])

        Assert.eq("match count permits overlapping matches", string_results[1], 1)
        Assert.eq("matchstr count returns overlapping match", string_results[2], "es")
        Assert.deep_eq("matchstrpos count span", string_results[3], { "es", 1, 3 })
        Assert.eq("match start treats suffix as string start", string_results[4], 1)
        Assert.eq("match count preserves original string start", string_results[5], -1)
        Assert.eq("match zero count selects the first string match", string_results[6], 0)
        Assert.deep_eq("matchstrpos preserves anchored zs span", string_results[7], { "]", 15, 16 })
    end,
}
