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
            local setup = {
                name = vim.api.nvim_buf_get_name(0):match("([^/]+)$"),
                first_line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1],
                filetype = vim.bo.filetype,
                buftype = vim.bo.buftype,
                conceallevel = vim.wo.conceallevel,
                enter_mapping = vim.fn.maparg("<CR>", "n", false, true).rhs,
            }
            local ns = vim.api.nvim_create_namespace("nvim.tutor.mark")
            vim.fn.cursor(vim.fn.search("^2)  Mud is fun,$"), 1)
            vim.cmd("normal! dd")
            local after_first_delete = vim.api.nvim_get_current_line()
            vim.cmd("normal! j2dd")

            local out = {}
            for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })) do
                local original = vim.b.tutor_extmarks[tostring(mark[1])]
                if original and tonumber(original) >= 309 and tonumber(original) <= 315 then
                    out[#out + 1] = { tonumber(original), mark[2], mark[4].invalid == true }
                end
            end
            table.sort(out, function(a, b) return a[1] < b[1] end)
            return { setup, out, after_first_delete }
        ]], root .. "/runtime"))

        ctx.assert.deep_eq("Tutor buffer", result[1], {
            name = "vim-01-beginner.tutor",
            first_line = "# Welcome to the Neovim Tutorial",
            filetype = "tutor",
            buftype = "nowrite",
            conceallevel = 2,
            enter_mapping = ":call tutor#FollowLink(0)<cr>",
        })

        ctx.assert.deep_eq("Lesson 2.6 marks remain aligned", result[2], {
            { 309, 308, false },
            { 310, 309, true },
            { 311, 309, false },
            { 312, 310, true },
            { 313, 310, true },
            { 314, 310, false },
            { 315, 311, false },
        })
        ctx.assert.eq("dd remains on the replacement line", result[3], "3)  Violets are blue,")
    end,
}
