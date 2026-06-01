return {
    id = "runtime.runtime_plugin_glob",
    description = "Checks CCVim runtime plugin discovery with absolute glob patterns.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local Filesystem = backend.mock.loadModule("lib.filesystem")

        local plugin_matches = Filesystem.ExpandWildcards(
            backend.mock.globals().ccvim_path .. "/runtime/plugin/**/*.vim"
        )
        local found_netrw_wrapper = false
        for _, path in ipairs(plugin_matches) do
            if path:match("/runtime/plugin/netrwPlugin%.vim$") then
                found_netrw_wrapper = true
                break
            end
        end

        Assert.eq("absolute runtime plugin glob finds netrw wrapper", found_netrw_wrapper, true)
    end,
}
