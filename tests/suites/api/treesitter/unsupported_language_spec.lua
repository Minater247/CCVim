return {
    id = "api.treesitter.unsupported_language",
    description = "Ports public Treesitter parser/start failure behavior for clearly unsupported languages against Neovim reference semantics.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "treesitter unsupported language parity", [[
            vim.o.swapfile = false

            local parser, parser_err = vim.treesitter.get_parser(0, "ccvim_missing_lang", { error = false })
            local start_ok, start_err = pcall(function()
                return vim.treesitter.start(0, "ccvim_missing_lang")
            end)

            return {
                parser == nil,
                tostring(parser_err or ""),
                start_ok,
                tostring(start_err or ""),
            }
        ]])

        Assert.eq("unsupported parser is nil", result[1], true)
        Assert.truthy(
            "unsupported parser reports the missing language",
            type(result[2]) == "string" and result[2]:find('ccvim_missing_lang', 1, true) ~= nil,
            result[2]
        )
        Assert.eq("unsupported start fails", result[3], false)
        Assert.truthy(
            "unsupported start reports the missing language",
            type(result[4]) == "string" and result[4]:find('ccvim_missing_lang', 1, true) ~= nil,
            result[4]
        )
    end,
}
