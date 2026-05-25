return {
    id = "runtime.netrw_plugin_compiles",
    description = "Loads the bundled netrw opt plugin through packadd and asserts its user commands are registered.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local dir_path = Assert.temp_path(backend, "netrw-edit-dir", "")

        Assert.ensure_dir(backend, dir_path)
        Assert.ensure_dir(backend, dir_path .. "/child-dir")
        Assert.write_file(backend, dir_path .. "/child-file.txt", "netrw listing probe\n")

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
            local filetype = vim.bo.filetype
            local modified = vim.bo.modified
            local modifiable = vim.bo.modifiable
            local readonly = vim.bo.readonly
            local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            vim.cmd("split")
            local quit_ok, quit_err = pcall(vim.cmd, "quit")
            return {
                filetype = filetype,
                modified = modified,
                modifiable = modifiable,
                readonly = readonly,
                quit_ok = quit_ok,
                quit_err = tostring(quit_err),
                lines = lines,
            }
        ]=], dir_path))

        Assert.eq("editing a directory opens netrw filetype", browse.filetype, "netrw")
        Assert.eq("editing a directory leaves netrw unmodified", browse.modified, false)
        Assert.eq("editing a directory leaves netrw nomodifiable", browse.modifiable, false)
        Assert.eq("editing a directory leaves netrw readonly", browse.readonly, true)
        Assert.eq("quit accepts unmodified netrw buffer", browse.quit_ok, true, browse.quit_err)
        Assert.truthy(
            "editing a directory renders netrw listing",
            table.concat(browse.lines, "\n"):find("Netrw Directory Listing", 1, true) ~= nil,
            browse.lines
        )
        Assert.truthy(
            "editing a directory lists child directory",
            table.concat(browse.lines, "\n"):find("child-dir/", 1, true) ~= nil,
            browse.lines
        )
        Assert.truthy(
            "editing a directory lists child file",
            table.concat(browse.lines, "\n"):find("child-file.txt", 1, true) ~= nil,
            browse.lines
        )

        if backend.name == "lua_editor" then
            local render_probe = Assert.eval_block(backend, "edit directory marks netrw window redraw", string.format([=[
                screen.width = 80
                screen.height = 24
                vim.cmd("packadd netrw")
                vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
                vim.cmd("edit " .. vim.fn.fnameescape(%q))
                return {
                    filetype = vim.bo.filetype,
                    needs_redraw = need_redraw,
                    window_needs_redraw = windows[curwin].need_redraw,
                }
            ]=], dir_path))

            Assert.eq("editing a directory opens netrw before render probe", render_probe.filetype, "netrw")
            Assert.eq("editing a directory schedules a screen redraw", render_probe.needs_redraw, true)
            Assert.eq("editing a directory marks current window redraw", render_probe.window_needs_redraw, true)

            local globals = backend.mock.globals()
            globals.tabpages[globals.curtp]:render()
            local cells = backend.mock.term_cells()
            local rendered = {}
            for y = 1, 12 do
                local row = cells[y] or {}
                local chars = {}
                for x = 1, 80 do
                    chars[x] = (row[x] and row[x].ch) or " "
                end
                rendered[#rendered + 1] = table.concat(chars)
            end
            local screen_text = table.concat(rendered, "\n")
            Assert.truthy(
                "editing a directory renders netrw listing into the window",
                screen_text:find("Netrw Directory Listing", 1, true) ~= nil,
                screen_text
            )
            Assert.truthy(
                "editing a directory renders child file into the window",
                screen_text:find("child-file.txt", 1, true) ~= nil,
                screen_text
            )
        end
    end,
}
