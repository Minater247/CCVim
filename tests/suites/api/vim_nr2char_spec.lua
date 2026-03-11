return {
    id = "api.vim_nr2char",
    description = "Ports vim.fn.nr2char() for ASCII, UTF-8, extended byte sequences, and error handling.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nr2char parity", [[
            local function bytes(s)
                return { string.byte(s, 1, #s) }
            end

            local ok_negative, err_negative = pcall(function()
                return vim.fn.nr2char(-1)
            end)

            return {
                ascii = vim.fn.nr2char(64),
                ctrl_w = bytes(vim.fn.nr2char(23)),
                nul = vim.fn.nr2char(0),
                unicode = bytes(vim.fn.nr2char(300)),
                unicode_utf8 = bytes(vim.fn.nr2char(300, true)),
                extended = bytes(vim.fn.nr2char(0x110000)),
                string_number = bytes(vim.fn.nr2char("0x41")),
                negative = { ok_negative, tostring(err_negative or "") },
            }
        ]])

        Assert.eq("nr2char ascii output", result.ascii, "@")
        Assert.table_eq("nr2char ctrl-w byte", result.ctrl_w, { 23 })
        Assert.eq("nr2char zero returns empty string", result.nul, "")
        Assert.table_eq("nr2char unicode bytes", result.unicode, { 196, 172 })
        Assert.table_eq("nr2char unicode bytes ignore utf8 flag", result.unicode_utf8, { 196, 172 })
        Assert.table_eq("nr2char extended bytes", result.extended, { 244, 144, 128, 128 })
        Assert.table_eq("nr2char accepts string numbers", result.string_number, { 65 })
        Assert.eq("nr2char negative result", result.negative[1], false)
        Assert.top_error_code("nr2char negative emits E5070", result.negative[2], "E5070")

        Assert.expect_error_code_block(backend, "nr2char extra arg emits E118", [[
            vim.fn.nr2char(65, true, false)
        ]], "E118")
    end,
}
