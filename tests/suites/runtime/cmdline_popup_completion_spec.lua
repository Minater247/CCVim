return {
    id = "runtime.cmdline_popup_completion",
    description = "Checks command-line Tab expansion and popup behavior through native input on both editors.",

    run = function(ctx)
        local path = ctx.backend:make_temp_path("cmdline-tab", ".lua")
        local wrote, write_err = ctx.backend:write_file(path, "return true\n")
        ctx.assert.eq("create completion file", wrote, true, write_err)
        local function complete(keys, setup)
            keys = "<Esc><Esc>" .. keys
            return ctx.backend:eval_ui_block((setup or "") .. string.format([[
                vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(%q, true, false, true), "mt", false)
                if _G.loadModule then tabpages[curtp]:render() end
            ]], keys), [[
                return { vim.fn.getcmdline(), vim.fn.pumvisible() }
            ]])
        end

        local unique, unique_err = complete(":tabed<Tab>")
        local ambiguous, ambiguous_err = complete(":ech<Tab>")
        if ctx.backend.mock then
            local rendered, first = {}, false
            for _, row in ipairs(ctx.backend.mock.term_cells()) do
                local chars = {}
                for i = 1, #row do chars[i] = row[i].ch end
                local text = table.concat(chars)
                rendered[#rendered + 1] = text
                if text:match("^echo%s*$") then first = true end
            end
            ctx.assert.truthy("ambiguous matches are rendered", table.concat(rendered, "\n"):find("echoerr", 1, true))
            ctx.assert.eq("first ambiguous match is visible", first, true)
        end
        local cancelled, cancelled_err = complete(":ech<Tab><Esc>")
        local color, color_err = complete(":colorscheme <Tab><Tab>")
        local file, file_err = complete(":edit " .. path:sub(1, -3) .. "<Tab>")
        local user, user_err = complete(":CodexCom<Tab>", [[
            vim.api.nvim_create_user_command("CodexComplete", function() end, {})
        ]])
        ctx.assert.eq("unique command completion error", unique_err, nil)
        ctx.assert.eq("ambiguous command completion error", ambiguous_err, nil)
        ctx.assert.eq("cancelled command completion error", cancelled_err, nil)
        ctx.assert.eq("colorscheme completion error", color_err, nil)
        ctx.assert.eq("file command completion error", file_err, nil)
        ctx.assert.eq("user command completion error", user_err, nil)
        ctx.assert.table_eq("unique command expands without popup", unique, { "tabedit", 0 })
        ctx.assert.table_eq("ambiguous command expands with popup", ambiguous, { "echo", 1 })
        ctx.assert.table_eq("Escape cancels command completion", cancelled, { "", 0 })
        ctx.assert.table_eq("colorscheme arguments cycle", color, { "colorscheme darkblue", 1 })
        ctx.assert.table_eq("file argument completes", file, { "edit " .. path, 0 })
        ctx.assert.table_eq("user command preserves case", user, { "CodexComplete", 0 })
        ctx.backend:remove_path(path)
    end,
}
