return {
    id = "runtime.vimxpr_numeric_coercion",
    description = "Ports Vimscript numeric coercion behavior through expression evaluation.",
    
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

        Assert.eq(
            "isnot# parses as a comparison operator",
            Assert.eval_vim(backend, "string isnot# comparison", "'exclusive' isnot# 'inclusive'"),
            1
        )

        Assert.eq(
            "is? ignores case",
            Assert.eval_vim(backend, "string is? comparison", "'ABC' is? 'abc'"),
            1
        )

        Assert.eq(
            "!~ returns false when pattern matches",
            Assert.eval_vim(backend, "negative regex match false", "'abc' !~ 'b'"),
            0
        )

        Assert.eq(
            "isnot# returns false when values match",
            Assert.eval_vim(backend, "string isnot# false comparison", "'inclusive' isnot# 'inclusive'"),
            0
        )
    end,
}
