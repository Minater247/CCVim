return {
    id = "api.vim_key_notation",
    description = "Ports public key-notation parsing for Plug, Bar, Space, Ctrl-S, and literal non-key tokens.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "key notation scenarios", [[
            local rt = vim.api.nvim_replace_termcodes
            local plug = rt("<plug>(Foo)", true, false, true)
            local plug_canonical = rt("<Plug>(Foo)", true, false, true)
            local bar = rt("<Bar>", true, false, true)
            local space = rt("<Space>", true, false, true)
            local ctrl_s = rt("<C-s>", true, false, true)
            local cword = rt("<cword>", true, false, true)

            return {
                vim.fn.keytrans(plug),
                vim.fn.keytrans(plug_canonical),
                vim.fn.keytrans(bar),
                space,
                vim.fn.keytrans(ctrl_s),
                vim.fn.keytrans(cword),
            }
        ]])

        Assert.eq("plug token canonicalizes", result[1], "<Plug>(Foo)")
        Assert.eq("plug token keeps canonical form", result[2], "<Plug>(Foo)")
        Assert.eq("bar token maps to literal pipe", result[3], "|")
        Assert.eq("space token maps to literal space", result[4], " ")
        Assert.eq("ctrl-s parses as key notation", result[5], "<C-S>")
        Assert.eq("non-key token remains literal text", result[6], "<lt>cword>")
    end,
}
