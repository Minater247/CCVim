return {
    id = "api.vim_iter",
    description = "Ensures vim.iter list/dict iteration pipelines behave as expected.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval(
            backend,
            "eval list filter",
            "vim.iter({1,2,3,4}):filter(function(v) return v % 2 == 0 end):totable()"
        )
        Assert.table_eq("list filter", result, {2, 4})

        result = Assert.eval_block(backend, "eval extmark filter", [[
            local out = vim.iter({{1,0,0,{invalid=true}},{2,0,0,{invalid=false}},{3,0,0,{}}})
                :filter(function(extmark) return not extmark[4].invalid end)
                :totable()
            return {#out, out[1][1], out[2][1]}
        ]])
        Assert.table_eq("extmark filter", result, {2, 2, 3})

        result = Assert.eval_block(backend, "eval dict iteration", [=[
            local t = vim.iter({a=1,b=2}):totable()
            local m = {}
            for i = 1, #t do
                m[t[i][1]] = t[i][2]
            end
            return {#t, m.a, m.b}
        ]=])
        Assert.table_eq("dict iteration", result, {2, 1, 2})
    end,
}
