return {
    id = "runtime.args_deferred_load_filetype",
    description = "Ports deferred startup file loading and BufRead-driven filetype assignment through CCVim's internal Args startup pipeline; lua-editor-only because Neovim parity would require the CCVim-specific startup path.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local path = Assert.temp_path(backend, "args-deferred-cli", ".lua")
        Assert.write_file(backend, path, "print('ok')\n")

        local window_ctor = setmetatable({ _next = 1 }, {
            __call = function(self, buffer)
                local id = self._next
                self._next = id + 1
                local win = {
                    winnr = id,
                    buffer = buffer,
                    opts = {},
                    scrolly = { 1, 0 },
                    scrollx = 1,
                    cursorx = 1,
                    cursory = 1,
                }
                windows[id] = win
                return win
            end,
        })

        local tab_ctor = setmetatable({ _next = 1 }, {
            __call = function(self, window)
                local id = self._next
                self._next = id + 1
                local tab = {
                    tabnr = id,
                    windows = {},
                    tree = {},
                    opts = {},
                }
                if window then
                    window.tabpagenr = id
                    tab.windows[1] = window
                end
                function tab.WinSplit(t, _, new_win)
                    new_win.tabpagenr = t.tabnr
                    t.windows[#t.windows + 1] = new_win
                    return true
                end
                tabpages[id] = tab
                return tab
            end,
        })

        local old_layout_window = package.loaded["layout.window"]
        local old_layout_tabpage = package.loaded["layout.tabpage"]
        local old_frame = package.loaded["lib.frame"]
        local old_sign = package.loaded["lib.sign"]

        package.loaded["layout.window"] = window_ctor
        package.loaded["layout.tabpage"] = tab_ctor
        package.loaded["lib.frame"] = { Equalize = function() return true end }
        package.loaded["lib.sign"] = { on_lines_changed = function() end }

        local ok, err = pcall(function()
            local Options = backend.mock.loadModule("lib.options")
            _G.options = Options
            local Autocmd = backend.mock.loadModule("lib.autocmd")
            local Args = backend.mock.loadModule("lib.args")

            Autocmd.CreateAutocommand({ "BufRead" }, { "*.lua" }, function(info)
                local buf = buffers[info.bufnr]
                Options.set("filetype", "lua", nil, nil, buf)
            end, nil, 1, false, false)

            Assert.eq("args parse ok", Args.parse({ [0] = "nvim", path }), true)

            local buf = nil
            for _, candidate in pairs(buffers) do
                if candidate.name == path then
                    buf = candidate
                    break
                end
            end
            Assert.truthy("deferred file buffer created", buf ~= nil, path)
            Assert.eq("buffer initially unloaded", buf.loaded, false)
            Assert.eq("filetype initially empty", Options.get("filetype", nil, buf), "")

            Assert.eq("load_pending_files ok", Args.load_pending_files(), true)
            Assert.eq("buffer loaded after startup load", buf.loaded, true)
            Assert.eq("filetype set from BufRead autocmd", Options.get("filetype", nil, buf), "lua")
        end)

        package.loaded["layout.window"] = old_layout_window
        package.loaded["layout.tabpage"] = old_layout_tabpage
        package.loaded["lib.frame"] = old_frame
        package.loaded["lib.sign"] = old_sign

        if not ok then
            error(err)
        end
    end,
}
