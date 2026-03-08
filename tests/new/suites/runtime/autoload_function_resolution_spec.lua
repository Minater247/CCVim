return {
    id = "runtime.autoload_function_resolution",
    description = "Ports Vimscript autoload resolution through runtimepath-backed function calls.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local root = Assert.temp_path(backend, "autoload-runtime", "")
        local autoload_dir = root .. "/autoload"
        local demo_vim = autoload_dir .. "/demo.vim"
        local proxy_vim = autoload_dir .. "/proxyauto.vim"
        local expr_vim = autoload_dir .. "/demoexpr.vim"

        Assert.ensure_dir(backend, autoload_dir)
        Assert.write_file(backend, demo_vim, table.concat({
            "function! demo#Loaded()",
            "  let g:demo_loaded = get(g:, 'demo_loaded', 0) + 1",
            "  return g:demo_loaded",
            "endfunction",
            "",
        }, "\n"))
        Assert.write_file(backend, proxy_vim, table.concat({
            "function! proxyauto#Loaded()",
            "  return 123",
            "endfunction",
            "",
        }, "\n"))
        Assert.write_file(backend, expr_vim, table.concat({
            "function! demoexpr#Loaded()",
            "  return 55",
            "endfunction",
            "",
        }, "\n"))

        local result = Assert.eval_block(backend, "autoload resolution", string.format([=[
            vim.cmd("set runtimepath^=" .. vim.fn.fnameescape(%q))
            vim.cmd("call demo#Loaded()")
            vim.cmd("let g:expr_autoload = demoexpr#Loaded()")

            return {
                vim.g.demo_loaded,
                vim.fn["proxyauto#Loaded"](),
                vim.g.expr_autoload,
            }
        ]=], root))

        Assert.table_eq("autoload results", result, { 1, 123, 55 })

        Assert.expect_error_code_block(
            backend,
            "missing autoload keeps E117",
            string.format([=[
                vim.cmd("set runtimepath^=" .. vim.fn.fnameescape(%q))
                vim.cmd("call missing#Nope()")
            ]=], root),
            "E117"
        )

        Assert.remove_path(backend, demo_vim)
        Assert.remove_path(backend, proxy_vim)
        Assert.remove_path(backend, expr_vim)
        Assert.remove_path(backend, autoload_dir)
        Assert.remove_path(backend, root)
    end,
}
