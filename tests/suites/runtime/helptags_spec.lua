return {
    id = "runtime.helptags",
    description = "Generates sorted English and translated help tags recursively with native escaping"
        .. " and duplicate checks.",
    supports = { lua_editor = true, headless_nvim = true },

    run = function(ctx)
        local Assert = ctx.assert
        local root = Assert.temp_path(ctx.backend, "helptags", "")
        Assert.ensure_dir(ctx.backend, root .. "/sub")
        Assert.write_file(ctx.backend, root .. "/one.txt", table.concat({
            "*z-tag* z", "*a-tag* a", "*slash/tag* s", "*back\\tag* b",
            "**not-a-tag**", "1. *image*: markdown", "",
        }, "\n"))
        Assert.write_file(ctx.backend, root .. "/sub/two.txt", "*sub-tag* x\n")
        Assert.write_file(ctx.backend, root .. "/uno.itx", "*italiano* x\n")

        local result = Assert.eval_block(ctx.backend, "helptags generation", string.format([[
            vim.cmd("helptags ++t %s")
            return {
                table.concat(vim.fn.readfile(%q), "\n"),
                table.concat(vim.fn.readfile(%q), "\n"),
            }
        ]], root, root .. "/tags", root .. "/tags-it"))
        Assert.table_eq("generated help tags", result, {
            table.concat({
                "a-tag\tone.txt\t/*a-tag*",
                "back\\tag\tone.txt\t/*back\\\\tag*",
                "help-tags\ttags\t1",
                "slash/tag\tone.txt\t/*slash\\/tag*",
                "sub-tag\tsub/two.txt\t/*sub-tag*",
                "z-tag\tone.txt\t/*z-tag*",
            }, "\n"),
            "help-tags\ttags-it\t1\nitaliano\tuno.itx\t/*italiano*",
        })

        local duplicate = Assert.temp_path(ctx.backend, "helptags-duplicate", "")
        Assert.ensure_dir(ctx.backend, duplicate)
        Assert.write_file(ctx.backend, duplicate .. "/one.txt", "*same*\n")
        Assert.write_file(ctx.backend, duplicate .. "/two.txt", "*same*\n")
        Assert.expect_error_block(ctx.backend, "duplicate help tag", string.format(
            "vim.cmd(%q)", "helptags " .. duplicate
        ), "E154")

        local missing = Assert.temp_path(ctx.backend, "helptags-missing", "")
        Assert.expect_error_block(ctx.backend, "missing help directory", string.format(
            "vim.cmd(%q)", "helptags " .. missing
        ), "E150")
    end,
}
