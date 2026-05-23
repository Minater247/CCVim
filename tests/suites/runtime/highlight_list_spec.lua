return {
    id = "runtime.highlight_list",
    description = "Lists highlight groups through real :highlight execution.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "highlight list scenarios", [[
            vim.cmd('highlight default link CcvimCommentRegression String " trailing comment')
            return {
                vim.fn.execute("highlight"),
                vim.fn.execute("highlight String"),
                vim.fn.execute("highlight CcvimCommentRegression"),
            }
        ]])

        Assert.truthy(
            "highlight with no args lists groups",
            type(result[1]) == "string" and result[1]:find("String", 1, true) ~= nil,
            result[1]
        )
        Assert.truthy(
            "highlight single group lists that group",
            type(result[2]) == "string" and result[2]:find("String", 1, true) ~= nil,
            result[2]
        )
        Assert.truthy(
            "highlight link ignores trailing comment",
            type(result[3]) == "string" and result[3]:find("links to String", 1, true) ~= nil,
            result[3]
        )
    end,
}
