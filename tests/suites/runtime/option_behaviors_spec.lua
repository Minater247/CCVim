return {
    id = "runtime.option_behaviors",
    description = "Ports option behavior coverage against real backend files and public option semantics.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local root = Assert.temp_path(backend, "option-behaviors", "")
        Assert.ensure_dir(backend, root .. "/src")
        Assert.ensure_dir(backend, root .. "/lua/pkg")
        Assert.ensure_dir(backend, root .. "/inc")
        Assert.ensure_dir(backend, root .. "/plugin")
        Assert.write_file(backend, root .. "/src/main.lua", "require 'pkg.mod'\n")
        Assert.write_file(backend, root .. "/lua/pkg/mod.lua", "return {}\n")
        Assert.write_file(backend, root .. "/inc/defs.h", "#define X 1\n")

        local result = Assert.eval_block(backend, "option behaviors", string.format([=[
            local root = %q
            local src = root .. "/src/main.lua"
            local old_cwd = vim.fn.getcwd()

            local function capture_cmd(cmd)
                local ok, err = pcall(vim.cmd, cmd)
                if ok then
                    return { true, nil }
                end
                return { false, tostring(err or "") }
            end

            vim.fn.chdir(root)
            vim.cmd("enew!")
            vim.api.nvim_buf_set_name(0, src)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "require 'pkg.mod'" })
            vim.api.nvim_win_set_cursor(0, { 1, 11 })

            local mouse_default = vim.go.mouse
            local mousemodel_default = vim.go.mousemodel
            local mousetime_default = vim.go.mousetime
            local keywordprg_default = vim.go.keywordprg

            vim.cmd("set path=.," .. root .. "/lua," .. root .. "/inc")
            vim.cmd("setlocal suffixesadd=.lua")
            vim.cmd([[setlocal includeexpr=substitute(v:fname,'\.','/','g')]])

            local getline_range = vim.fn.getline(1, 3)

            vim.cmd("setlocal cocu=nvic")
            vim.cmd("setlocal cole=3")
            vim.cmd("set kp=:VimKeywordPrg")
            vim.cmd("setglobal keywordprg=:GlobalKeywordPrg")
            vim.cmd("setlocal keywordprg=:LocalKeywordPrg")
            local keywordprg_local = vim.fn.eval("&l:keywordprg")
            local keywordprg_global = vim.fn.eval("&g:keywordprg")
            vim.cmd("setlocal keywordprg<")
            local keywordprg_reset = vim.fn.eval("&l:keywordprg")

            vim.cmd([[setlocal commentstring=--\ %%s]])
            local commentstring_local = vim.fn.eval("&l:commentstring")
            vim.cmd("setlocal commentstring<")
            local commentstring_reset_default = vim.fn.eval("&l:commentstring")
            vim.cmd("setglobal commentstring=GLOBAL_%%s")
            vim.cmd("setlocal commentstring=LOCAL_%%s")
            vim.cmd("setlocal commentstring<")
            local commentstring_reset_global = vim.fn.eval("&l:commentstring")

            vim.cmd("setglobal ul=777")
            vim.cmd("setlocal ul=-1")
            local undolevels_local = vim.fn.eval("&l:undolevels")
            local undolevels_global = vim.fn.eval("&g:undolevels")
            vim.cmd("setlocal undolevels<")
            local undolevels_reset = vim.fn.eval("&l:undolevels")

            vim.cmd("setlocal udf")
            vim.cmd("set mousem=popup")
            vim.cmd("set mouset=250")

            local bad_mouse = capture_cmd("set mouse=z")

            vim.cmd("set mouse=nvn")
            local mouse_dedup = vim.o.mouse
            vim.cmd("set mouse+=ni")
            local mouse_append = vim.o.mouse
            vim.cmd("set mouse=nvi")
            vim.cmd("set mouse^=ca")
            local mouse_prepend = vim.o.mouse
            vim.cmd("set mouse-=ni")
            local mouse_prepend_remove = vim.o.mouse
            vim.cmd("set mouse=vni")
            vim.cmd("set mouse-=ni")
            local mouse_remove_contiguous = vim.o.mouse
            vim.cmd("set mouse=nvi")
            vim.cmd("set mouse-=ni")
            local mouse_keep_noncontiguous = vim.o.mouse

            local mouse_remove_unknown = capture_cmd("set mouse-=N")
            local mouse_upper = capture_cmd("set mouse=N")
            local mouse_plus_upper = capture_cmd("set mouse+=N")
            local mouse_caret_upper = capture_cmd("set mouse^=N")

            vim.wo[0][0].number = false

            local sid_none = capture_cmd([[let g:__sid_none = expand("<SID>")]])
            local sid_none_value = vim.g.__sid_none
            vim.g.__sid_none = nil

            vim.fn.chdir(old_cwd)

            return {
                findfile = vim.fn.findfile("pkg/mod"),
                finddir = vim.fn.finddir("pkg", root .. "/lua"),
                cfile = vim.fn.expand("<cfile>"),
                resolve = vim.fn.resolve(root .. "/src/../lua/pkg"),
                resolve_slash = vim.fn.resolve(root .. "/src/../lua/pkg/"),
                sid_none = sid_none,
                sid_none_value = sid_none_value,
                getline_single = vim.fn.getline(2),
                getline_range = getline_range,
                join_range = table.concat(getline_range, "\n"),
                concealcursor = vim.wo.concealcursor,
                conceallevel = vim.wo.conceallevel,
                mouse_default = mouse_default,
                mousemodel_default = mousemodel_default,
                mousetime_default = mousetime_default,
                keywordprg_default = keywordprg_default,
                keywordprg_local = keywordprg_local,
                keywordprg_global = keywordprg_global,
                keywordprg_reset = keywordprg_reset,
                commentstring_local = commentstring_local,
                commentstring_reset_default = commentstring_reset_default,
                commentstring_reset_global = commentstring_reset_global,
                undolevels_local = undolevels_local,
                undolevels_global = undolevels_global,
                undolevels_reset = undolevels_reset,
                undofile_local = vim.bo.undofile,
                mousemodel = vim.go.mousemodel,
                mousetime = vim.go.mousetime,
                bad_mouse = bad_mouse,
                mouse_dedup = mouse_dedup,
                mouse_append = mouse_append,
                mouse_prepend = mouse_prepend,
                mouse_prepend_remove = mouse_prepend_remove,
                mouse_remove_contiguous = mouse_remove_contiguous,
                mouse_keep_noncontiguous = mouse_keep_noncontiguous,
                mouse_remove_unknown = mouse_remove_unknown,
                mouse_upper = mouse_upper,
                mouse_plus_upper = mouse_plus_upper,
                mouse_caret_upper = mouse_caret_upper,
                number_window_api = vim.wo[0][0].number,
            }
        ]=], root))

        local sid_from_script = Assert.eval_vim(backend, "expand <SID> in script context", "expand('<SID>')", {
            script_ctx = root .. "/plugin/test_option_behaviors.vim",
        })

        Assert.eq("findfile path+suffixesadd", result.findfile, root .. "/lua/pkg/mod.lua")
        Assert.eq("finddir", result.finddir, root .. "/lua/pkg")
        Assert.eq("expand <cfile> stays token-shaped", result.cfile, "pkg.mod")
        local resolved_pkg = root .. "/lua/pkg"
        local resolved_pkg_private = resolved_pkg:gsub("^/tmp/", "/private/tmp/")
        Assert.truthy(
            "resolve simplifies path",
            result.resolve == resolved_pkg or result.resolve == resolved_pkg_private,
            result.resolve
        )
        Assert.truthy(
            "resolve strips trailing slash",
            result.resolve_slash == resolved_pkg or result.resolve_slash == resolved_pkg_private,
            result.resolve_slash
        )
        Assert.eq("expand <SID> without script id errors", result.sid_none[1], false)
        Assert.top_error_code("expand <SID> without script id uses E81", result.sid_none[2], "E81")
        Assert.eq("expand <SID> without script id leaves no value", result.sid_none_value, nil)
        Assert.truthy("expand <SID> with script context", type(sid_from_script) == "string" and sid_from_script:match("^<SNR>%d+_$") ~= nil, sid_from_script)

        Assert.eq("getline single missing line empty", result.getline_single, "")
        Assert.eq("getline range count", #result.getline_range, 1)
        Assert.eq("getline range first", result.getline_range[1], "require 'pkg.mod'")
        Assert.eq("join(getline range)", result.join_range, "require 'pkg.mod'")

        Assert.eq("concealcursor set via alias", result.concealcursor, "nvic")
        Assert.eq("conceallevel set via alias", result.conceallevel, 3)
        Assert.eq("mouse default", result.mouse_default, "nvi")
        Assert.eq("mousemodel default", result.mousemodel_default, "popup_setpos")
        Assert.eq("mousetime default", result.mousetime_default, 500)
        Assert.eq("keywordprg default", result.keywordprg_default, ":Man")
        Assert.eq("keywordprg local override", result.keywordprg_local, ":LocalKeywordPrg")
        Assert.eq("keywordprg global override", result.keywordprg_global, ":GlobalKeywordPrg")
        Assert.eq("keywordprg < copies global value", result.keywordprg_reset, ":GlobalKeywordPrg")
        Assert.eq("commentstring local override", result.commentstring_local, "-- %s")
        Assert.eq("commentstring < resets local-only option to default", result.commentstring_reset_default, "")
        Assert.eq("commentstring < copies global value", result.commentstring_reset_global, "GLOBAL_%s")
        Assert.eq("undolevels local override", result.undolevels_local, -1)
        Assert.eq("undolevels global value", result.undolevels_global, 777)
        Assert.eq("undolevels < copies global to local", result.undolevels_reset, 777)
        Assert.eq("undofile local set/get", result.undofile_local, true)
        Assert.eq("mousemodel set via alias", result.mousemodel, "popup")
        Assert.eq("mousetime set via alias", result.mousetime, 250)
        Assert.eq("mouse invalid value rejects", result.bad_mouse[1], false)
        Assert.eq("mouse = deduplicates repeated flags", result.mouse_dedup, "vn")
        Assert.eq("mouse += moves flags to end", result.mouse_append, "vni")
        Assert.eq("mouse ^= prepends missing flags", result.mouse_prepend, "canvi")
        Assert.eq("mouse -= keeps non-contiguous flags", result.mouse_prepend_remove, "canvi")
        Assert.eq("mouse -= removes contiguous substring", result.mouse_remove_contiguous, "v")
        Assert.eq("mouse -= keeps non-contiguous flags from base value", result.mouse_keep_noncontiguous, "nvi")
        Assert.eq("mouse -= with unknown flag is a no-op", result.mouse_remove_unknown[1], true)
        Assert.eq("mouse uppercase flag rejects", result.mouse_upper[1], false)
        Assert.top_error_code("mouse uppercase error uses E539", result.mouse_upper[2], "E539")
        Assert.eq("mouse += uppercase flag rejects", result.mouse_plus_upper[1], false)
        Assert.top_error_code("mouse += error uses E539", result.mouse_plus_upper[2], "E539")
        Assert.eq("mouse ^= uppercase flag rejects", result.mouse_caret_upper[1], false)
        Assert.top_error_code("mouse ^= error uses E539", result.mouse_caret_upper[2], "E539")
        Assert.eq("wo double index set/get", result.number_window_api, false)
    end,
}
