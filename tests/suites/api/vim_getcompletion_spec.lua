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
            vim.api.nvim_create_user_command("CCVimBufferComplete", function() end, {
                nargs = "*",
                complete = "buffer",
            })
            local callback_args
            vim.api.nvim_create_user_command("CCVimCallbackComplete", function() end, {
                nargs = "*",
                complete = function(lead, line, pos)
                    callback_args = { lead, line, pos }
                    return { "alpha", "alpine", "beta" }
                end,
            })
            vim.cmd("command! -nargs=* -complete=event CCVimEventComplete echo")
            vim.api.nvim_create_augroup("CCVimCompletionGroup", { clear = true })
            vim.api.nvim_set_hl(0, "CCVimCompletionHighlight", { fg = "#ffffff" })
            vim.api.nvim_buf_set_name(0, "/tmp/ccvim-completion-buffer.txt")
            local path_root = "/tmp/ccvim-completion-path"
            vim.fn.mkdir(path_root .. "/directory", "p")
            vim.fn.writefile({ "return true" }, path_root .. "/needle.lua")
            vim.fn.writefile({ "Alpha\talpha.lua\t1", "Beta\tbeta.lua\t1" }, path_root .. "/tags")
            vim.api.nvim_set_option_value("path", path_root, {})
            vim.api.nvim_set_option_value("cdpath", path_root, {})
            vim.api.nvim_set_option_value("tags", path_root .. "/tags", {})

            local valid_types = {
                "arglist", "augroup", "buffer", "breakpoint", "cmdline", "color", "command",
                "compiler", "diff_buffer", "dir", "dir_in_path", "environment", "event", "expression", "file",
                "file_in_path", "filetype", "function", "help", "highlight", "history", "keymap",
                "locale", "lua", "mapclear", "mapping", "menu", "messages", "option", "packadd", "runtime",
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
            local api_complete_ok = pcall(vim.api.nvim_create_user_command, "CCVimInvalidComplete", function() end, {
                nargs = "*",
                complete = "not-a-completion-kind",
            })
            local vimscript_complete_ok = pcall(vim.cmd,
                "command! -nargs=* -complete=not-a-completion-kind CCVimInvalidComplete echo")
            local custom_complete_ok = pcall(vim.cmd,
                "command! -nargs=* -complete=customlist CCVimInvalidCustomComplete echo")
            local no_args_complete_ok = pcall(vim.cmd,
                "command! -complete=file CCVimInvalidNoArgsComplete echo")

            local callback_values = vim.fn.getcompletion("CCVimCallbackComplete al", "cmdline")
            local event_values = vim.fn.getcompletion("CCVimEventComplete BufR", "cmdline")
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
                file_in_path = contains(vim.fn.getcompletion("need", "file_in_path"), "needle.lua"),
                dir_in_path = contains(vim.fn.getcompletion("dire", "dir_in_path"), "directory/"),
                tag = contains(vim.fn.getcompletion("Al", "tag"), "Alpha"),
                shellcmd = #vim.fn.getcompletion("", "shellcmd") > 0,
                builtin_buffer_cmdline = contains(
                    vim.fn.getcompletion("buffer /tmp/ccvim", "cmdline"),
                    "/tmp/ccvim-completion-buffer.txt"
                ),
                builtin_autocmd_cmdline = contains(vim.fn.getcompletion("autocmd BufR", "cmdline"), "BufReadPost"),
                autocmd_tail_cmdline = contains(
                    vim.fn.getcompletion("autocmd BufReadPost *.lua ech", "cmdline"),
                    "echo"
                ),
                builtin_sign_cmdline = contains(vim.fn.getcompletion("sign un", "cmdline"), "undefine"),
                syntax_cmdline = contains(vim.fn.getcompletion("syntax ca", "cmdline"), "case"),
                syntax_case_cmdline = contains(vim.fn.getcompletion("syntax case i", "cmdline"), "ignore"),
                highlight_cmdline = contains(vim.fn.getcompletion("highlight def", "cmdline"), "default"),
                wrapper_cmdline = contains(vim.fn.getcompletion("silent colorscheme d", "cmdline"), "default"),
                typed_user_command = contains(
                    vim.fn.getcompletion("CCVimBufferComplete /tmp/ccvim", "cmdline"),
                    "/tmp/ccvim-completion-buffer.txt"
                ),
                callback_user_command = contains(callback_values, "alpha") and contains(callback_values, "alpine")
                    and contains(callback_values, "beta"),
                callback_lead = callback_args and callback_args[1] == "al",
                callback_line = callback_args and callback_args[2] == "CCVimCallbackComplete al",
                callback_position = callback_args and callback_args[3] == #"CCVimCallbackComplete al",
                vimscript_user_command = contains(event_values, "BufReadPost"),
                invalid_error = not invalid_ok and tostring(invalid_err):find("E475", 1, true) ~= nil,
                too_many_error = not too_many_ok and tostring(too_many_err):find("E118", 1, true) ~= nil,
                pattern_error = not pattern_ok and tostring(pattern_err):find("E474", 1, true) ~= nil,
                type_error = not type_ok and tostring(type_err):find("E1174", 1, true) ~= nil,
                api_complete_validation = not api_complete_ok,
                vimscript_complete_validation = not vimscript_complete_ok,
                custom_complete_validation = not custom_complete_ok,
                complete_requires_arguments = not no_args_complete_ok,
            }
        ]])

        for name, value in pairs(result) do
            ctx.assert.eq("getcompletion " .. name, value, true)
        end
        return result
    end,
}
