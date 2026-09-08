local plugin_root = assert(os.getenv("CCVIM_PLUGIN_TEST_ROOT"),
    "Set CCVIM_PLUGIN_TEST_ROOT to a directory containing lualine.nvim")

return {
    id = "integration.lualine_events",
    description = "Real Lualine refresh through its default cursor movement autocommand.",
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

        copy_plugin(plugin_root .. "/lualine.nvim", "/plugins/lualine.nvim")
        Assert.eval_block(backend, "Lualine CursorMoved refresh", [=[
            vim.opt.rtp:prepend('/plugins/lualine.nvim')
            vim.g.lualine_event_value = 'before'
            require('lualine').setup({
                options = {
                    refresh = {
                        statusline = 10000,
                        tabline = 10000,
                        winbar = 10000,
                        refresh_time = 16,
                    },
                },
                sections = {
                    lualine_a = {function() return vim.g.lualine_event_value end},
                    lualine_b = {},
                    lualine_c = {},
                    lualine_x = {},
                    lualine_y = {},
                    lualine_z = {},
                },
            })
            assert(vim.wait(500, function()
                return vim.o.statusline:find('before', 1, true) ~= nil
            end), 'Lualine did not complete its initial refresh')

            vim.api.nvim_buf_set_lines(0, 0, -1, false, {'one', 'two'})
            vim.g.lualine_event_value = 'after'
            vim.api.nvim_win_set_cursor(0, {2, 0})
            assert(vim.wait(250, function()
                return vim.o.statusline:find('after', 1, true) ~= nil
            end), 'CursorMoved did not refresh Lualine before its periodic timer')
            return true
        ]=])
    end,
}
