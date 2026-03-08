return {
    id = "runtime.vimxpr_numeric_coercion",
    description = "Ports Vimscript numeric coercion behavior through expression evaluation.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.table_eq(
            "list plus list concatenates",
            Assert.eval_vim(backend, "list plus list", "[1] + [2]"),
            { 1, 2 }
        )

        Assert.table_eq(
            "empty list plus list concatenates",
            Assert.eval_vim(backend, "empty list plus list", "[] + [3]"),
            { 3 }
        )

        Assert.expect_error_code_vim(
            backend,
            "string plus list errors",
            "'abc' + []",
            "E745"
        )

        Assert.expect_error_code_vim(
            backend,
            "dict plus number errors",
            "{} + 1",
            "E728"
        )

        Assert.expect_error_code_vim(
            backend,
            "funcref plus number errors",
            "function('len') + 1",
            "E703"
        )
    end,
}
