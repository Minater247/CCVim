return {
    id = "api.vim_wait",
    description = "Ports vim.wait() behavior for immediate success, timeout, "
        .. "timers, callback errors, and fast-event guard.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "vim.wait scenarios", [[
            local immediate_calls = 0
            local immediate_ok, immediate_reason = vim.wait(100, function()
                immediate_calls = immediate_calls + 1
                return true
            end, 10)

            local zero_calls = 0
            local zero_ok, zero_reason = vim.wait(0, function()
                zero_calls = zero_calls + 1
                return false
            end, 10)

            local timer_hits = 0
            local timer = assert(vim.uv.new_timer())
            timer:start(20, 0, function()
                timer_hits = timer_hits + 1
                timer:stop()
                timer:close()
            end)
            local timer_ok, timer_reason = vim.wait(500, function()
                return timer_hits >= 1
            end, 10)

            local fast_hits = 0
            local fast_timer = assert(vim.uv.new_timer())
            fast_timer:start(20, 0, function()
                fast_hits = fast_hits + 1
                fast_timer:stop()
                fast_timer:close()
            end)
            local fast_ok, fast_reason = vim.wait(500, function()
                return fast_hits >= 1
            end, 10, true)

            local callback_ok, callback_err = pcall(function()
                vim.wait(50, function()
                    error("boom")
                end, 10)
            end)

            local fast_guard = nil
            local guard_timer = assert(vim.uv.new_timer())
            guard_timer:start(0, 0, function()
                local ok, err = pcall(function()
                    vim.wait(10, function()
                        return false
                    end, 10)
                end)
                fast_guard = {
                    ok,
                    tostring(err or ""),
                }
                guard_timer:stop()
                guard_timer:close()
            end)
            local guard_wait_ok, guard_wait_reason = vim.wait(500, function()
                return fast_guard ~= nil
            end, 10)

            return {
                immediate_ok,
                immediate_reason == nil,
                immediate_calls,
                zero_ok,
                zero_reason,
                zero_calls,
                timer_ok,
                timer_reason == nil,
                timer_hits,
                fast_ok,
                fast_reason == nil,
                fast_hits,
                callback_ok,
                tostring(callback_err),
                guard_wait_ok,
                guard_wait_reason == nil,
                fast_guard,
            }
        ]])

        Assert.eq("immediate callback success", result[1], true)
        Assert.eq("immediate callback reason", result[2], true)
        Assert.eq("immediate callback call count", result[3], 1)
        Assert.eq("zero timeout result", result[4], false)
        Assert.eq("zero timeout reason", result[5], -1)
        Assert.eq("zero timeout callback call count", result[6], 1)
        Assert.eq("timer wait succeeds", result[7], true)
        Assert.eq("timer wait reason", result[8], true)
        Assert.eq("timer callback fired once", result[9], 1)
        Assert.eq("fast_only timer wait succeeds", result[10], true)
        Assert.eq("fast_only timer wait reason", result[11], true)
        Assert.eq("fast_only timer callback fired once", result[12], 1)
        Assert.eq("callback error raised", result[13], false)
        Assert.truthy("callback error message", result[14]:find("boom", 1, true) ~= nil, result[14])
        Assert.eq("fast-event guard callback ran", result[15], true)
        Assert.eq("fast-event guard callback reason", result[16], true)
        Assert.eq("fast-event guard raised", result[17][1], false)
        Assert.top_error_code("fast-event guard raised E5560", result[17][2], "E5560")
    end,
}
