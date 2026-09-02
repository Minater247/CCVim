return {
    id = "api.vim_getcompletion",
    description = "Covers getcompletion() sources, matching, command-line context, and errors.",
    supports = { lua_editor = true, headless_nvim = true, parity = true },

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "getcompletion scenarios", [[
            local function contains(values, wanted)
                for i = 1, #values do if values[i] == wanted then return true end end
                return false
            end

            vim.api.nvim_create_user_command("CCVimCompletionProbe", function() end, {})
            vim.api.nvim_create_augroup("CCVimCompletionGroup", { clear = true })
            vim.api.nvim_set_hl(0, "CCVimCompletionHighlight", { fg = "#ffffff" })
            vim.api.nvim_buf_set_name(0, "/tmp/ccvim-completion-buffer.txt")

            local valid_types = {
                "arglist", "augroup", "buffer", "breakpoint", "cmdline", "color", "command",
                "compiler", "diff_buffer", "dir", "environment", "event", "expression", "file",
                "file_in_path", "filetype", "function", "help", "highlight", "history", "keymap",
                "locale", "mapclear", "mapping", "menu", "messages", "option", "packadd", "runtime",
                "scriptnames", "shellcmd", "shellcmdline", "sign", "syntax", "syntime", "user", "var",
            }
            local all_valid = true
            for i = 1, #valid_types do
                local ok, value = pcall(vim.fn.getcompletion, "", valid_types[i])
                if not ok or type(value) ~= "table" then all_valid = false end
            end

            local invalid_ok, invalid_err = pcall(vim.fn.getcompletion, "", "not-a-completion-kind")
            local too_many_ok, too_many_err = pcall(vim.fn.getcompletion, "", "command", 0, 1)
            local pattern_ok, pattern_err = pcall(vim.fn.getcompletion, {}, "command")
            local type_ok, type_err = pcall(vim.fn.getcompletion, "", {})

            return {
                all_valid = all_valid,
                user_command = contains(vim.fn.getcompletion("CCVim*Probe", "command"), "CCVimCompletionProbe"),
                cmdline = contains(vim.fn.getcompletion("colo d", "cmdline"), "default"),
                color = contains(vim.fn.getcompletion("def*", "color"), "default"),
                event = contains(vim.fn.getcompletion("BufR", "event"), "BufReadPost"),
                augroup = contains(vim.fn.getcompletion("CCVim", "augroup"), "CCVimCompletionGroup"),
                builtin_function = contains(vim.fn.getcompletion("getcomp", "function"), "getcompletion("),
                option = contains(vim.fn.getcompletion("wildignore", "option"), "wildignorecase"),
                highlight = contains(vim.fn.getcompletion("CCVim", "highlight"), "CCVimCompletionHighlight"),
                environment = contains(vim.fn.getcompletion("HO", "environment"), "HOME"),
                buffer = contains(vim.fn.getcompletion("/tmp/ccvim", "buffer"), "/tmp/ccvim-completion-buffer.txt"),
                sign = contains(vim.fn.getcompletion("un", "sign"), "undefine"),
                mapping = contains(vim.fn.getcompletion("<s", "mapping"), "<silent>"),
                packadd = contains(vim.fn.getcompletion("net", "packadd"), "netrw"),
                invalid_error = not invalid_ok and tostring(invalid_err):find("E475", 1, true) ~= nil,
                too_many_error = not too_many_ok and tostring(too_many_err):find("E118", 1, true) ~= nil,
                pattern_error = not pattern_ok and tostring(pattern_err):find("E474", 1, true) ~= nil,
                type_error = not type_ok and tostring(type_err):find("E1174", 1, true) ~= nil,
            }
        ]])

        for name, value in pairs(result) do
            ctx.assert.eq("getcompletion " .. name, value, true)
        end
        return result
    end,
}
