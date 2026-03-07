return {
    id = "runtime.vimxpr_slice",
    description = "Checks Vim expression slicing semantics for strings/lists and script local concatenation.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local Error = backend.mock.loadModule("lib.error")
        local VimExpr = backend.mock.loadModule("lib.excmd.vimxpr")
        local Options = backend.mock.loadModule("lib.options")
        _G.options = Options

        local function eval(expr, scope_s)
            return VimExpr.evaluate(expr, {
                scope = { g = {}, s = scope_s or {}, l = {}, a = {}, v = {} },
                funcs = {},
            })
        end

        Assert.eq("string slice omitted start", eval("'abcdef'[:-2]"), "abcde")
        Assert.eq("string slice both bounds", eval("'abcdef'[2:-2]"), "cde")

        local list = eval("[1,2,3,4][1:2]")
        Assert.truthy("list slice returns list", type(list) == "table", type(list))
        Assert.table_eq("list slice values", list, { 2, 3 })

        local skip_expr = "s:SynAt(line('.'),col('.')) =~? b:syng_strcom"
        local rv = eval("s:skip_expr[:-14] . \"'comment\\\\|doc'\"", { skip_expr = skip_expr })
        Assert.truthy("slice expression parses", not Error.IsError(rv), rv)
        Assert.eq("slice expression value", rv, "s:SynAt(line('.'),col('.')) =~? 'comment\\|doc'")
    end,
}
