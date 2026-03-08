return {
    id = "runtime.vscope_type",
    description = "Ports shared v: scope truthiness and type() behavior through runtime execution.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "v:true and v:false shared scope", [=[
            vim.cmd([[
                function! TestVScope(enable)
                  if a:enable
                    let g:v_scope_last = 1
                  else
                    let g:v_scope_last = 0
                  endif
                endfunction
                call TestVScope(v:true)
                let g:v_scope_true = g:v_scope_last
                call TestVScope(v:false)
                let g:v_scope_false = g:v_scope_last
            ]])

            return {
                vim.g.v_scope_true,
                vim.g.v_scope_false,
            }
        ]=])

        Assert.table_eq("v: scope truthiness", result, { 1, 0 })
        Assert.eval_vim_eq(backend, "type({}) reports dict", "type({})", 4)
        Assert.eval_vim_eq(backend, "type([]) reports list", "type([])", 3)
    end,
}
