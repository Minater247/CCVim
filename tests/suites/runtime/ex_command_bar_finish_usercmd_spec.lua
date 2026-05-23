return {
    id = "runtime.ex_command_bar_finish_usercmd",
    description = "Ports sourced Vimscript behavior for quoted bars, finish, silent, syntax pipes, and user-command expansion.", -- luacheck: ignore 631
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local quoted_bar = Assert.temp_path(backend, "quoted-bar-runtime", ".vim")
        local finish_script = Assert.temp_path(backend, "finish-runtime", ".vim")
        local silent_script = Assert.temp_path(backend, "silent-runtime", ".vim")
        local case_cmp_script = Assert.temp_path(backend, "case-cmp-runtime", ".vim")
        local syn_script = Assert.temp_path(backend, "syn-quoted-bar-runtime", ".vim")
        local command_bar_script = Assert.temp_path(backend, "command-bar-body-runtime", ".vim")
        local keepj_script = Assert.temp_path(backend, "keepj-cmd-runtime", ".vim")
        local uargs_script = Assert.temp_path(backend, "uargs-cmd-runtime", ".vim")
        local nmap_bar_script = Assert.temp_path(backend, "nmap-bar-runtime", ".vim")
        local execute_double_quote_script = Assert.temp_path(backend, "execute-double-quote-bar-runtime", ".vim")

        Assert.write_file(backend, quoted_bar, table.concat({
            "let s_skip = '1'",
            "execute 'if ' . s_skip . ' | let g:quoted_bar_ok = 42 | endif'",
            "",
        }, "\n"))
        Assert.write_file(backend, finish_script, table.concat({
            "let g:finish_seen = 1",
            "finish",
            "let g:finish_seen = 2",
            "",
        }, "\n"))
        Assert.write_file(backend, silent_script, table.concat({
            "silent let g:silent_seen = 7",
            "",
        }, "\n"))
        Assert.write_file(backend, case_cmp_script, table.concat({
            "set buftype=nofile",
            "if &buftype ==# 'nofile'",
            "  let g:case_cmp_term_ok = 1",
            "endif",
            "",
        }, "\n"))
        Assert.write_file(backend, syn_script, table.concat({
            [[syn match luaError "\<\%(end\|else\|elseif\|then\|until\|in\)\>"]],
            "",
        }, "\n"))
        Assert.write_file(backend, command_bar_script, table.concat({
            [[com! Rexplore if exists("g:rexlocal")|let g:rex_branch='yes'|else|let g:rex_branch='no'|endif]],
            "let g:rexlocal = 1",
            "Rexplore",
            "unlet g:rexlocal",
            "Rexplore",
            "",
        }, "\n"))
        Assert.write_file(backend, keepj_script, table.concat({
            "command! -nargs=* KeepjCmd keepj <args>",
            "let g:keepj_cmd_probe = 0",
            "KeepjCmd let g:keepj_cmd_probe = 9",
            "",
        }, "\n"))
        Assert.write_file(backend, uargs_script, table.concat({
            [=[
command! -nargs=* UArgs let g:uargs_raw = "<args>" | let g:uargs_q = <q-args> | let g:uargs_f = [<f-args>]
]=],
            "UArgs one two",
            "",
        }, "\n"))
        Assert.write_file(backend, nmap_bar_script, table.concat({
            "if 1|nmap <buffer> <silent> <nowait> - <Plug>NetrwBrowseUpDir|endif",
            "let g:nmap_bar_split = 1",
            "",
        }, "\n"))
        Assert.write_file(backend, execute_double_quote_script, table.concat({
            [[execute "if 1 | let g:execute_double_quote_bar_ok = 11 | endif"]],
            "",
        }, "\n"))

        local result = Assert.eval_block(backend, "ex command bar finish usercmd scenarios", string.format([=[
            local quoted_bar = %q
            local finish_script = %q
            local silent_script = %q
            local case_cmp_script = %q
            local syn_script = %q
            local command_bar_script = %q
            local keepj_script = %q
            local uargs_script = %q
            local nmap_bar_script = %q
            local execute_double_quote_script = %q

            local function source(path)
                vim.cmd("source " .. vim.fn.fnameescape(path))
            end

            source(quoted_bar)
            source(finish_script)
            source(silent_script)

            vim.cmd("enew!")
            source(case_cmp_script)

            vim.cmd("syntax clear")
            source(syn_script)
            local syntax_list = vim.fn.execute("syntax list luaError")

            source(command_bar_script)
            source(keepj_script)
            source(uargs_script)

            vim.cmd("enew!")
            source(nmap_bar_script)
            source(execute_double_quote_script)

            return {
                vim.g.quoted_bar_ok,
                vim.g.finish_seen,
                vim.g.silent_seen,
                vim.g.case_cmp_term_ok,
                syntax_list,
                vim.g.rex_branch,
                vim.g.keepj_cmd_probe,
                vim.g.uargs_raw,
                vim.g.uargs_q,
                vim.g.uargs_f,
                vim.g.nmap_bar_split,
                vim.fn.maparg("-", "n"),
                vim.g.execute_double_quote_bar_ok,
            }
        ]=],
            quoted_bar,
            finish_script,
            silent_script,
            case_cmp_script,
            syn_script,
            command_bar_script,
            keepj_script,
            uargs_script,
            nmap_bar_script,
            execute_double_quote_script
        ))

        Assert.eq("quoted execute with bars runs", result[1], 42)
        Assert.eq("finish stops script", result[2], 1)
        Assert.eq("silent command still executes", result[3], 7)
        Assert.eq("case-sensitive option comparison branch", result[4], 1)
        Assert.truthy(
            "syntax pattern with pipes survives source",
            type(result[5]) == "string" and result[5]:find("luaError", 1, true) ~= nil,
            result[5]
        )
        Assert.eq("command body with bars ran else branch on second call", result[6], "no")
        Assert.eq("user command keepj body executes", result[7], 9)
        Assert.eq("user command expands <args>", result[8], "one two")
        Assert.eq("user command expands <q-args>", result[9], "one two")
        Assert.table_eq("user command expands <f-args>", result[10], { "one", "two" })
        Assert.eq("inline if with nmap still runs following line", result[11], 1)
        Assert.eq("inline if with nmap preserves mapping rhs", result[12], "<Plug>NetrwBrowseUpDir")
        Assert.eq("execute double-quoted command preserves bars", result[13], 11)
    end,
}
