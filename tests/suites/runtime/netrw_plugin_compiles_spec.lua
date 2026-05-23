return {
    id = "runtime.netrw_plugin_compiles",
    description = "Loads the bundled netrw opt plugin through packadd and asserts its user commands are registered.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local dir_path = Assert.temp_path(backend, "netrw-edit-dir", "")

        Assert.ensure_dir(backend, dir_path)

        local result = Assert.eval_block(backend, "packadd netrw", [[
            vim.cmd("packadd netrw")
            return {
                vim.fn.exists(":Explore"),
                vim.fn.exists(":Sexplore"),
                vim.fn.exists(":Lexplore"),
                vim.fn.exists(":Nread"),
            }
        ]])

        Assert.table_eq("netrw plugin commands registered", result, { 2, 2, 2, 2 })

        local browse = Assert.eval_block(backend, "edit directory with netrw", string.format([=[
            vim.cmd("packadd netrw")
            vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
            vim.cmd("edit " .. vim.fn.fnameescape(%q))
            return {
                filetype = vim.bo.filetype,
                first_lines = vim.api.nvim_buf_get_lines(0, 0, 6, false),
            }
        ]=], dir_path))

        Assert.eq("editing a directory opens netrw filetype", browse.filetype, "netrw")
        Assert.truthy(
            "editing a directory renders netrw listing",
            table.concat(browse.first_lines, "\n"):find("Netrw Directory Listing", 1, true) ~= nil,
            browse.first_lines
        )
    end,
}
