return {
    id = "runtime.close_command",
    description = "Ports :close differences from :quit: E444 on the last window, count-targeted close, and no QuitPre.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "close command behavior", [[
            local name_seq = 0

            local function reset_single_window()
                local wins = vim.api.nvim_tabpage_list_wins(0)
                local keep = wins[1] or vim.api.nvim_get_current_win()
                vim.api.nvim_set_current_win(keep)
                for i = #wins, 1, -1 do
                    if wins[i] ~= keep then
                        vim.api.nvim_win_close(wins[i], true)
                    end
                end
                vim.cmd("enew!")
            end

            local function named_layout()
                local out = {}
                local wins = vim.api.nvim_tabpage_list_wins(0)
                for i = 1, #wins do
                    out[#out + 1] = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(wins[i]))
                end
                return out
            end

            local function set_close_windows()
                name_seq = name_seq + 1
                local suffix = tostring(name_seq)
                reset_single_window()
                vim.cmd("file one_" .. suffix)
                vim.cmd("split")
                vim.cmd("enew!")
                vim.cmd("file two_" .. suffix)
                vim.cmd("split")
                vim.cmd("enew!")
                vim.cmd("file three_" .. suffix)
                vim.cmd("1wincmd w")
            end

            reset_single_window()
            local close_last_ok, close_last_err = pcall(vim.cmd, "close")
            local close_bang_last_ok, close_bang_last_err = pcall(vim.cmd, "close!")

            set_close_windows()
            local before_count = named_layout()
            local before_current = vim.fn.winnr()
            vim.cmd("2close")
            local after_count = named_layout()
            local after_current = vim.fn.winnr()

            set_close_windows()
            local events = {}
            local group = vim.api.nvim_create_augroup("CloseCommandSpec", { clear = true })
            vim.api.nvim_create_autocmd("QuitPre", {
                group = group,
                callback = function(args)
                    events[#events + 1] = args.event
                end,
            })
            vim.cmd("close")
            local close_events = vim.deepcopy(events)
            events = {}
            vim.cmd("quit")
            local quit_events = vim.deepcopy(events)
            vim.api.nvim_del_augroup_by_id(group)

            return {
                close_last_ok,
                tostring(close_last_err or ""),
                close_bang_last_ok,
                tostring(close_bang_last_err or ""),
                before_count,
                before_current,
                after_count,
                after_current,
                close_events,
                quit_events,
            }
        ]])

        Assert.eq("close on last window fails", result[1], false)
        Assert.top_error_code("close on last window uses E444", result[2], "E444")
        Assert.eq("close! on last window fails", result[3], false)
        Assert.top_error_code("close! on last window uses E444", result[4], "E444")
        Assert.eq("counted close starts with three named windows", #result[5], 3)
        Assert.eq("counted close starts in first window", result[6], 1)
        Assert.eq("2close removes one window", #result[7], 2)
        Assert.eq("2close keeps first window name", result[7][1], result[5][1])
        Assert.eq("2close keeps third window name", result[7][2], result[5][3])
        Assert.eq("2close keeps current window", result[8], 1)
        Assert.eq("close does not fire QuitPre", #result[9], 0)
        Assert.table_eq("quit fires QuitPre once", result[10], { "QuitPre" })

        Assert.expect_error_code_block(backend, "counted close rejects invalid range", [[
            vim.cmd("enew!")
            vim.cmd("split")
            vim.cmd("split")
            vim.cmd("4close")
        ]], "E16")
    end,
}
