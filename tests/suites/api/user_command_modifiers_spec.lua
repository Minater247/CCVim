return {
    id = "api.user_command_modifiers",
    description = "Actual command modifiers, aliases, counts, combinations, and invocation isolation.",
    run = function(ctx)
        local A = ctx.assert
        local result = A.eval_block(ctx.backend, "command modifier callbacks", [=[
            local calls = {}
            vim.api.nvim_create_user_command('ModifierProbe', function(args)
                calls[#calls + 1] = {mods = args.mods, smods = args.smods}
            end, {bar = true})
            local cases = {
                'vertical', 'horizontal', 'leftabove', 'rightbelow', 'topleft', 'botright',
                'browse', 'confirm', 'hide', 'keepalt', 'keepjumps', 'keepmarks',
                'keeppatterns', 'lockmarks', 'noautocmd', 'noswapfile',
                'silent', 'silent!', 'unsilent', 'tab', '0tab', '1tab',
                'verbose', '0verbose', '3verbose',
                'sil! vert', 'horizontal vertical', 'vertical horizontal',
                'botright aboveleft', 'topleft belowright',
                'silent! unsilent', 'unsilent silent!', 'silent! silent',
                'keepalt silent! vertical 1tab 3verbose',
                '3verbose 0verbose',
            }
            for _, prefix in ipairs(cases) do
                vim.cmd(prefix .. ' ModifierProbe')
            end
            vim.api.nvim_create_user_command('ModifierOuter', function(args)
                calls[#calls + 1] = {mods = args.mods, smods = args.smods}
                args.smods.vertical = false
                vim.cmd('ModifierProbe')
                vim.cmd('horizontal ModifierProbe')
            end, {})
            vim.cmd('vertical ModifierOuter')
            vim.cmd('vertical execute "ModifierProbe"')
            vim.cmd('vertical ModifierProbe | ModifierProbe')
            vim.api.nvim_create_user_command('ModifierFail', function() error('probe failure') end, {})
            assert(not pcall(vim.cmd, 'vertical ModifierFail'))
            vim.cmd('ModifierProbe')
            assert(not pcall(vim.cmd, '2tab ModifierProbe'))
            vim.cmd('ModifierProbe')
            assert(not pcall(vim.cmd, 'sandbox ModifierProbe'))
            vim.cmd('ModifierProbe')
            vim.api.nvim_cmd({cmd = 'ModifierProbe', mods = {vertical = true, split = 'belowright'}}, {})
            vim.cmd.ModifierProbe({mods = {silent = true, emsg_silent = true, verbose = 0}})
            vim.api.nvim_cmd({cmd = 'ModifierProbe', mods = {tab = 0}}, {output = true})
            vim.cmd('tabnew')
            vim.cmd('2tab ModifierProbe')
            vim.cmd('tab ModifierProbe')
            vim.cmd('.tab ModifierProbe')
            vim.cmd('-tab ModifierProbe')
            vim.cmd('$tab ModifierProbe')
            vim.cmd('tabprevious')
            vim.cmd('+tab ModifierProbe')
            vim.cmd('tabclose')
            vim.api.nvim_cmd({cmd = 'ModifierProbe', mods = {emsg_silent = true}}, {})
            vim.api.nvim_cmd({cmd = 'ModifierProbe', mods = {vertical = 1, split = 'leftabove'}}, {})
            vim.api.nvim_cmd({cmd = 'ModifierProbe', mods = {tab = 999}}, {})
            vim.api.nvim_cmd({cmd = 'ModifierProbe', mods = {tab = -2}}, {})
            vim.api.nvim_cmd({cmd = 'ModifierProbe', mods = {filter = {pattern = 'foo', force = true}}}, {})
            for _, mods in ipairs({{vertical = 'bad'}, {split = 'bad'}, {filter = 'bad'}, {unknown = true}}) do
                assert(not pcall(vim.api.nvim_cmd, {cmd = 'ModifierProbe', mods = mods}, {}))
            end
            return calls
        ]=])
        local defaults = {
            browse = false, confirm = false, hide = false, keepalt = false,
            keepjumps = false, keepmarks = false, keeppatterns = false, lockmarks = false,
            noswapfile = false, sandbox = false, unsilent = false, noautocmd = false,
            silent = false, emsg_silent = false, vertical = false, horizontal = false,
            tab = -1, verbose = -1, split = "",
        }
        if ctx.backend.name ~= 'headless_nvim' then
            defaults.filter = {pattern = '', force = false}
        end
        local expected = {}
        local function add(mods, values)
            local smods = {}
            for k, v in pairs(defaults) do smods[k] = v end
            for k, v in pairs(values or {}) do smods[k] = v end
            expected[#expected + 1] = {mods = mods, smods = smods}
        end
        add('vertical', {vertical = true})
        add('horizontal', {horizontal = true})
        for _, name in ipairs({'aboveleft', 'belowright', 'topleft', 'botright'}) do add(name, {split = name}) end
        for _, name in ipairs({'browse', 'confirm', 'hide', 'keepalt', 'keepjumps', 'keepmarks',
            'keeppatterns', 'lockmarks', 'noautocmd', 'noswapfile', 'silent'}) do add(name, {[name] = true}) end
        add('silent!', {silent = true, emsg_silent = true})
        add('unsilent', {unsilent = true})
        add('tab', {tab = 1})
        add('0tab', {tab = 0})
        add('tab', {tab = 1})
        add('verbose', {verbose = 1})
        add('0verbose', {verbose = 0})
        add('3verbose', {verbose = 3})
        add('silent! vertical', {silent = true, emsg_silent = true, vertical = true})
        for _ = 1, 2 do add('vertical horizontal', {vertical = true, horizontal = true}) end
        add('aboveleft botright', {split = 'aboveleft'})
        add('belowright topleft', {split = 'belowright'})
        for _ = 1, 2 do add('unsilent silent!', {silent = true, emsg_silent = true, unsilent = true}) end
        add('silent!', {silent = true, emsg_silent = true})
        add('keepalt silent! 3verbose tab vertical', {
            keepalt = true, silent = true, emsg_silent = true, verbose = 3, tab = 1, vertical = true,
        })
        add('0verbose', {verbose = 0})
        add('vertical')
        add('')
        add('horizontal', {horizontal = true})
        add('')
        add('vertical', {vertical = true})
        for _ = 1, 4 do add('') end
        add('belowright vertical', {split = 'belowright', vertical = true})
        add('silent! 0verbose', {silent = true, emsg_silent = true, verbose = 0})
        add('0tab', {tab = 0})
        add('tab', {tab = 2})
        add('tab', {tab = 2})
        add('tab', {tab = 2})
        add('1tab', {tab = 1})
        add('tab', {tab = 2})
        add('2tab', {tab = 2})
        add('silent!', {silent = true, emsg_silent = true})
        add('aboveleft vertical', {split = 'aboveleft', vertical = true})
        add('999tab', {tab = 999})
        add('')
        local filter_values
        if ctx.backend.name ~= 'headless_nvim' then
            filter_values = {filter = {pattern = 'foo', force = true}}
        end
        add('', filter_values)
        A.deep_eq('modifier callback snapshots', result, expected)
    end,
}
