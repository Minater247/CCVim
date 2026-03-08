return {
    id = "api.vim_reg_recording",
    description = "Ports reg_recording(), reg_executing(), and reg_recorded() through real macro recording.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "register recording state", [[
            local function feed(keys)
                local termcoded = vim.api.nvim_replace_termcodes(keys, true, false, true)
                vim.api.nvim_feedkeys(termcoded, "mx", false)
            end

            vim.cmd("enew!")
            vim.g.reg_recording_seen = "<unset>"
            vim.g.reg_executing_seen = "<unset>"

            local defaults = {
                vim.fn.reg_recording(),
                vim.fn.reg_executing(),
                vim.fn.reg_recorded(),
            }

            feed("qq:let g:reg_recording_seen = reg_recording() | let g:reg_executing_seen = reg_executing()<CR>q")

            local after_record = {
                vim.g.reg_recording_seen,
                vim.g.reg_executing_seen,
                vim.fn.reg_recording(),
                vim.fn.reg_executing(),
                vim.fn.reg_recorded(),
            }

            vim.g.reg_recording_seen = "<unset>"
            vim.g.reg_executing_seen = "<unset>"
            feed("@q")

            local after_execute = {
                vim.fn.reg_recording(),
                vim.fn.reg_executing(),
                vim.fn.reg_recorded(),
            }

            return {
                defaults,
                after_record,
                after_execute,
            }
        ]])

        Assert.table_eq("default register state is empty", result[1], { "", "", "" })
        Assert.table_eq(
            "recording exposes recording register and last recorded",
            result[2],
            { "q", "", "", "", "q" }
        )
        Assert.table_eq(
            "executing exposes executing register and last recorded",
            result[3],
            { "", "q", "q" }
        )
    end,
}
