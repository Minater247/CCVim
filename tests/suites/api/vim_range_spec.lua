return {
    id = "api.vim_range",
    description = "Ports vim.fn.range() semantics and one-line :for | echo | endfor execution through the public Vim API.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.fn.range scenarios", [=[
            local loop_output = vim.fn.execute([[for i in range(1, 3) | echo "line" | endfor]], "")
            local bad_ok, bad_err = pcall(vim.fn.range, 2, 0)
            local zero_ok, zero_err = pcall(vim.fn.range, 1, 5, 0)
            local function format_err(err)
                if type(err) == "table" and type(err.toString) == "function" then
                    return err:toString()
                end
                return tostring(err or "")
            end

            return {
                vim.fn.range(4),
                vim.fn.range(2, 4),
                vim.fn.range(2, 9, 3),
                vim.fn.range(2, -2, -1),
                vim.fn.range(0),
                loop_output,
                bad_ok,
                format_err(bad_err),
                zero_ok,
                format_err(zero_err),
            }
        ]=])

        Assert.table_eq("range single-arg", result[1], { 0, 1, 2, 3 })
        Assert.table_eq("range bounded", result[2], { 2, 3, 4 })
        Assert.table_eq("range stride", result[3], { 2, 5, 8 })
        Assert.table_eq("range descending", result[4], { 2, 1, 0, -1, -2 })
        Assert.table_eq("range zero is empty", result[5], {})
        Assert.eq("one-line for loop echoes each iteration", result[6], "\nline\nline\nline")
        Assert.eq("range start-past-end fails", result[7], false)
        Assert.top_error_code("range start-past-end uses E727", result[8], "E727")
        Assert.eq("range zero-stride fails", result[9], false)
        Assert.top_error_code("range zero-stride uses E726", result[10], "E726")
    end,
}
