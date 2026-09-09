return {
    id = "commands.help",
    description = "Ports :help tag resolution, whitespace-only :help, and bare :help! E478 behavior.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local root = Assert.temp_path(backend, "help-command", "")
        local doc_dir = root .. "/doc"
        local tags_path = doc_dir .. "/tags"
        local help_path = doc_dir .. "/vimfn.txt"
        local fuzzy_root = Assert.temp_path(backend, "help-command-fuzzy", "")
        local fuzzy_doc_dir = fuzzy_root .. "/doc"

        Assert.ensure_dir(backend, doc_dir)
        Assert.ensure_dir(backend, fuzzy_doc_dir)
        Assert.write_file(backend, tags_path, table.concat({
            "copy()\tvimfn.txt\t/*copy()*",
            "global-help-target\tvimfn.txt\t/*global-help-target*",
            "",
        }, "\n"))
        Assert.write_file(backend, help_path, table.concat({
            "header",
            "*copy()*",
            "*global-help-target*",
            "body",
            "",
        }, "\n"))
        Assert.write_file(
            backend,
            fuzzy_doc_dir .. "/tags",
            "plugin-global-help-target-link\tplugin.txt\t/*plugin-global-help-target-link*\n"
        )
        Assert.write_file(backend, fuzzy_doc_dir .. "/plugin.txt", "*plugin-global-help-target-link*\n")

        local result = Assert.eval_block(backend, "help command parity", string.format([[
            local function snapshot()
                return {
                    vim.api.nvim_buf_get_name(0),
                    vim.bo.buftype,
                    vim.api.nvim_get_current_line(),
                }
            end

            vim.cmd("set runtimepath^=" .. vim.fn.fnameescape(%q))
            vim.cmd("set runtimepath^=" .. vim.fn.fnameescape(%q))

            vim.cmd("help global-help-target")
            local globally_ranked = snapshot()
            pcall(vim.cmd, "helpclose")

            vim.cmd("help copy()")
            local plain = snapshot()
            pcall(vim.cmd, "helpclose")

            vim.cmd("help    ")
            local spaced = snapshot()
            pcall(vim.cmd, "helpclose")

            local bang_empty_ok, bang_empty_err = pcall(vim.cmd, "help!")
            local bang_spaced_ok, bang_spaced_err = pcall(vim.cmd, "help!   ")

            local bang_subject_ok, bang_subject_err = pcall(vim.cmd, "help! copy()")
            local bang_subject = snapshot()

            return {
                globally_ranked,
                plain,
                spaced,
                bang_empty_ok,
                tostring(bang_empty_err or ""),
                bang_spaced_ok,
                tostring(bang_spaced_err or ""),
                bang_subject_ok,
                tostring(bang_subject_err or ""),
                bang_subject,
            }
        ]], root, fuzzy_root))

        Assert.truthy(
            "exact help tag outranks earlier runtimepath substring",
            type(result[1][1]) == "string" and result[1][1]:find("/doc/vimfn.txt", 1, true) ~= nil,
            result[1][1]
        )
        Assert.eq("globally ranked help lands on exact tag", result[1][3], "*global-help-target*")

        Assert.truthy(
            "help file opened",
            type(result[2][1]) == "string" and result[2][1]:find("/doc/vimfn.txt", 1, true) ~= nil,
            result[2][1]
        )
        Assert.eq("help buftype set", result[2][2], "help")
        Assert.eq("cursor moved to tag line", result[2][3], "*copy()*")

        Assert.truthy(
            "spaced help opens main help file",
            type(result[3][1]) == "string" and result[3][1]:find("/doc/help.txt", 1, true) ~= nil,
            result[3][1]
        )
        Assert.eq("spaced help buftype set", result[3][2], "help")
        Assert.truthy(
            "spaced help lands on help title line",
            type(result[3][3]) == "string" and result[3][3]:find("*help.txt*", 1, true) ~= nil,
            result[3][3]
        )

        Assert.eq("bare help bang fails", result[4], false)
        Assert.top_error_code("bare help bang uses E478", result[5], "E478")

        Assert.eq("spaced bare help bang fails", result[6], false)
        Assert.top_error_code("spaced bare help bang uses E478", result[7], "E478")

        Assert.eq("help bang with subject succeeds", result[8], true)
        Assert.eq("help bang with subject has no error", result[9], "")
        Assert.truthy(
            "help bang opens tagged file",
            type(result[10][1]) == "string" and result[10][1]:find("/doc/vimfn.txt", 1, true) ~= nil,
            result[10][1]
        )
        Assert.eq("help bang buftype set", result[10][2], "help")
        Assert.eq("help bang cursor moved to tag line", result[10][3], "*copy()*")
    end,
}
