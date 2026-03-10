return {
    id = "runtime.highlight_list",
    description = "Lists highlight groups through real :highlight execution.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "highlight list scenarios", [[
            return {
                vim.fn.execute("highlight"),
                vim.fn.execute("highlight String"),
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
    end,
}
