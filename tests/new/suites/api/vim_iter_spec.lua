return {
    id = "api.vim_iter",
    description = "Ensures vim.iter list/dict iteration pipelines behave as expected.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        if backend.name == "lua_editor" then
            local api = backend:api_build().vim

            local out = api.iter({ 1, 2, 3, 4 })
                :filter(function(v) return v % 2 == 0 end)
                :map(function(v) return v * 10 end)
                :totable()
            Assert.table_eq("list filter+map", out, { 20, 40 })

            local extmarks = {
                { 1, 0, 0, { invalid = true } },
                { 2, 0, 0, { invalid = false } },
                { 3, 0, 0, {} },
            }
            local out2 = api.iter(extmarks)
                :filter(function(extmark) return not extmark[4].invalid end)
                :totable()
            Assert.eq("filtered len", #out2, 2)
            Assert.eq("first id", out2[1][1], 2)
            Assert.eq("second id", out2[2][1], 3)

            local dict = api.iter({ a = 1, b = 2 }):totable()
            Assert.eq("dict pair count", #dict, 2)
            Assert.contains_pair("dict has a", dict, "a", 1)
            Assert.contains_pair("dict has b", dict, "b", 2)
            return
        end

        local result, err = backend:eval_lua("vim.iter({1,2,3,4}):filter(function(v) return v % 2 == 0 end):totable()")
        Assert.truthy("headless eval ok", result ~= nil, err)
        Assert.eq("headless filtered", result, "[2,4]")
    end,
}
