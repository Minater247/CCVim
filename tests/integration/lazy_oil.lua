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
        Assert.eval_block(backend, "Lazy runtime help resolution", [=[
            vim.opt.rtp:prepend('/plugins/lazy.nvim')
            vim.cmd('help nvim')
            local name = vim.api.nvim_buf_get_name(0)
            assert(name:match('/runtime/doc/nvim%.txt$'), ':help nvim opened ' .. name)
            vim.api.nvim_win_close(0, true)
            return true
        ]=])
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
        Assert.eval_block(backend, "Lazy floating view close", [=[
            vim.cmd('vsplit')
            vim.cmd('split')
            vim.cmd('vertical resize 20')
            vim.cmd('resize 5')
            local prior = vim.api.nvim_get_current_win()
            local layout = vim.deepcopy(vim.fn.winlayout())
            local function dimensions(value)
                local result = {}
                local function collect(node)
                    if node[1] == 'leaf' then
                        result[node[2]] = {
                            vim.api.nvim_win_get_width(node[2]),
                            vim.api.nvim_win_get_height(node[2]),
                        }
                    else
                        for _, child in ipairs(node[2]) do collect(child) end
                    end
                end
                collect(value)
                return result
            end
            local sizes = dimensions(layout)
            local view_module = require('lazy.view')
            view_module.show()
            assert(view_module.visible(), 'Lazy floating view did not open')
            local view = view_module.view
            local content = view.win
            local backdrop = view.backdrop_win
            assert(vim.api.nvim_get_current_win() == content, 'Lazy content float was not current')
            assert(vim.deep_equal(vim.fn.winlayout(), layout), 'opening Lazy changed the tiled layout')
            assert(vim.deep_equal(dimensions(layout), sizes), 'opening Lazy changed tiled dimensions')
            vim.api.nvim_win_close(content, true)
            assert(vim.wait(1000, function()
                return not vim.api.nvim_win_is_valid(content)
                    and (not backdrop or not vim.api.nvim_win_is_valid(backdrop))
            end), 'Lazy floats did not close')
            assert(vim.api.nvim_get_current_win() == prior, 'closing Lazy did not restore the prior window')
            assert(vim.deep_equal(vim.fn.winlayout(), layout), 'closing Lazy changed the tiled layout')
            assert(vim.deep_equal(dimensions(layout), sizes), 'closing Lazy changed tiled dimensions')

            view_module.show()
            view = view_module.view
            content = view.win
            backdrop = view.backdrop_win
            view:close()
            assert(vim.wait(1000, function()
                return not vim.api.nvim_win_is_valid(content)
                    and (not backdrop or not vim.api.nvim_win_is_valid(backdrop))
            end), 'Lazy scheduled close left a float open')
            assert(vim.api.nvim_get_current_win() == prior, 'scheduled close did not restore the prior window')
            assert(vim.deep_equal(vim.fn.winlayout(), layout), 'scheduled close changed the tiled layout')
            assert(vim.deep_equal(dimensions(layout), sizes), 'scheduled close changed tiled dimensions')
            return true
        ]=])
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
