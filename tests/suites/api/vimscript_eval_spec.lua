return {
    id = "api.vimscript_eval",
    description = "Validates backend.eval_vimscript translation layer across backends.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.eval_vim_eq(backend, "strlen result", "strlen('hello')", 5)

        local result = Assert.eval_vim(backend, "eval_vimscript has", "has('nvim')")
        Assert.eq("has('nvim')", type(result), "number")

        Assert.eval_vim_eq(backend, "type(42)", "type(42)", 0)  -- 0 = number type in Vimscript
    end,
}
