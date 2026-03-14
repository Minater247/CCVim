return {
    id = "runtime.vim_bo_local_option_parity",
    description = "Checks that vim.bo and nvim_get/set_option_value with { buf = ... } behave like buffer-local access, not global-effective :set semantics.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.bo local option parity", [[
            vim.go.tabstop = 4
            vim.go.keywordprg = ":GlobalKeywordPrg"

            local before_bo_tabstop = vim.bo.tabstop
            local before_bo_keywordprg = vim.bo.keywordprg
            local before_api_tabstop = vim.api.nvim_get_option_value("tabstop", { buf = 0 })
            local before_api_keywordprg = vim.api.nvim_get_option_value("keywordprg", { buf = 0 })
            local before_global_tabstop = vim.go.tabstop
            local before_global_keywordprg = vim.go.keywordprg

            vim.bo.tabstop = 6
            vim.bo.keywordprg = ":LocalKeywordPrg"
            local after_vim_bo_bo_tabstop = vim.bo.tabstop
            local after_vim_bo_bo_keywordprg = vim.bo.keywordprg
            local after_vim_bo_api_tabstop = vim.api.nvim_get_option_value("tabstop", { buf = 0 })
            local after_vim_bo_api_keywordprg = vim.api.nvim_get_option_value("keywordprg", { buf = 0 })
            local after_vim_bo_global_tabstop = vim.go.tabstop
            local after_vim_bo_global_keywordprg = vim.go.keywordprg

            vim.cmd("enew!")
            local after_vim_bo_new_bo_tabstop = vim.bo.tabstop
            local after_vim_bo_new_bo_keywordprg = vim.bo.keywordprg
            local after_vim_bo_new_api_tabstop = vim.api.nvim_get_option_value("tabstop", { buf = 0 })
            local after_vim_bo_new_api_keywordprg = vim.api.nvim_get_option_value("keywordprg", { buf = 0 })
            local after_vim_bo_new_global_tabstop = vim.go.tabstop
            local after_vim_bo_new_global_keywordprg = vim.go.keywordprg

            vim.api.nvim_set_option_value("tabstop", 5, { buf = 0 })
            vim.api.nvim_set_option_value("keywordprg", ":ApiLocalKeywordPrg", { buf = 0 })
            local after_api_bo_tabstop = vim.bo.tabstop
            local after_api_bo_keywordprg = vim.bo.keywordprg
            local after_api_api_tabstop = vim.api.nvim_get_option_value("tabstop", { buf = 0 })
            local after_api_api_keywordprg = vim.api.nvim_get_option_value("keywordprg", { buf = 0 })
            local after_api_global_tabstop = vim.go.tabstop
            local after_api_global_keywordprg = vim.go.keywordprg

            vim.cmd("enew!")
            local after_api_new_bo_tabstop = vim.bo.tabstop
            local after_api_new_bo_keywordprg = vim.bo.keywordprg
            local after_api_new_api_tabstop = vim.api.nvim_get_option_value("tabstop", { buf = 0 })
            local after_api_new_api_keywordprg = vim.api.nvim_get_option_value("keywordprg", { buf = 0 })
            local after_api_new_global_tabstop = vim.go.tabstop
            local after_api_new_global_keywordprg = vim.go.keywordprg

            return {
                before_bo_tabstop = before_bo_tabstop,
                before_bo_keywordprg = before_bo_keywordprg,
                before_api_tabstop = before_api_tabstop,
                before_api_keywordprg = before_api_keywordprg,
                before_global_tabstop = before_global_tabstop,
                before_global_keywordprg = before_global_keywordprg,

                after_vim_bo_bo_tabstop = after_vim_bo_bo_tabstop,
                after_vim_bo_bo_keywordprg = after_vim_bo_bo_keywordprg,
                after_vim_bo_api_tabstop = after_vim_bo_api_tabstop,
                after_vim_bo_api_keywordprg = after_vim_bo_api_keywordprg,
                after_vim_bo_global_tabstop = after_vim_bo_global_tabstop,
                after_vim_bo_global_keywordprg = after_vim_bo_global_keywordprg,

                after_vim_bo_new_bo_tabstop = after_vim_bo_new_bo_tabstop,
                after_vim_bo_new_bo_keywordprg = after_vim_bo_new_bo_keywordprg,
                after_vim_bo_new_api_tabstop = after_vim_bo_new_api_tabstop,
                after_vim_bo_new_api_keywordprg = after_vim_bo_new_api_keywordprg,
                after_vim_bo_new_global_tabstop = after_vim_bo_new_global_tabstop,
                after_vim_bo_new_global_keywordprg = after_vim_bo_new_global_keywordprg,

                after_api_bo_tabstop = after_api_bo_tabstop,
                after_api_bo_keywordprg = after_api_bo_keywordprg,
                after_api_api_tabstop = after_api_api_tabstop,
                after_api_api_keywordprg = after_api_api_keywordprg,
                after_api_global_tabstop = after_api_global_tabstop,
                after_api_global_keywordprg = after_api_global_keywordprg,

                after_api_new_bo_tabstop = after_api_new_bo_tabstop,
                after_api_new_bo_keywordprg = after_api_new_bo_keywordprg,
                after_api_new_api_tabstop = after_api_new_api_tabstop,
                after_api_new_api_keywordprg = after_api_new_api_keywordprg,
                after_api_new_global_tabstop = after_api_new_global_tabstop,
                after_api_new_global_keywordprg = after_api_new_global_keywordprg,
            }
        ]])
        Assert.eq("vim.bo tabstop sees current local value", result.before_bo_tabstop, 8)
        Assert.eq("vim.bo keywordprg sees current local value", result.before_bo_keywordprg, "")
        Assert.eq("api buf tabstop sees current local value", result.before_api_tabstop, 8)
        Assert.eq("api buf keywordprg sees current local value", result.before_api_keywordprg, "")
        Assert.eq("global tabstop stays configured value", result.before_global_tabstop, 4)
        Assert.eq("global keywordprg stays configured value", result.before_global_keywordprg, ":GlobalKeywordPrg")

        Assert.eq("vim.bo tabstop writes local value", result.after_vim_bo_bo_tabstop, 6)
        Assert.eq("vim.bo keywordprg writes local value", result.after_vim_bo_bo_keywordprg, ":LocalKeywordPrg")
        Assert.eq("api buf tabstop sees vim.bo local write", result.after_vim_bo_api_tabstop, 6)
        Assert.eq("api buf keywordprg sees vim.bo local write", result.after_vim_bo_api_keywordprg, ":LocalKeywordPrg")
        Assert.eq("vim.bo write leaves global tabstop alone", result.after_vim_bo_global_tabstop, 4)
        Assert.eq("vim.bo write leaves global keywordprg alone", result.after_vim_bo_global_keywordprg, ":GlobalKeywordPrg")

        Assert.eq("new buffer after vim.bo write uses global tabstop", result.after_vim_bo_new_bo_tabstop, 4)
        Assert.eq("new buffer after vim.bo write has empty local keywordprg", result.after_vim_bo_new_bo_keywordprg, "")
        Assert.eq("api buf on new buffer uses global-seeded tabstop", result.after_vim_bo_new_api_tabstop, 4)
        Assert.eq("api buf on new buffer still reads local keywordprg", result.after_vim_bo_new_api_keywordprg, "")
        Assert.eq("globals persist after buffer creation tabstop", result.after_vim_bo_new_global_tabstop, 4)
        Assert.eq("globals persist after buffer creation keywordprg", result.after_vim_bo_new_global_keywordprg, ":GlobalKeywordPrg")

        Assert.eq("api buf set writes local tabstop", result.after_api_bo_tabstop, 5)
        Assert.eq("api buf set writes local keywordprg", result.after_api_bo_keywordprg, ":ApiLocalKeywordPrg")
        Assert.eq("api buf get sees its own local tabstop", result.after_api_api_tabstop, 5)
        Assert.eq("api buf get sees its own local keywordprg", result.after_api_api_keywordprg, ":ApiLocalKeywordPrg")
        Assert.eq("api buf set leaves global tabstop alone", result.after_api_global_tabstop, 4)
        Assert.eq("api buf set leaves global keywordprg alone", result.after_api_global_keywordprg, ":GlobalKeywordPrg")

        Assert.eq("new buffer after api buf set uses global tabstop", result.after_api_new_bo_tabstop, 4)
        Assert.eq("new buffer after api buf set has empty local keywordprg", result.after_api_new_bo_keywordprg, "")
        Assert.eq("api buf on second new buffer sees global-seeded tabstop", result.after_api_new_api_tabstop, 4)
        Assert.eq("api buf on second new buffer still reads local keywordprg", result.after_api_new_api_keywordprg, "")
        Assert.eq("globals remain unchanged after api buf set tabstop", result.after_api_new_global_tabstop, 4)
        Assert.eq("globals remain unchanged after api buf set keywordprg", result.after_api_new_global_keywordprg, ":GlobalKeywordPrg")
    end,
}
