return {
    id = "api.vim_islist",
    description = "Checks vim.islist/isarray semantics and empty-dict metatable handling.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        if backend.name == "lua_editor" then
            local api = backend:api_build().vim
            Assert.truthy("vim.islist exists", type(api.islist) == "function", type(api.islist))
            Assert.truthy("vim.isarray exists", type(api.isarray) == "function", type(api.isarray))
            Assert.truthy("vim.tbl_islist exists", type(api.tbl_islist) == "function", type(api.tbl_islist))

            Assert.eq("islist empty table", api.islist({}), true)
            Assert.eq("islist contiguous", api.islist({ "a", "b", "c" }), true)
            Assert.eq("islist gap", api.islist({ [1] = "a", [3] = "c" }), false)
            Assert.eq("islist dict key", api.islist({ a = 1 }), false)
            Assert.eq("islist non-table", api.islist("x"), false)

            Assert.eq("isarray non-contiguous integers", api.isarray({ [2] = true, [5] = true }), true)
            Assert.eq("isarray non-integer key", api.isarray({ [1] = true, a = true }), false)
            Assert.eq("tbl_islist alias", api.tbl_islist({ 1, 2 }), true)

            api._empty_dict_mt = {}
            local empty_dict = setmetatable({}, api._empty_dict_mt)
            Assert.eq("islist empty_dict mt", api.islist(empty_dict), false)
            Assert.eq("isarray empty_dict mt", api.isarray(empty_dict), false)
            return
        end

        local result, err = backend:eval_lua("{vim.islist({}), vim.islist({a=1}), vim.isarray({[2]=true,[5]=true})}")
        Assert.truthy("headless eval ok", result ~= nil, err)
        Assert.eq("headless tuple", result, "[true,false,true]")
    end,
}
