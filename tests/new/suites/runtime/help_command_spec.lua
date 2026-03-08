return {
    id = "runtime.help_command",
    description = "Ports :help tag resolution and help buffer setup through a generated runtimepath.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local root = Assert.temp_path(backend, "help-runtime", "")
        local doc_dir = root .. "/doc"
        local tags_path = doc_dir .. "/tags"
        local help_path = doc_dir .. "/vimfn.txt"

        Assert.ensure_dir(backend, doc_dir)
        Assert.write_file(backend, tags_path, "copy()\tvimfn.txt\t/*copy()*\n")
        Assert.write_file(backend, help_path, table.concat({
            "header",
            "*copy()*",
            "body",
            "",
        }, "\n"))

        local result = Assert.eval_block(backend, "help command jump", string.format([[
            vim.cmd("set runtimepath^=" .. vim.fn.fnameescape(%q))
            vim.cmd("help copy()")

            return {
                vim.api.nvim_buf_get_name(0),
                vim.bo.buftype,
                vim.api.nvim_get_current_line(),
            }
        ]], root))

        Assert.truthy(
            "help file opened",
            type(result[1]) == "string" and result[1]:find("/doc/vimfn.txt", 1, true) ~= nil,
            result[1]
        )
        Assert.eq("help buftype set", result[2], "help")
        Assert.eq("cursor moved to tag line", result[3], "*copy()*")

        Assert.remove_path(backend, tags_path)
        Assert.remove_path(backend, help_path)
        Assert.remove_path(backend, doc_dir)
        Assert.remove_path(backend, root)
    end,
}
