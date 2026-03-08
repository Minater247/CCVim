return {
    id = "runtime.global_substitute",
    description = "Ports substitute and :global behavior through real Ex execution.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "substitute and global scenarios", [[
            local function set_lines(lines, cursor_line)
                vim.cmd("enew!")
                vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
                vim.api.nvim_win_set_cursor(0, { cursor_line or 1, 0 })
            end

            local function lines()
                return vim.api.nvim_buf_get_lines(0, 0, -1, false)
            end

            local function try_cmd(cmd)
                local ok, rv = pcall(vim.cmd, cmd)
                if ok then
                    return true, tostring(rv or "")
                end
                return false, tostring(rv)
            end

            set_lines({ "foo foo", "bar" }, 1)
            local ok_basic, err_basic = try_cmd("s/foo/baz/")
            local basic_lines = lines()

            vim.o.gdefault = false
            set_lines({ "aaaa" }, 1)
            local ok_set_g, err_set_g = try_cmd("s/a/x/g")
            local set_g_lines = lines()

            set_lines({ "aaaa" }, 1)
            local ok_repeat, err_repeat = try_cmd("s")
            local repeat_lines = lines()

            set_lines({ "aaaa" }, 1)
            local ok_amp, err_amp = try_cmd("s&")
            local amp_lines = lines()

            set_lines({ "a1", "a2", "b3" }, 1)
            local ok_range, err_range = try_cmd("%s/a/x/g")
            local range_lines = lines()

            set_lines({ "abc" }, 1)
            local ok_missing, err_missing = try_cmd("s/z/y/")

            set_lines({ "abc" }, 1)
            local ok_missing_e, err_missing_e = try_cmd("s/z/y/e")
            local missing_e_lines = lines()

            set_lines({ "abc 123" }, 1)
            local ok_zero, err_zero = try_cmd([=[s/[0-9]\+/[\0]/]=])
            local zero_lines = lines()

            set_lines({ "abc 123" }, 1)
            local ok_amp_ref, err_amp_ref = try_cmd([=[s/[a-z]\+/<&>/]=])
            local amp_ref_lines = lines()

            set_lines({ "aa", "bb", "aa" }, 1)
            local ok_global_sub, err_global_sub = try_cmd("g/aa/s/a/x/g")
            local global_sub_lines = lines()

            set_lines({ "foo foo", "bar" }, 1)
            local ok_global_pat, err_global_pat = try_cmd("g/foo/s//baz/g")
            local global_pat_lines = lines()

            set_lines({ "keep", "drop", "keep" }, 1)
            local ok_global_bang, err_global_bang = try_cmd("g!/keep/d")
            local global_bang_lines = lines()

            set_lines({ "one", "two", "one" }, 1)
            vim.cmd("redir => g:global_default_print")
            vim.cmd("g/one/")
            vim.cmd("redir END")
            local default_print = vim.fn.split(
                vim.fn.substitute(
                    vim.fn.substitute(vim.g.global_default_print, "^\\n", "", ""),
                    "\\n$",
                    "",
                    ""
                ),
                "\\n"
            )

            set_lines({ "ok", "bad", "ok" }, 1)
            vim.cmd([=[
function! ContinueOrFail()
  if getline('.') ==# 'bad'
    call does_not_exist()
  endif
endfunction
]=])
            vim.v.errmsg = ""
            local ok_continue, err_continue = try_cmd(
                "silent! g/./call ContinueOrFail()|s/ok/OK/"
            )
            local continue_errmsg = vim.v.errmsg
            local continue_lines = lines()

            return {
                ok_basic, err_basic, basic_lines,
                ok_set_g, err_set_g, set_g_lines,
                ok_repeat, err_repeat, repeat_lines,
                ok_amp, err_amp, amp_lines,
                ok_range, err_range, range_lines,
                ok_missing, err_missing,
                ok_missing_e, err_missing_e, missing_e_lines,
                ok_zero, err_zero, zero_lines,
                ok_amp_ref, err_amp_ref, amp_ref_lines,
                ok_global_sub, err_global_sub, global_sub_lines,
                ok_global_pat, err_global_pat, global_pat_lines,
                ok_global_bang, err_global_bang, global_bang_lines,
                default_print,
                ok_continue, err_continue, continue_errmsg, continue_lines,
            }
        ]])

        Assert.eq("basic substitute succeeds", result[1], true)
        Assert.eq("basic substitute error", result[2], "")
        Assert.table_eq("basic substitute updates first match", result[3], { "baz foo", "bar" })

        Assert.eq("g flag substitute succeeds", result[4], true)
        Assert.eq("g flag substitute error", result[5], "")
        Assert.table_eq("g flag substitute updates all matches", result[6], { "xxxx" })

        Assert.eq("repeat substitute succeeds", result[7], true)
        Assert.eq("repeat substitute error", result[8], "")
        Assert.table_eq("repeat substitute drops prior g flag", result[9], { "xaaa" })

        Assert.eq("ampersand repeat succeeds", result[10], true)
        Assert.eq("ampersand repeat error", result[11], "")
        Assert.table_eq("ampersand delimiter reuses pattern", result[12], { "aaa" })

        Assert.eq("range substitute succeeds", result[13], true)
        Assert.eq("range substitute error", result[14], "")
        Assert.table_eq("range substitute updates matching lines", result[15], { "x1", "x2", "b3" })

        Assert.eq("missing pattern errors", result[16], false)
        Assert.top_error_code("missing pattern includes E486", result[17], "E486")

        Assert.eq("missing pattern e-flag succeeds", result[18], true)
        Assert.eq("missing pattern e-flag error", result[19], "")
        Assert.table_eq("missing pattern e-flag keeps text", result[20], { "abc" })

        Assert.eq("zero replacement succeeds", result[21], true)
        Assert.eq("zero replacement error", result[22], "")
        Assert.table_eq("zero replacement inserts full match", result[23], { "abc [123]" })

        Assert.eq("ampersand replacement succeeds", result[24], true)
        Assert.eq("ampersand replacement error", result[25], "")
        Assert.table_eq("ampersand replacement inserts full match", result[26], { "<abc> 123" })

        Assert.eq("global nested substitute succeeds", result[27], true)
        Assert.eq("global nested substitute error", result[28], "")
        Assert.table_eq("global nested substitute updates matching lines", result[29], { "xx", "bb", "xx" })

        Assert.eq("global pattern reuse succeeds", result[30], true)
        Assert.eq("global pattern reuse error", result[31], "")
        Assert.table_eq("global pattern reuse applies global pattern", result[32], { "baz baz", "bar" })

        Assert.eq("global! delete succeeds", result[33], true)
        Assert.eq("global! delete error", result[34], "")
        Assert.table_eq("global! keeps matching lines", result[35], { "keep", "keep" })

        Assert.table_eq("global default print emits matches", result[36], { "one", "", "one" })

        Assert.eq("global continues on per-line error", result[37], true)
        Assert.eq("global continue error", result[38], "")
        Assert.top_error_code("global continue records E117", result[39], "E117")
        Assert.table_eq("global continue processes later lines", result[40], { "OK", "bad", "OK" })
    end,
}
