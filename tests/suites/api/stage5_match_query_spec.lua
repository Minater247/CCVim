return {
    id = "api.stage5_match_query",
    description = "Ports public stage5 syntax query behavior against Neovim reference semantics.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "stage5 match/query public behavior", [[
            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo bar", "zzz" })

            vim.cmd("2match Search /foo/")
            local matches = vim.fn.getmatches()
            vim.cmd("2match none")
            local cleared_matches = vim.fn.getmatches()

            vim.cmd("syntax clear")
            vim.cmd("syntax keyword String foo")
            local syn_id = vim.fn.synID(1, 1, 0)
            local syn_name = vim.fn.synIDattr(syn_id, "name")
            local stack = vim.fn.synstack(1, 1)
            local trans = vim.fn.synIDtrans(syn_id)
            local concealed = vim.fn.synconcealed(1, 1)
            local hl_id = vim.fn.hlID("String")

            vim.cmd("syntax clear")
            vim.cmd("syntax match TestLinked /foo/")
            vim.cmd("highlight default link TestLinked Comment")
            local linked_syntax_name = vim.fn.synIDattr(vim.fn.synID(1, 1, 1), "name")

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo" })
            local left_win = vim.api.nvim_get_current_win()
            vim.cmd("vsplit")
            local right_win = vim.api.nvim_get_current_win()

            vim.api.nvim_set_current_win(left_win)
            vim.cmd("syntax clear")
            vim.cmd("syntax keyword Comment foo")

            vim.api.nvim_set_current_win(right_win)
            vim.cmd("ownsyntax lua")
            vim.cmd("syntax keyword String foo")
            local right_name = vim.fn.synIDattr(vim.fn.synID(1, 1, 0), "name")

            vim.api.nvim_set_current_win(left_win)
            local left_name = vim.fn.synIDattr(vim.fn.synID(1, 1, 0), "name")

            return {
                matches = matches,
                cleared_matches = cleared_matches,
                syn_id = syn_id,
                syn_name = syn_name,
                stack = stack,
                trans = trans,
                concealed = concealed,
                hl_id = hl_id,
                linked_syntax_name = linked_syntax_name,
                left_name = left_name,
                right_name = right_name,
            }
        ]])

        Assert.eq("2match returns one match entry", #result.matches, 1)
        Assert.eq("2match uses slot id 2", result.matches[1].id, 2)
        Assert.eq("2match stores Search group", result.matches[1].group, "Search")
        Assert.eq("2match stores pattern", result.matches[1].pattern, "foo")
        Assert.eq("2match none clears matches", #result.cleared_matches, 0)

        Assert.truthy("synID returns non-zero", result.syn_id > 0, result.syn_id)
        Assert.eq("synIDattr(name)", result.syn_name, "String")
        Assert.truthy("synstack has at least one id", #result.stack >= 1, #result.stack)
        Assert.eq("synstack top id", result.stack[#result.stack], result.syn_id)
        Assert.truthy("synIDtrans returns id", result.trans > 0, result.trans)
        Assert.eq("synconcealed has 3 fields", #result.concealed, 3)
        Assert.eq("synconcealed not concealed", result.concealed[1], 0)
        Assert.truthy("hlID(String) non-zero", result.hl_id > 0, result.hl_id)
        Assert.eq(
            "synID keeps a non-transparent syntax group despite its highlight link",
            result.linked_syntax_name,
            "TestLinked"
        )

        Assert.eq("shared buffer regular window keeps buffer syntax", result.left_name, "Comment")
        Assert.eq("shared buffer ownsyntax window uses override syntax", result.right_name, "String")
    end,
}
