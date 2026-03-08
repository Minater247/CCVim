return {
    id = "api.vim_call",
    description = "Ports vim.call coverage to the backend-independent harness.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.call scenarios", [[
            local len_ok, len_value = pcall(vim.call, "len", { 1, 2, 3 })
            local getcwd_ok, getcwd_value = pcall(vim.call, "getcwd")
            local getcwd_nil_ok, getcwd_nil_err = pcall(vim.call, "getcwd", nil)
            local numeric_ok, numeric_err = pcall(vim.call, 123)

            return {
                type(vim.call),
                len_ok,
                len_value,
                getcwd_ok,
                type(getcwd_value),
                tostring(getcwd_value or ""),
                getcwd_nil_ok,
                tostring(getcwd_nil_err or ""),
                numeric_ok,
                tostring(numeric_err or ""),
            }
        ]])

        Assert.eq("vim.call is function", result[1], "function")
        Assert.eq("vim.call len succeeds", result[2], true)
        Assert.eq("vim.call len result", result[3], 3)
        Assert.eq("vim.call getcwd succeeds", result[4], true)
        Assert.eq("vim.call getcwd returns string", result[5], "string")
        Assert.truthy("vim.call getcwd returns non-empty path", result[6] ~= "", result[6])
        Assert.eq("vim.call explicit nil fails", result[7], false)
        Assert.top_error_code("vim.call explicit nil uses E474", result[8], "E474")
        Assert.eq("vim.call numeric name fails", result[9], false)
        Assert.top_error_code("vim.call numeric name uses E117", result[10], "E117")
    end,
}
