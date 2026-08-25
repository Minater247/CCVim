return {
    id = "api.vim_uv_check",
    description = "Ports vim.uv.new_check() and vim.uv.now() behavior through real event-loop handles.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.uv check scenarios", [[
            local check = assert(vim.uv.new_check())
            local now1 = vim.uv.now()
            local now2 = vim.uv.now()

            local calls = 0
            check:start(function()
                calls = calls + 1
                check:stop()
            end)

            local active_before = check:is_active()
            local closing_before = check:is_closing()
            local wait_ok, wait_reason = vim.wait(500, function()
                return calls >= 1
            end, 10)

            local active_after = check:is_active()
            check:close()
            local closing_after = check:is_closing()

            return {
                {
                    type(check.start),
                    type(check.stop),
                    type(check.close),
                    type(check.is_active),
                    type(check.is_closing),
                },
                type(now1),
                now2 >= now1,
                active_before,
                closing_before,
                wait_ok,
                wait_reason == nil,
                calls,
                active_after,
                closing_after,
            }
        ]])

        Assert.table_eq("check methods exist", result[1], {
            "function",
            "function",
            "function",
            "function",
            "function",
        })
        Assert.eq("vim.uv.now returns number", result[2], "number")
        Assert.eq("vim.uv.now is non-decreasing", result[3], true)
        Assert.eq("check start marks active", result[4], true)
        Assert.eq("check start marks not closing", result[5], false)
        Assert.eq("check callback wait succeeds", result[6], true)
        Assert.eq("check callback wait reason", result[7], true)
        Assert.eq("check callback ran once", result[8], 1)
        Assert.eq("check stop clears active", result[9], false)
        Assert.eq("check close marks closing", result[10], true)
    end,
}
