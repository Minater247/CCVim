return {
    id = "runtime.vimxpr_slice",
    description = "Checks Vim expression slicing semantics for strings/lists and script local concatenation.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.eval_vim_eq(backend, "string slice omitted start", "'abcdef'[:-2]", "abcde")
        Assert.eval_vim_eq(backend, "string slice both bounds", "'abcdef'[2:-2]", "cde")

        local list = Assert.eval_vim(backend, "list slice", "[1,2,3,4][1:2]")
        Assert.table_eq("list slice values", list, { 2, 3 })

        Assert.eval_vim_eq(
            backend,
            "slice expression value",
            [[s:skip_expr[:-14] . "'comment\\|doc'"]],
            "s:SynAt(line('.'),col('.')) =~? 'comment\\|doc'",
            {
                script_ctx = "/tmp/vimxpr_slice_spec.vim",
                setup = [[
let s:skip_expr = "s:SynAt(line('.'),col('.')) =~? b:syng_strcom"
]],
            }
        )
    end,
}
