return {
    id = "runtime.lualoader_error_codes",
    description = "Matches Neovim's file-backed Lua load and execution error codes and prefixes.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local syntax_path = Assert.temp_path(backend, "lua-syntax-error", ".lua")
        local runtime_path = Assert.temp_path(backend, "lua-runtime-error", ".lua")
        Assert.write_file(backend, syntax_path, "local broken =")
        Assert.write_file(backend, runtime_path, 'error("probe runtime failure")')

        local result = Assert.eval_block(backend, "Lua source errors", string.format([[
            local syntax_ok, syntax_err = pcall(vim.cmd, "source " .. %q)
            local runtime_ok, runtime_err = pcall(vim.cmd, "source " .. %q)
            local eval_syntax_ok, eval_syntax_err = pcall(vim.cmd, "lua local broken =")
            local eval_runtime_ok, eval_runtime_err = pcall(vim.cmd, 'lua error("probe runtime failure")')
            return {
                syntax_ok,
                tostring(syntax_err or ""),
                runtime_ok,
                tostring(runtime_err or ""),
                eval_syntax_ok,
                tostring(eval_syntax_err or ""),
                eval_runtime_ok,
                tostring(eval_runtime_err or ""),
            }
        ]], syntax_path, runtime_path))

        Assert.eq("syntax failure", result[1], false)
        Assert.top_error_code("syntax code", result[2], "E5112")
        Assert.truthy(
            "syntax prefix",
            result[2]:find("E5112: Error while creating lua chunk:", 1, true) ~= nil,
            result[2]
        )
        Assert.eq("runtime failure", result[3], false)
        Assert.top_error_code("runtime code", result[4], "E5113")
        Assert.truthy(
            "runtime prefix",
            result[4]:find("E5113: Error while calling lua chunk:", 1, true) ~= nil,
            result[4]
        )
        Assert.eq(":lua syntax failure", result[5], false)
        Assert.top_error_code(":lua syntax code", result[6], "E5107")
        Assert.truthy(
            ":lua syntax prefix",
            result[6]:find("E5107: Error loading lua ", 1, true) ~= nil,
            result[6]
        )
        Assert.eq(":lua runtime failure", result[7], false)
        Assert.top_error_code(":lua runtime code", result[8], "E5108")
        Assert.truthy(
            ":lua runtime prefix",
            result[8]:find("E5108: Error executing lua ", 1, true) ~= nil,
            result[8]
        )
    end,
}
