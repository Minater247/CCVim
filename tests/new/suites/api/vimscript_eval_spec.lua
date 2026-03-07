return {
    id = "api.vimscript_eval",
    description = "Validates backend.eval_vimscript translation layer across backends.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result, err = backend:eval_vimscript("strlen('hello')")
        Assert.truthy("eval_vimscript strlen", result ~= nil, err)
        Assert.eq("strlen result", result, 5)

        result, err = backend:eval_vimscript("has('nvim')")
        Assert.truthy("eval_vimscript has", result ~= nil, err)
        Assert.eq("has('nvim')", type(result), "number")

        result, err = backend:eval_vimscript("type(42)")
        Assert.truthy("eval_vimscript type", result ~= nil, err)
        Assert.eq("type(42)", result, 0)  -- 0 = number type in Vimscript
    end,
}
