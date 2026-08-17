return {
    id = "runtime.filetype_write_detection",
    description = "Checks that writing an unnamed buffer detects its new extension and that .yml loads YAML syntax.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local lua_path = Assert.temp_path(backend, "filetype-write-detection", ".lua")
        local yaml_write_path = Assert.temp_path(backend, "filetype-write-yaml", ".yml")
        local source_path = Assert.temp_path(backend, "filetype-write-source", ".vim")
        local alternate_path = Assert.temp_path(backend, "filetype-write-alternate", ".lua")
        local yml_path = Assert.temp_path(backend, "filetype-yml-detection", ".yml")
        Assert.write_file(backend, yml_path, "enabled: true\n")

        local result = Assert.eval_block(backend, "filetype detection after write and for .yml", string.format([[
            vim.cmd("filetype on")
            vim.cmd("syntax on")

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = true" })
            vim.cmd("write! " .. vim.fn.fnameescape(%q))
            local written_lua = { vim.bo.filetype, vim.bo.syntax }

            vim.cmd("enew!")
            vim.cmd("file " .. vim.fn.fnameescape(%q))
            vim.bo.filetype = "vim"
            vim.bo.syntax = "vim"
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "let value = true" })
            vim.cmd("write! " .. vim.fn.fnameescape(%q))
            local alternate_write = {
                vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"),
                vim.bo.filetype,
                vim.bo.syntax,
            }

            vim.cmd("edit " .. vim.fn.fnameescape(%q))
            local opened_yml = {
                vim.bo.filetype,
                vim.bo.syntax,
                vim.fn.synIDattr(vim.fn.synID(1, 1, 0), "name"),
                vim.fn.synIDattr(vim.fn.synID(1, 10, 0), "name"),
            }

            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "---", "# This is a test." })
            vim.cmd("write! " .. vim.fn.fnameescape(%q))
            local delfunction_ok = pcall(vim.cmd, "delfunction! __ccvim_yaml_cleanup_probe")
            local written_yml = {
                vim.bo.filetype,
                vim.bo.syntax,
                delfunction_ok,
                not vim.fn.execute("messages"):find("E492", 1, true),
            }

            return { written_lua, alternate_write, opened_yml, written_yml }
        ]], lua_path, source_path, alternate_path, yml_path, yaml_write_path))

        Assert.table_eq("writing an unnamed .lua buffer detects Lua", result[1], { "lua", "lua" })
        Assert.table_eq("writing an alternate file preserves the current buffer name and syntax", result[2], {
            source_path:match("([^/]+)$"),
            "vim",
            "vim",
        })
        Assert.table_eq(
            "opening .yml detects and loads YAML",
            result[3],
            { "yaml", "yaml", "yamlBlockMappingKey", "yamlBool" }
        )
        Assert.table_eq("writing a YAML document loads syntax without E492", result[4], {
            "yaml",
            "yaml",
            true,
            true,
        })
    end,
}
