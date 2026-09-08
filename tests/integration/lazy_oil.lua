local plugin_root = assert(os.getenv("CCVIM_PLUGIN_TEST_ROOT"),
    "Set CCVIM_PLUGIN_TEST_ROOT to a directory containing lazy.nvim and oil.nvim")

return {
    id = "integration.lazy_oil",
    description = "Real Lazy manual/sync cleanup followed by an Oil directory listing.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local backend, Assert = ctx.backend, ctx.assert
        local lfs = require("lfs")
        local function copy_plugin(source, destination)
            Assert.ensure_dir(backend, destination)
            for name in lfs.dir(source) do
                if name ~= "." and name ~= ".." and name ~= ".git" then
                    local src, dst = source .. "/" .. name, destination .. "/" .. name
                    if lfs.attributes(src, "mode") == "directory" then
                        copy_plugin(src, dst)
                    else
                        local file = assert(io.open(src, "rb"))
                        local content = file:read("*a")
                        file:close()
                        Assert.write_file(backend, dst, content)
                    end
                end
            end
        end
        copy_plugin(plugin_root .. "/oil.nvim", "/plugins/oil.nvim")
        copy_plugin(plugin_root .. "/lazy.nvim", "/plugins/lazy.nvim")
        Assert.eval_block(backend, "manual cleanup", [=[
            vim.opt.rtp:prepend('/plugins/lazy.nvim')
            local config = require('lazy.core.config')
            config.options.root = '/plugins'
            config.options.rocks = {root = '/rocks'}
            local plugin = {name = 'oil.nvim', dir = '/plugins/oil.nvim', _ = {installed = true}}
            require('lazy.manage.task.fs').clean.run({plugin = plugin})
            assert(vim.uv.fs_stat(plugin.dir) == nil, 'manual cleanup left oil behind')
            assert(plugin._.installed == false)
            return true
        ]=])
        copy_plugin(plugin_root .. "/oil.nvim", "/plugins/oil.nvim")
        Assert.eval_block(backend, "automatic sync cleanup", string.format([=[
            require('lazy').setup({}, {
                root = '/plugins', lockfile = %q, state = %q,
                pkg = {enabled = false, cache = '/pkg-cache.lua'},
                readme = {enabled = false, root = '/readme'},
                install = {missing = false}, checker = {enabled = false},
                change_detection = {enabled = false}, rocks = {enabled = false},
            })
            require('lazy.core.config').plugins['lazy.nvim']._.is_local = true
            require('lazy.manage').sync({plugins = {}, show = false, wait = true})
            assert(vim.wait(1000, function()
                return vim.uv.fs_stat('/plugins/oil.nvim') == nil
            end), 'sync left oil behind')
            return true
        ]=], backend:host_path_for_editor_path('/lazy-lock.json'),
            backend:host_path_for_editor_path('/lazy-state.json')))
        copy_plugin(plugin_root .. "/oil.nvim", "/plugins/oil.nvim")
        Assert.ensure_dir(backend, "/browse")
        Assert.write_file(backend, "/browse/example.txt", "hello")
        Assert.eval_block(backend, "Oil command and directory listing", [=[
            vim.opt.rtp:prepend('/plugins/oil.nvim')
            local Args = loadModule('lib.args')
            assert(Args.parse({[0] = 'nvim', '/browse'}))
            local startup_win
            for winid, window in pairs(windows) do
                if window.buffer.name == '/browse' then
                    startup_win = winid
                    break
                end
            end
            assert(startup_win, 'startup directory was not attached to a window')
            enterWindow(startup_win)
            assert(vim.fn.bufloaded('/browse') == 0, 'startup directory loaded before plugin setup')
            local ScriptSource = loadModule('lib.scriptsource')
            for _, path in ipairs({'ftplugin.vim', 'indent.vim', 'lua/vim/_defaults.lua'}) do
                local ok, err = ScriptSource.source_runtime(path)
                assert(ok, tostring(err))
            end
            assert(vim.fn.bufloaded('/browse') == 0, 'startup runtime loaded the directory argument')
            require('oil').setup({columns = {'type'}})
            Args.load_pending_files()
            assert(vim.wait(1000, function()
                local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                return table.concat(lines, '\n'):find('example.txt', 1, true) ~= nil
            end), 'Oil did not hijack the startup directory argument')
            assert(vim.bo.filetype == 'oil')
            assert(vim.api.nvim_buf_get_name(0):match('^oil://'), 'startup directory kept its filesystem buffer name')
            vim.cmd('Oil /browse')
            local windows_before = #vim.api.nvim_tabpage_list_wins(0)
            vim.cmd('belowright vertical Oil /browse')
            assert(#vim.api.nvim_tabpage_list_wins(0) == windows_before + 1)
            local layout = vim.fn.winlayout()
            assert(layout[1] == 'row')
            assert(layout[2][#layout[2]][2] == vim.api.nvim_get_current_win())
            local tabs_before = #vim.api.nvim_list_tabpages()
            vim.cmd('tab Oil /browse')
            assert(#vim.api.nvim_list_tabpages() == tabs_before + 1)
            assert(vim.bo.filetype == 'oil')
            return true
        ]=])
    end,
}
