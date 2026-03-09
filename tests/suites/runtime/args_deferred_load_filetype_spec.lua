return {
    id = "runtime.args_deferred_load_filetype",
    description = "Ports deferred startup file loading and BufRead-driven filetype assignment through CCVim's internal Args startup pipeline; lua-editor-only because Neovim parity would require the CCVim-specific startup path.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local path = Assert.temp_path(backend, "args-deferred-cli", ".lua")
        Assert.write_file(backend, path, "print('ok')\n")

        local ok, err = pcall(function()
            local Options = backend.mock.loadModule("lib.options")
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

        if not ok then
            error(err)
        end
    end,
}
