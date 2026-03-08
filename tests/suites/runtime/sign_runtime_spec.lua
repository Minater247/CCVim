return {
    id = "runtime.sign_runtime",
    description = "Ports sign placement, movement, and removal behavior through the public sign API.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local result = Assert.eval_block(backend, "sign runtime via public API", [[
            vim.cmd("enew!")
            local bufnr = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_set_name(bufnr, "/tmp/sign_runtime.lua")
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two", "three", "four" })

            local define_warn = vim.fn.sign_define("WarnSign", { text = "!!", priority = 30 })
            local define_numeric = vim.fn.sign_define("001", { text = "??", priority = 10 })

            local id_global = vim.fn.sign_place(0, "", "WarnSign", bufnr, { lnum = 2 })
            local id_group = vim.fn.sign_place(0, "g1", "WarnSign", bufnr, { lnum = 3 })
            local placed_all = vim.fn.sign_getplaced(bufnr, { group = "*" })

            local moved_id = vim.fn.sign_place(id_global, "", "WarnSign", bufnr, { lnum = 3 })
            local moved = vim.fn.sign_getplaced(bufnr, { group = "", id = id_global })

            vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})
            local shifted = vim.fn.sign_getplaced(bufnr, { group = "*", lnum = 2 })

            vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, {})
            local after_delete = vim.fn.sign_getplaced(bufnr, { group = "*" })

            local g0 = vim.fn.sign_place(0, "", "WarnSign", bufnr, { lnum = 1 })
            local g1 = vim.fn.sign_place(0, "g1", "WarnSign", bufnr, { lnum = 1 })
            local unplace_one = vim.fn.sign_unplace("", { buffer = bufnr, id = g0 })
            local grouped = vim.fn.sign_getplaced(bufnr, { group = "*" })
            local unplace_all = vim.fn.sign_unplace("*", { buffer = bufnr })
            local empty = vim.fn.sign_getplaced(bufnr, { group = "*" })

            return {
                define_warn = define_warn,
                define_numeric = define_numeric,
                id_global = id_global,
                id_group = id_group,
                placed_all = placed_all,
                moved_id = moved_id,
                moved = moved,
                shifted = shifted,
                after_delete = after_delete,
                g0 = g0,
                g1 = g1,
                unplace_one = unplace_one,
                grouped = grouped,
                unplace_all = unplace_all,
                empty = empty,
            }
        ]])

        Assert.eq("define sign", result.define_warn, 0)
        Assert.eq("define sign in numeric-name form", result.define_numeric, 0)
        Assert.eq("first auto id in global group", result.id_global, 1)
        Assert.eq("first auto id in named group", result.id_group, 1)
        Assert.eq("placed result has one buffer entry", #result.placed_all, 1)
        Assert.eq("placed signs count", #result.placed_all[1].signs, 2)
        Assert.eq("first placed lnum ordering", result.placed_all[1].signs[1].lnum, 2)
        Assert.eq("second placed lnum ordering", result.placed_all[1].signs[2].lnum, 3)
        Assert.eq("move existing id by placing same id", result.moved_id, result.id_global)
        Assert.eq("moved sign now on line 3", result.moved[1].signs[1].lnum, 3)
        Assert.eq("both signs shifted up after deleting first line", #result.shifted[1].signs, 2)
        Assert.eq("signs on deleted line are removed", #result.after_delete[1].signs, 0)
        Assert.truthy("placed signs for unplace test", result.g0 > 0 and result.g1 > 0)
        Assert.eq("unplace one id from global group", result.unplace_one, 0)
        Assert.eq("group sign remains after removing global id", #result.grouped[1].signs, 1)
        Assert.eq("remaining sign group is g1", result.grouped[1].signs[1].group, "g1")
        Assert.eq("unplace all groups from buffer", result.unplace_all, 0)
        Assert.eq("all signs removed", #result.empty[1].signs, 0)
    end,
}
