return {
    id = "api.nvim_buf_attach",
    description = "Ports buffer attach coverage through public on_lines/on_detach callbacks.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nvim_buf_attach scenarios", [[
            local bufnr = vim.api.nvim_create_buf(true, false)

            local events = {}
            local ok = vim.api.nvim_buf_attach(bufnr, false, {
                on_lines = function(...)
                    events[#events + 1] = { ... }
                end,
            })

            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "hello" })

            local bufnr_auto = vim.api.nvim_create_buf(true, false)
            local auto_detach_calls = 0
            vim.api.nvim_buf_attach(bufnr_auto, false, {
                on_lines = function()
                    auto_detach_calls = auto_detach_calls + 1
                    return true
                end,
            })
            vim.api.nvim_buf_set_lines(bufnr_auto, 0, -1, false, { "hello2" })
            vim.api.nvim_buf_set_lines(bufnr_auto, 0, -1, false, { "hello3" })

            local bufnr_detach = vim.api.nvim_create_buf(true, false)
            local detached = 0
            vim.api.nvim_buf_attach(bufnr_detach, false, {
                on_detach = function()
                    detached = detached + 1
                end,
            })
            vim.api.nvim_buf_delete(bufnr_detach, { force = true })

            return {
                ok,
                events,
                auto_detach_calls,
                detached,
            }
        ]])

        Assert.eq("attach returns true", result[1], true)
        Assert.eq("on_lines fired once", #result[2], 1)
        Assert.eq("event kind", result[2][1][1], "lines")
        Assert.truthy("event bufnr positive", result[2][1][2] > 0, result[2][1][2])
        Assert.truthy("event changedtick positive", result[2][1][3] > 0, result[2][1][3])
        Assert.eq("event firstline", result[2][1][4], 0)
        Assert.eq("event old_lastline", result[2][1][5], 1)
        Assert.eq("event new_lastline", result[2][1][6], 1)
        Assert.eq("truthy return detaches callback", result[3], 1)
        Assert.eq("on_detach called on delete", result[4], 1)
    end,
}
