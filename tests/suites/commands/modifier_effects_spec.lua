return {
    id = "commands.modifier_effects",
    description = "Modifiers change buffer lifetime, tab placement, marks, swap options, and sandbox permissions.",
    run = function(ctx)
        local A, b = ctx.assert, ctx.backend
        local root = A.temp_path(b, 'modifier-effects', '')
        A.ensure_dir(b, root)
        A.write_file(b, root .. '/one', 'one\ntwo\nthree\nfour\n')
        A.write_file(b, root .. '/two', 'second\n')
        local result = A.eval_block(b, 'modifier effects', string.format([=[
            local root = %q
            local function errcode(command)
                local ok, err = pcall(vim.cmd, command)
                return ok and '' or tostring(err):match('E%%d+')
            end
            vim.o.hidden = false
            vim.cmd('edit ' .. root .. '/one')
            local original = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_set_lines(0, 0, 1, false, {'changed'})
            local refused = errcode('edit ' .. root .. '/two')
            vim.cmd('hide edit ' .. root .. '/two')
            local hidden = vim.api.nvim_buf_is_loaded(original) and vim.bo[original].modified
            local restored = vim.o.hidden == false
            vim.cmd('split')
            local count = #vim.api.nvim_tabpage_list_wins(0)
            vim.cmd('hide')
            local closed = #vim.api.nvim_tabpage_list_wins(0) == count - 1
            vim.cmd('split')
            vim.cmd('split')
            local wins = vim.api.nvim_tabpage_list_wins(0)
            local target = wins[2]
            vim.api.nvim_set_current_win(wins[1])
            vim.cmd('2hide')
            local count_hide = true
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if win == target then count_hide = false end
            end
            while #vim.api.nvim_tabpage_list_wins(0) > 1 do vim.cmd('close') end
            vim.cmd('noswapfile edit ' .. root .. '/new')
            local noswap = vim.bo.swapfile == false
            vim.cmd('edit ' .. root .. '/two')
            local normal_swap = vim.bo.swapfile
            local existing = vim.api.nvim_get_current_buf()
            vim.cmd('noswapfile buffer ' .. existing)
            local existing_swap = vim.bo.swapfile
            local first = vim.api.nvim_get_current_tabpage()
            local first_buf = vim.api.nvim_get_current_buf()
            vim.cmd('0tab split')
            local ids = vim.api.nvim_list_tabpages()
            local new_first = ids[1] == vim.api.nvim_get_current_tabpage() and ids[2] == first
            local shared = vim.api.nvim_get_current_buf() == first_buf
            local tab_windows = #vim.api.nvim_tabpage_list_wins(first)
            local tab_numbers = vim.fn.tabpagenr() == 1
                and vim.fn.tabpagebuflist(2)[1] == first_buf
            local inserted_handle = vim.api.nvim_get_current_tabpage()
            vim.cmd('tabnew')
            local inserted_second = vim.fn.tabpagenr() == 2
            vim.cmd('tabprevious')
            vim.cmd('2tabclose')
            local noncurrent_close = vim.api.nvim_get_current_tabpage() == inserted_handle
                and #vim.api.nvim_list_tabpages() == 2
            vim.cmd('tabclose')
            local tabs_before = #vim.api.nvim_list_tabpages()
            vim.cmd('tab execute "split"')
            local execute_local = #vim.api.nvim_list_tabpages() == tabs_before
            vim.cmd('close')
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {'one', 'two', 'three', 'four'})
            vim.fn.setpos("'a", {0, 3, 1, 0})
            vim.cmd('lockmarks 1delete')
            local locked = vim.fn.getpos("'a")[2]
            vim.cmd('1delete')
            local adjusted = vim.fn.getpos("'a")[2]
            local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            vim.cmd('sandbox let g:modifier_safe = 6 * 7')
            local sandbox_errors = {}
            for _, cmd in ipairs({'delete', 'write', 'edit ' .. root .. '/one',
                'command SandboxCommand echo 1', 'nnoremap x y', 'set shell=unsafe',
                "call writefile(['bad'], '" .. root .. "/forbidden')", "call readfile('" .. root .. "/one')"}) do
                sandbox_errors[#sandbox_errors + 1] = errcode('sandbox ' .. cmd)
            end
            local after = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            local unchanged = table.concat(before, '\n') == table.concat(after, '\n')
            vim.cmd('sandbox set number')
            local number = vim.wo.number
            vim.api.nvim_buf_set_lines(0, 0, 1, false, {'outside sandbox'})
            local outside = vim.api.nvim_get_current_line() == 'outside sandbox'
            vim.cmd('browse let g:modifier_browse = 9')
            local browse_error = errcode('browse write ' .. root .. '/browse-output')
            return {refused, hidden, restored, closed, count_hide, noswap, normal_swap, existing_swap,
                new_first, shared, tab_windows, tab_numbers, inserted_second,
                noncurrent_close, execute_local, locked, adjusted,
                vim.g.modifier_safe, sandbox_errors, unchanged, number, outside,
                vim.g.modifier_browse, browse_error, vim.fn.filereadable(root .. '/forbidden')}
        ]=], root))
        A.deep_eq('modifier effects', result, {
            'E37', true, true, true, true, true, true, true,
            true, true, 1, true, true, true, true, 3, 2, 42,
            {'E48', 'E48', 'E48', 'E48', 'E48', 'E48', 'E48', ''},
            true, true, true, 9, b.name == 'headless_nvim' and '' or 'E338', 0,
        })
    end,
}
