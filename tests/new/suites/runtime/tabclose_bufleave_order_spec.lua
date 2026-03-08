return {
    id = "runtime.tabclose_bufleave_order",
    description = "Ports current-window close ordering so BufLeave sees a registered current buffer and the survivor becomes current.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "tab close BufLeave ordering", [[
            vim.cmd("enew!")
            vim.cmd("file /tmp/tabclose_a")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
            local survivor_win = vim.api.nvim_get_current_win()

            vim.cmd("split")
            vim.cmd("enew!")
            vim.cmd("file /tmp/tabclose_b")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "b" })
            local closing_buf = vim.api.nvim_get_current_buf()
            vim.bo.bufhidden = "wipe"
            vim.o.hidden = true

            local events = {}
            vim.api.nvim_create_autocmd("BufLeave", {
                group = vim.api.nvim_create_augroup("TabCloseBufLeaveOrder", { clear = true }),
                callback = function()
                    events[#events + 1] = {
                        current_buf = vim.api.nvim_get_current_buf(),
                        current_buf_exists = vim.api.nvim_buf_is_valid(vim.api.nvim_get_current_buf()),
                    }
                end,
            })

            local close_ok, close_err = pcall(vim.cmd, "close!")

            return {
                close_ok,
                tostring(close_err or ""),
                events,
                vim.api.nvim_get_current_win(),
                #vim.api.nvim_tabpage_list_wins(0),
                vim.api.nvim_buf_is_valid(closing_buf),
                survivor_win,
            }
        ]])

        Assert.eq("close returns true", result[1], true)
        Assert.eq("BufLeave fired during close", #result[3], 1)
        Assert.eq("BufLeave sees a registered current buffer", result[3][1].current_buf_exists, true)
        Assert.eq("current window switched to survivor", result[4], result[7])
        Assert.eq("one window remains after close", result[5], 1)
        Assert.eq("closed buffer is wiped", result[6], false)
    end,
}
