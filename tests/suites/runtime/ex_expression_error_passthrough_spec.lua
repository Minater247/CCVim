return {
    id = "runtime.ex_expression_error_passthrough",
    description = "Ports Ex expression error reporting for one-line :for bodies; Neovim reports the underlying E117 directly instead of wrapping it in a Lua execution error.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "Ex expression errors stay as E117", [=[
            local ok, err = pcall(vim.cmd, [[for i in MissingFn() | echo "line" | endfor]])
            return {
                ok,
                tostring(err or ""),
            }
        ]=])

        Assert.eq("one-line for with missing expr function fails", result[1], false)
        Assert.top_error_code("missing expr function reports E117", result[2], "E117")
        Assert.truthy(
            "missing expr function does not get wrapped in E5108",
            result[2]:find("E5108", 1, true) == nil,
            result[2]
        )
    end,
}
