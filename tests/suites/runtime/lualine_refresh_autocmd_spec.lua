return {
    id = "runtime.lualine_refresh_autocmd",
    description = "Exercises Lualine's refresh autocommand definition and callback payload.",
    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "lualine refresh autocommands", [=[
            local calls = {}
            package.loaded.lualine_refresh_probe = {
                refresh = function(opts)
                    calls[#calls + 1] = opts
                end,
            }

            vim.cmd("call v:lua.require'lualine_refresh_probe'.refresh("
                .. "{'kind': 'tabpage', 'place': ['statusline'], 'trigger': 'direct'})")
            local direct_call = calls[1]
            calls = {}
            local paren_require = pcall(vim.cmd,
                "call v:lua.require('lualine_refresh_probe').refresh({})")
            local double_quote_require = pcall(vim.cmd,
                'call v:lua.require"lualine_refresh_probe".refresh({})')
            calls = {}

            vim.cmd([[augroup lualine_refresh_probe | exe "autocmd!" | augroup END]])
            vim.cmd("autocmd lualine_refresh_probe "
                .. "WinEnter,BufEnter,BufWritePost,Filetype,CursorMoved,CursorMovedI,ModeChanged * "
                .. "call v:lua.require'lualine_refresh_probe'.refresh("
                .. "{'kind': 'tabpage', 'place': ['statusline'], 'trigger': 'autocmd'})")

            local events = {
                "WinEnter", "BufEnter", "BufWritePost", "Filetype",
                "CursorMoved", "CursorMovedI", "ModeChanged",
            }
            for _, event in ipairs(events) do
                vim.api.nvim_exec_autocmds(event, { pattern = "*", modeline = false })
            end

            local definitions = vim.api.nvim_get_autocmds({ group = "lualine_refresh_probe" })
            local definition_events = {}
            for _, definition in ipairs(definitions) do
                definition_events[#definition_events + 1] = definition.event
            end
            return {
                calls = calls,
                definitions = definitions,
                definition_events = definition_events,
                errmsg = vim.v.errmsg,
                direct_call = direct_call,
                paren_require = paren_require,
                double_quote_require = double_quote_require,
            }
        ]=])

        ctx.assert.truthy("one definition per event", #result.definitions == 7,
            table.concat(result.definition_events, ","))
        ctx.assert.eq("direct callback trigger", result.direct_call.trigger, "direct")
        ctx.assert.eq("direct callback kind", result.direct_call.kind, "tabpage")
        ctx.assert.deep_eq("direct callback place", result.direct_call.place, { "statusline" })
        if ctx.backend.name == "lua_editor" then
            ctx.assert.eq("parenthesized require prefix is rejected", result.paren_require, false)
        end
        ctx.assert.eq("double-quoted require prefix is rejected", result.double_quote_require, false)
        ctx.assert.truthy("one callback per event", #result.calls == 7, result.errmsg)
        for i = 1, #result.calls do
            ctx.assert.eq("callback trigger", result.calls[i].trigger, "autocmd")
            ctx.assert.eq("callback kind", result.calls[i].kind, "tabpage")
            ctx.assert.deep_eq("callback place", result.calls[i].place, { "statusline" })
        end
    end,
}
