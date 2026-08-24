return {
    id = "runtime.tutor_command",
    description = "Opens the bundled Tutor through its real runtime plugin and compares its buffer setup with Neovim.",

    run = function(ctx)
        local source = debug.getinfo(1, "S").source:sub(2)
        local root = source:match("^(.*)/tests/suites/runtime/") or "."
        local result = ctx.assert.eval_block(ctx.backend, "Tutor command", string.format([[
            if not _G.loadModule then
                vim.o.runtimepath = vim.fn.fnamemodify(%q, ":p") .. "," .. vim.o.runtimepath
            end
            vim.cmd("runtime plugin/tutor.vim")
            vim.cmd("Tutor")
            return {
                name = vim.api.nvim_buf_get_name(0):match("([^/]+)$"),
                first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1],
                filetype = vim.bo.filetype,
                buftype = vim.bo.buftype,
                conceallevel = vim.wo.conceallevel,
                enter_mapping = vim.fn.maparg("<CR>", "n", false, true).rhs,
            }
        ]], root .. "/runtime"))

        ctx.assert.deep_eq("Tutor buffer", result, {
            name = "vim-01-beginner.tutor",
            first_line = "# Welcome to the Neovim Tutorial",
            filetype = "tutor",
            buftype = "nowrite",
            conceallevel = 2,
            enter_mapping = ":call tutor#FollowLink(0)<cr>",
        })
    end,
}
