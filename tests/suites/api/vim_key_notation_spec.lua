return {
    id = "api.vim_key_notation",
    description = "Ports public key-notation parsing for Plug, Bar, Space, Ctrl-S, and literal non-key tokens.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "key notation scenarios", [[
            local rt = vim.api.nvim_replace_termcodes
            local plug = rt("<plug>(Foo)", true, false, true)
            local plug_canonical = rt("<Plug>(Foo)", true, false, true)
            local bar = rt("<Bar>", true, false, true)
            local bar_lower = rt("<bar>", true, false, true)
            local space = rt("<Space>", true, false, true)
            local ctrl_s = rt("<C-s>", true, false, true)
            local cword = rt("<cword>", true, false, true)
            vim.g.mapleader = ","
            vim.g.maplocalleader = ";"
            local leader = rt("<Leader>x", true, false, true)
            local local_leader = rt("<localleader>x", true, false, true)
            vim.g.mapleader = ""
            vim.g.maplocalleader = nil
            local default_leader = rt("<Leader>x", true, false, true)
            local default_local_leader = rt("<LocalLeader>x", true, false, true)
            vim.g.mapleader = "<Space>"
            local literal_leader = rt("<Leader>x", true, false, true)
            vim.g.mapleader = ","
            vim.g.leader_capture = false
            vim.keymap.set("n", "<Leader>z", function() vim.g.leader_capture = true end)
            vim.g.mapleader = ";"
            vim.api.nvim_feedkeys(",z", "mx", false)

            return {
                vim.fn.keytrans(plug),
                vim.fn.keytrans(plug_canonical),
                vim.fn.keytrans(bar),
                vim.fn.keytrans(bar_lower),
                space,
                vim.fn.keytrans(ctrl_s),
                vim.fn.keytrans(cword),
                leader,
                local_leader,
                default_leader,
                default_local_leader,
                literal_leader,
                vim.g.leader_capture,
            }
        ]])

        Assert.eq("plug token canonicalizes", result[1], "<Plug>(Foo)")
        Assert.eq("plug token keeps canonical form", result[2], "<Plug>(Foo)")
        Assert.eq("bar token maps to literal pipe", result[3], "|")
        Assert.eq("bar token is case-insensitive", result[4], "|")
        Assert.eq("space token maps to literal space", result[5], " ")
        Assert.eq("ctrl-s parses as key notation", result[6], "<C-S>")
        Assert.eq("non-key token remains literal text", result[7], "<lt>cword>")
        Assert.eq("leader uses current global value", result[8], ",x")
        Assert.eq("local leader token is case-insensitive", result[9], ";x")
        Assert.eq("empty leader defaults to backslash", result[10], "\\x")
        Assert.eq("unset local leader defaults to backslash", result[11], "\\x")
        Assert.eq("leader value is inserted literally", result[12], "<Space>x")
        Assert.eq("mapping captures leader at definition", result[13], true)
    end,
}
