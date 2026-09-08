return {
    id = "api.user_command_count_modifiers",
    description = "Count-bearing Lua command callbacks keep counts and modifiers through text and structured calls.",
    run = function(ctx)
        local A = ctx.assert
        local result = A.eval_block(ctx.backend, "count and modifier callbacks", [=[
            local calls = {}
            vim.api.nvim_create_user_command('CountProbe', function(a)
                calls[#calls + 1] = {a.count, a.nargs, a.line1, a.line2, a.range, a.reg, a.mods}
            end, {count = true, nargs = '*'})
            vim.cmd('vertical CountProbe')
            vim.cmd('vertical 2CountProbe')
            vim.api.nvim_cmd({cmd = 'CountProbe', count = 3, mods = {horizontal = true}}, {})
            vim.api.nvim_create_user_command('DefaultCountProbe', function(a)
                calls[#calls + 1] = {a.count, a.nargs, a.line1, a.line2, a.range, a.reg, a.mods}
            end, {count = 5})
            vim.cmd('DefaultCountProbe')
            return calls
        ]=])
        A.deep_eq('counts and modifiers', result, {
            {0, '*', 1, 1, 0, '', 'vertical'},
            {2, '*', 2, 2, 1, '', 'vertical'},
            {3, '*', 1, 3, 1, '', 'horizontal'},
            {5, '0', 1, 1, 0, '', ''},
        })
    end,
}
