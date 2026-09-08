return {
    id = "runtime.args_directory_plugin_startup",
    description = "Keeps an unloaded startup directory buffer visible to file explorer setup before argument loading.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local directory = Assert.temp_path(backend, "startup-directory", "")
        Assert.ensure_dir(backend, directory)
        Assert.write_file(backend, directory .. "/entry.txt", "entry\n")

        local result = Assert.eval_block(backend, "startup directory plugin handoff", string.format([=[
            local Args = loadModule("lib.args")
            local bufadd = 0
            vim.api.nvim_create_autocmd("BufAdd", {
                callback = function()
                    bufadd = bufadd + 1
                end,
            })

            assert(Args.parse({ [0] = "nvim", %q }))
            local argument_buffer
            local argument_window
            for bufnr, buffer in pairs(buffers) do
                if buffer.name == %q then
                    argument_buffer = buffer
                    for winid, window in pairs(windows) do
                        if window.buffer == buffer then
                            argument_window = winid
                            break
                        end
                    end
                    break
                end
            end
            assert(argument_buffer and argument_window)
            enterWindow(argument_window)

            local visible_name = vim.api.nvim_buf_get_name(0)
            local unloaded_before_setup = vim.fn.bufloaded(argument_buffer.bufnr) == 0
            local ScriptSource = loadModule("lib.scriptsource")
            for _, path in ipairs({ "ftplugin.vim", "indent.vim", "lua/vim/_defaults.lua" }) do
                local ok, err = ScriptSource.source_runtime(path)
                assert(ok, tostring(err))
            end
            vim.cmd("call exists('g:loaded_matchit')")
            local unloaded_after_runtime = vim.fn.bufloaded(argument_buffer.bufnr) == 0
            local readcmd = 0
            vim.api.nvim_create_autocmd("BufReadCmd", {
                pattern = "oil://*",
                callback = function(params)
                    readcmd = readcmd + 1
                    vim.api.nvim_buf_set_lines(params.buf, 0, -1, false, { "entry.txt" })
                    vim.bo[params.buf].filetype = "oil"
                end,
            })
            if vim.fn.isdirectory(visible_name) == 1 then
                vim.api.nvim_buf_set_name(0, "oil:///startup-directory/")
            end

            Args.load_pending_files()
            return {
                visible_name = visible_name,
                unloaded_before_setup = unloaded_before_setup,
                unloaded_after_runtime = unloaded_after_runtime,
                bufadd = bufadd,
                readcmd = readcmd,
                final_name = vim.api.nvim_buf_get_name(0),
                filetype = vim.bo.filetype,
                lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
            }
        ]=], directory, directory))

        Assert.eq("startup plugin sees directory argument", result.visible_name, directory)
        Assert.eq("directory argument remains unloaded during plugin setup", result.unloaded_before_setup, true)
        Assert.eq("startup runtime does not load the directory argument", result.unloaded_after_runtime, true)
        Assert.eq("startup argument creation does not fire BufAdd", result.bufadd, 0)
        Assert.eq("renamed startup buffer dispatches BufReadCmd", result.readcmd, 1)
        Assert.eq("plugin keeps renamed startup buffer current", result.final_name, "oil:///startup-directory/")
        Assert.eq("plugin assigns filetype during deferred read", result.filetype, "oil")
        Assert.deep_eq("plugin supplies startup directory contents", result.lines, { "entry.txt" })
    end,
}
