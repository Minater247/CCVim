return {
    id = 'runtime.confirm_modifier',
    description = 'Confirmation decisions drive real buffer saves, discards, cancellations, and overwrite checks.',
    supports = {headless_nvim = false},
    run = function(ctx)
        local A, b = ctx.assert, ctx.backend
        local root = A.temp_path(b, 'confirm', '')
        A.ensure_dir(b, root)
        A.write_file(b, root .. '/one', 'original\n')
        A.write_file(b, root .. '/two', 'second\n')
        local ExMsg = b.mock.loadModule('lib.excmd.exmsg')
        local globals = b.mock.globals()
        local function screen_text()
            local rows = {}
            for y, cells in ipairs(b.mock.term_cells()) do
                local chars = {}
                for x, cell in ipairs(cells) do chars[x] = cell.ch end
                rows[y] = table.concat(chars)
            end
            return table.concat(rows, '\n')
        end
        ExMsg.echomsg('test')
        ExMsg.echon('')
        ExMsg.BeginQuestion('Overwrite existing file "/test.confirm"?\n(Y)es, [N]o: ')
        globals.tabpages[globals.curtp]:render()
        A.truthy('pending message remains visible', screen_text():find('test', 1, true) ~= nil)
        A.truthy('question draws', screen_text():find('Overwrite existing file', 1, true) ~= nil)
        A.eq('question newline is not rendered as control text', screen_text():find('^J', 1, true), nil)
        globals.tabpages[globals.curtp]:render()
        A.truthy('pending message survives redraw', screen_text():find('test', 1, true) ~= nil)
        A.truthy('question survives redraw', screen_text():find('(Y)es, [N]o:', 1, true) ~= nil)
        ExMsg.EndQuestion()
        globals.tabpages[globals.curtp]:render()
        A.eq('question clears', screen_text():find('Overwrite existing file', 1, true), nil)
        A.eval_block(b, 'prepare modified buffer', string.format([=[
            vim.o.hidden = false
            vim.cmd('edit ' .. %q .. '/one')
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {'changed'})
            return true
        ]=], root))
        b.mock.queueEvent('char', 'c')
        local cancel = A.eval_block(b, 'cancel edit', string.format([=[
            local ok = pcall(vim.cmd, 'confirm edit ' .. %q .. '/two')
            return {ok, vim.api.nvim_get_current_line(), vim.bo.modified}
        ]=], root))
        A.deep_eq('cancel retains changes', cancel, {false, 'changed', true})
        b.mock.queueEvent('char', 'y')
        local saved = A.eval_block(b, 'save before edit', string.format([=[
            vim.cmd('confirm edit ' .. %q .. '/two')
            return vim.fn.readfile(%q .. '/one')
        ]=], root, root))
        A.deep_eq('save persisted', saved, {'changed'})
        A.eval_block(b, 'prepare overwrite', [=[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {'overwrite'})
            return true
        ]=])
        local backend_impl = b.mock.loadModule('lib.backend').current()
        local original_pull = backend_impl.pull_event
        local tabpage = globals.tabpages[globals.curtp]
        local original_render = tabpage.render
        local render_count = 0
        tabpage.render = function(self, ...)
            render_count = render_count + 1
            return original_render(self, ...)
        end
        local prompt_screen
        local pull_count = 0
        backend_impl.pull_event = function()
            pull_count = pull_count + 1
            if pull_count == 1 then return 'timer', -1 end
            prompt_screen = screen_text()
            return 'char', 'n'
        end
        local ran, rejected = pcall(A.eval_block, b, 'reject overwrite with pending messages', string.format([=[
            vim.v.errmsg = ''
            local ok = pcall(vim.cmd, 'echom "test" | echon | confirm write ' .. %q .. '/one')
            return {ok, vim.v.errmsg, vim.fn.readfile(%q .. '/one')[1]}
        ]=], root, root))
        backend_impl.pull_event = original_pull
        tabpage.render = original_render
        if not ran then error(rejected) end
        A.truthy('real prompt retains pending message', prompt_screen:find('test', 1, true) ~= nil)
        A.truthy('real prompt draws question', prompt_screen:find('Overwrite existing file', 1, true) ~= nil)
        A.truthy('real prompt draws choices', prompt_screen:find('(Y)es, [N]o:', 1, true) ~= nil)
        A.eq('real prompt suppresses hit-enter prompt', prompt_screen:find('Press ENTER', 1, true), nil)
        A.eq('timer does not repaint editor behind prompt', render_count, 1)
        A.deep_eq('reject quietly preserves target', rejected, {true, '', 'changed'})
        b.mock.queueEvent('char', 'y')
        local overwrite = A.eval_block(b, 'accept overwrite', string.format([=[
            vim.cmd('confirm write ' .. %q .. '/one')
            return vim.fn.readfile(%q .. '/one')
        ]=], root, root))
        A.deep_eq('overwrite persisted', overwrite, {'overwrite'})
        A.eval_block(b, 'prepare readonly write', [=[
            vim.bo.readonly = true
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {'readonly confirmation'})
            return true
        ]=])
        b.mock.queueEvent('char', 'y')
        local readonly = A.eval_block(b, 'confirm readonly', string.format([=[
            vim.cmd('confirm write')
            return vim.fn.readfile(%q .. '/two')
        ]=], root))
        A.deep_eq('readonly saved', readonly, {'readonly confirmation'})
        local readonly_copy = A.eval_block(b, 'readonly write to new path', string.format([=[
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {'readonly copy'})
            vim.cmd('confirm write ' .. %q .. '/readonly-copy')
            return vim.fn.readfile(%q .. '/readonly-copy')
        ]=], root, root))
        A.deep_eq('readonly does not block another path', readonly_copy, {'readonly copy'})
        A.eval_block(b, 'prepare discard', [=[
            vim.bo.readonly = false
            vim.api.nvim_buf_set_lines(0, 0, -1, false, {'discarded'})
            return true
        ]=])
        b.mock.queueEvent('char', 'n')
        local discard = A.eval_block(b, 'discard before edit', string.format([=[
            vim.cmd('confirm edit ' .. %q .. '/one')
            return {vim.api.nvim_get_current_line(), vim.fn.readfile(%q .. '/two')[1]}
        ]=], root, root))
        A.deep_eq('discard does not save', discard, {'overwrite', 'readonly confirmation'})
    end,
}
