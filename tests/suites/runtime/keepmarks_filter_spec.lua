return {
    id = 'runtime.keepmarks_filter',
    description = 'Real shell filters preserve or delete marks according to keepmarks and cpoptions R.',
    run = function(ctx)
        local A, b = ctx.assert, ctx.backend
        if b.name == 'lua_editor' then
            local Native = assert(loadfile('lib/backend/native.lua'))()
            b.mock.loadModule('lib.backend').current().system = Native.system
        end
        local result = A.eval_block(b, 'filter marks', [=[
            local function filter(prefix, command)
                vim.api.nvim_buf_set_lines(0, 0, -1, false, {'one','two','three','four'})
                vim.fn.setpos("'a", {0, 2, 1, 0})
                vim.fn.setpos("'b", {0, 4, 1, 0})
                vim.cmd(prefix .. '1,3!' .. command)
                return {vim.fn.getpos("'a")[2], vim.fn.getpos("'b")[2],
                    vim.api.nvim_buf_get_lines(0, 0, -1, false)}
            end
            vim.o.cpoptions = vim.o.cpoptions .. 'R'
            local normal = filter('', 'cat')
            local kept = filter('keepmarks ', 'cat')
            local shortened = filter('keepmarks ', 'head -n 1')
            vim.o.cpoptions = vim.o.cpoptions:gsub('R', '')
            local implicit = filter('', 'cat')
            return {normal, kept, shortened, implicit}
        ]=])
        A.deep_eq('filter mark results', result, {
            {0,4,{'one','two','three','four'}},
            {2,4,{'one','two','three','four'}},
            {0,2,{'one','four'}},
            {2,4,{'one','two','three','four'}},
        })
    end,
}
