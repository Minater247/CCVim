return {
    id = "api.vim_uv_timer",
    description = "Ports vim.uv.new_timer() method coverage through real timer handles.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.uv timer scenarios", [[
            local timer = assert(vim.uv.new_timer())
            local hits = 0

            local method_types = {
                type(timer.start),
                type(timer.again),
                type(timer.stop),
                type(timer.close),
                type(timer.set_repeat),
                type(timer.get_repeat),
            }

            timer:start(20, 0, function()
                hits = hits + 1
                timer:stop()
            end)

            local active_before = timer:is_active()
            local closing_before = timer:is_closing()
            local first_wait_ok, first_wait_reason = vim.wait(500, function()
                return hits >= 1
            end, 10)
            local active_after_first = timer:is_active()

            timer:set_repeat(40)
            local repeat_value = timer:get_repeat()

            local again_ok, again_err = pcall(function()
                timer:again()
            end)
            local active_after_again = timer:is_active()
            local second_wait_ok, second_wait_reason = vim.wait(500, function()
                return hits >= 2
            end, 10)
            local active_after_second = timer:is_active()

            timer:stop()
            local active_after_stop = timer:is_active()
            timer:close()
            local closing_after = timer:is_closing()

            return {
                method_types,
                active_before,
                closing_before,
                first_wait_ok,
                first_wait_reason == nil,
                hits >= 1,
                active_after_first,
                repeat_value,
                again_ok,
                tostring(again_err),
                active_after_again,
                second_wait_ok,
                second_wait_reason == nil,
                hits,
                active_after_second,
                active_after_stop,
                closing_after,
            }
        ]])

        Assert.table_eq("timer methods exist", result[1], {
            "function",
            "function",
            "function",
            "function",
            "function",
            "function",
        })
        Assert.eq("timer start marks active", result[2], true)
        Assert.eq("timer start marks not closing", result[3], false)
        Assert.eq("timer first wait succeeds", result[4], true)
        Assert.eq("timer first wait reason", result[5], true)
        Assert.eq("timer first callback fired", result[6], true)
        Assert.eq("timer inactive after first one-shot callback", result[7], false)
        Assert.eq("timer repeat round-trips", result[8], 40)
        Assert.eq("timer again succeeds", result[9], true)
        Assert.eq("timer again error stays nil", result[10], "nil")
        Assert.eq("timer again marks active", result[11], true)
        Assert.eq("timer second wait succeeds", result[12], true)
        Assert.eq("timer second wait reason", result[13], true)
        Assert.eq("timer callback fired twice total", result[14], 2)
        Assert.eq("timer inactive after second callback", result[15], false)
        Assert.eq("timer stop keeps inactive", result[16], false)
        Assert.eq("timer close marks closing", result[17], true)
    end,
}
