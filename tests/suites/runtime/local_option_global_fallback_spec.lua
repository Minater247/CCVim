return {
    id = "runtime.local_option_global_fallback",
    description = "Checks that new buffers and windows inherit global local-only options, while existing ones keep their local values; tabpage cmdheight keeps matching global tab reads.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "local option global fallback parity", [[
            vim.api.nvim_set_option_value("tabstop", 4, { scope = "global" })
            vim.api.nvim_set_option_value("shiftwidth", 4, { scope = "global" })
            vim.api.nvim_set_option_value("expandtab", true, { scope = "global" })

            local buffer_current = {
                tabstop = vim.bo.tabstop,
                shiftwidth = vim.bo.shiftwidth,
                expandtab = vim.bo.expandtab,
            }

            vim.api.nvim_set_option_value("tabstop", 6, { scope = "local", buf = 0 })
            vim.api.nvim_set_option_value("expandtab", false, { scope = "local", buf = 0 })
            local buffer_local = {
                tabstop = vim.bo.tabstop,
                shiftwidth = vim.bo.shiftwidth,
                expandtab = vim.bo.expandtab,
            }

            vim.cmd("enew!")
            local buffer_new = {
                tabstop = vim.bo.tabstop,
                shiftwidth = vim.bo.shiftwidth,
                expandtab = vim.bo.expandtab,
            }

            vim.api.nvim_set_option_value("number", true, { scope = "global" })
            vim.api.nvim_set_option_value("numberwidth", 7, { scope = "global" })
            vim.api.nvim_set_option_value("cursorline", true, { scope = "global" })

            local window_current = {
                number = vim.wo.number,
                numberwidth = vim.wo.numberwidth,
                cursorline = vim.wo.cursorline,
            }

            vim.api.nvim_set_option_value("numberwidth", 9, { scope = "local", win = 0 })
            local window_local = {
                number = vim.wo.number,
                numberwidth = vim.wo.numberwidth,
                cursorline = vim.wo.cursorline,
            }

            vim.cmd("tabnew")
            local window_new = {
                number = vim.wo.number,
                numberwidth = vim.wo.numberwidth,
                cursorline = vim.wo.cursorline,
            }

            vim.api.nvim_set_option_value("cmdheight", 3, { scope = "global" })
            local tab_current = vim.o.cmdheight
            local tab_current_local = vim.api.nvim_get_option_value("cmdheight", { scope = "local" })
            vim.cmd("tabnew")
            local tab_new = vim.o.cmdheight
            local tab_new_local = vim.api.nvim_get_option_value("cmdheight", { scope = "local" })

            return {
                buffer_current = buffer_current,
                buffer_local = buffer_local,
                buffer_new = buffer_new,
                window_current = window_current,
                window_local = window_local,
                window_new = window_new,
                tab_current = tab_current,
                tab_current_local = tab_current_local,
                tab_new = tab_new,
                tab_new_local = tab_new_local,
            }
        ]])

        Assert.eq("current buffer keeps prior local tabstop", result.buffer_current.tabstop, 8)
        Assert.eq("current buffer keeps prior local shiftwidth", result.buffer_current.shiftwidth, 8)
        Assert.eq("current buffer keeps prior local expandtab", result.buffer_current.expandtab, false)
        Assert.eq("explicit buffer local tabstop still wins", result.buffer_local.tabstop, 6)
        Assert.eq("explicit buffer local keeps prior local shiftwidth", result.buffer_local.shiftwidth, 8)
        Assert.eq("explicit buffer local expandtab still wins", result.buffer_local.expandtab, false)
        Assert.eq("new buffer inherits global tabstop", result.buffer_new.tabstop, 4)
        Assert.eq("new buffer inherits global shiftwidth", result.buffer_new.shiftwidth, 4)
        Assert.eq("new buffer inherits global expandtab", result.buffer_new.expandtab, true)

        Assert.eq("current window keeps prior local number", result.window_current.number, false)
        Assert.eq("current window keeps prior local numberwidth", result.window_current.numberwidth, 4)
        Assert.eq("current window keeps prior local cursorline", result.window_current.cursorline, false)
        Assert.eq("explicit window local numberwidth still wins", result.window_local.numberwidth, 9)
        Assert.eq("explicit window local keeps prior local number", result.window_local.number, false)
        Assert.eq("explicit window local keeps prior local cursorline", result.window_local.cursorline, false)
        Assert.eq("new window inherits global number", result.window_new.number, true)
        Assert.eq("new tab window inherits global numberwidth", result.window_new.numberwidth, 7)
        Assert.eq("new window inherits global cursorline", result.window_new.cursorline, true)

        Assert.eq("current tabpage cmdheight uses global value", result.tab_current, 3)
        Assert.eq("current tabpage local cmdheight uses global value", result.tab_current_local, 3)
        Assert.eq("new tabpage cmdheight uses global value", result.tab_new, 3)
        Assert.eq("new tabpage local cmdheight uses global value", result.tab_new_local, 3)
    end,
}
