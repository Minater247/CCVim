return {
    id = "api.vim_termcodes",
    description = "Ports replace_termcodes/keytrans coverage through public Neovim APIs.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "termcode scenarios", [[
            local cr = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
            local cmd = vim.api.nvim_replace_termcodes("<Cmd>echo 1<CR>", true, false, true)
            local star = vim.api.nvim_replace_termcodes("<*C-j>", true, false, true)
            local nonstar = vim.api.nvim_replace_termcodes("<C-j>", true, false, true)

            return {
                string.byte(cr),
                string.byte(cmd, 1),
                string.byte(cmd, 2),
                string.byte(cmd, 3),
                string.byte(cmd, #cmd),
                vim.fn.keytrans(cmd),
                vim.fn.keytrans(star),
                vim.fn.keytrans(nonstar),
            }
        ]])

        Assert.eq("replace_termcodes CR byte", result[1], 13)
        Assert.eq("replace_termcodes Cmd prefix b1", result[2], 128)
        Assert.eq("replace_termcodes Cmd prefix b2", result[3], 253)
        Assert.eq("replace_termcodes Cmd prefix b3", result[4], 104)
        Assert.eq("replace_termcodes Cmd suffix byte", result[5], 13)
        Assert.eq("replace_termcodes Cmd keytrans", result[6], "<Cmd>echo<Space>1<CR>")
        Assert.eq("keytrans star ctrl-j", result[7], "<NL>")
        Assert.eq("keytrans non-star ctrl-j", result[8], "<NL>")
    end,
}
