return {
    id = "runtime.diff_mode",
    description = "Exercises diff window setup, change navigation, copying, and option restoration.",

    run = function(ctx)
        local Assert = ctx.assert
        local result = Assert.eval_block(ctx.backend, "diff mode behavior", [[
            local function command(value)
                local ok, err = pcall(vim.cmd, value)
                if not ok then error(value .. ": " .. tostring(err)) end
            end
            command("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "same", "left", "middle", "tail" })
            command("file diff-left")
            vim.wo.wrap = true
            vim.wo.foldmethod = "manual"
            vim.wo.foldcolumn = "0"
            local left_win = vim.api.nvim_get_current_win()
            command("split")
            command("enew!")
            local right_win = vim.api.nvim_get_current_win()
            local right_buf = vim.api.nvim_get_current_buf()
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "same", "right", "middle", "added", "tail" })
            command("file diff-right")
            command("diffthis")
            vim.api.nvim_set_current_win(left_win)
            command("diffthis")

            local entered = {
                vim.wo.diff,
                vim.wo.scrollbind,
                vim.wo.cursorbind,
                vim.wo.wrap,
                vim.wo.foldmethod,
                vim.wo.foldcolumn,
                vim.o.scrollopt,
            }

            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            command("normal ]c")
            local first_change = vim.api.nvim_win_get_cursor(0)[1]
            command("diffget")
            local after_get = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            command("diffupdate")
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            command("normal ]c")
            local remaining_change = vim.api.nvim_win_get_cursor(0)[1]
            command("1,$diffget " .. tostring(right_buf))
            local after_range_get = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            vim.api.nvim_buf_set_lines(0, 1, 2, false, { "pushed" })
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            command("diffput " .. tostring(right_buf))
            local after_put = vim.api.nvim_buf_get_lines(right_buf, 0, -1, false)

            command("diffoff")
            local left_after_off = {
                vim.wo.diff,
                vim.wo.scrollbind,
                vim.wo.cursorbind,
                vim.wo.wrap,
                vim.wo.foldmethod,
                vim.wo.foldcolumn,
            }
            command("diffoff!")
            vim.api.nvim_set_current_win(right_win)
            local right_diff = vim.wo.diff

            return {
                entered, first_change, after_get, remaining_change,
                after_range_get, after_put, left_after_off, right_diff,
            }
        ]])

        Assert.table_eq("diffthis applies documented window options", result[1], {
            true, true, true, false, "diff", "2", "ver,jump,hor",
        })
        Assert.eq("]c finds the first changed hunk", result[2], 2)
        Assert.table_eq("diffget copies the hunk from the other buffer", result[3], {
            "same", "right", "middle", "tail",
        })
        Assert.eq("]c finds the remaining inserted hunk", result[4], 4)
        Assert.table_eq("ranged diffget copies every selected hunk", result[5], {
            "same", "right", "middle", "added", "tail",
        })
        Assert.table_eq("diffput with a buffer number updates that buffer", result[6], {
            "same", "pushed", "middle", "added", "tail",
        })
        Assert.table_eq("diffoff restores saved local values", result[7], {
            false, false, false, true, "manual", "0",
        })
        Assert.eq("diffoff! disables the other diff window", result[8], false)

        local path = Assert.temp_path(ctx.backend, "diffsplit-target", ".txt")
        Assert.write_file(ctx.backend, path, "one\ntarget\nthree\n")
        local split = Assert.eval_block(ctx.backend, "diffsplit behavior", string.format([=[
            local wins = vim.api.nvim_tabpage_list_wins(0)
            vim.api.nvim_set_current_win(wins[1])
            for i = #wins, 2, -1 do vim.api.nvim_win_close(wins[i], true) end
            vim.cmd("enew!")
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "base", "three" })
            vim.wo.wrap = false
            vim.cmd("diffsplit " .. %q)
            local diff_wins = vim.api.nvim_tabpage_list_wins(0)
            local values = {}
            for _, win in ipairs(diff_wins) do
                values[#values + 1] = {
                    vim.api.nvim_get_option_value("diff", { win = win }),
                    vim.api.nvim_get_option_value("scrollbind", { win = win }),
                    vim.api.nvim_get_option_value("cursorbind", { win = win }),
                    vim.api.nvim_win_get_width(win),
                }
            end
            local loaded = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            vim.cmd("close")
            local remaining = {
                vim.wo.diff,
                vim.wo.scrollbind,
                vim.wo.cursorbind,
                vim.wo.wrap,
                vim.wo.foldmethod,
                vim.wo.foldcolumn,
            }
            return { #diff_wins, values, loaded, remaining }
        ]=], path))
        Assert.eq("diffsplit creates one peer window", split[1], 2)
        for _, values in ipairs(split[2]) do
            Assert.table_eq("diffsplit configures each window", { values[1], values[2], values[3] }, {
                true, true, true,
            })
        end
        Assert.eq("diffsplit defaults to a horizontal split", split[2][1][4], split[2][2][4])
        Assert.table_eq("diffsplit loads its file", split[3], { "one", "target", "three" })
        Assert.table_eq("closeoff restores the last diff window", split[4], {
            false, false, false, false, "manual", "0",
        })
    end,
}
