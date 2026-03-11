return {
    id = "commands.window_modifiers",
    description = "Ports documented :vertical and :horizontal command-modifier behavior for split-producing commands and :wincmd =.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local root = Assert.temp_path(backend, "window-modifiers", "")
        local doc_dir = root .. "/doc"
        local tags_path = doc_dir .. "/tags"
        local help_path = doc_dir .. "/vimfn.txt"

        Assert.ensure_dir(backend, doc_dir)
        Assert.write_file(backend, tags_path, "copy()\tvimfn.txt\t/*copy()*\n")
        Assert.write_file(backend, help_path, table.concat({
            "header",
            "*copy()*",
            "body",
            "",
        }, "\n"))

        local result = Assert.eval_block(backend, "window modifier parity", string.format([[
            local function close_extra_windows()
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

            local function win_metrics()
                local wins = vim.api.nvim_tabpage_list_wins(0)
                local out = {}
                for i = 1, #wins do
                    local win = wins[i]
                    out[i] = {
                        width = vim.api.nvim_win_get_width(win),
                        height = vim.api.nvim_win_get_height(win),
                    }
                end
                table.sort(out, function(a, b)
                    if a.width ~= b.width then
                        return a.width < b.width
                    end
                    return a.height < b.height
                end)
                return out
            end

            local function nested_resize_state(modifier)
                close_extra_windows()

                local top = vim.api.nvim_get_current_win()
                vim.cmd("split")
                vim.api.nvim_set_current_win(top)
                vim.cmd("resize 12")

                local wins = vim.api.nvim_tabpage_list_wins(0)
                local bottom
                for i = 1, #wins do
                    if wins[i] ~= top then
                        bottom = wins[i]
                        break
                    end
                end

                vim.api.nvim_set_current_win(bottom)
                vim.cmd("vsplit")
                vim.cmd("vertical resize 30")

                local before = win_metrics()
                vim.cmd(modifier .. " wincmd =")
                local after = win_metrics()

                return {
                    before = before,
                    after = after,
                    layout = vim.fn.winlayout(),
                }
            end

            close_extra_windows()
            vim.cmd("set runtimepath^=" .. vim.fn.fnameescape(%q))
            vim.cmd("vert help copy()")
            local vert_help = {
                layout = vim.fn.winlayout(),
                buftype = vim.bo.buftype,
                line = vim.api.nvim_get_current_line(),
                widths = win_metrics(),
            }
            pcall(vim.cmd, "helpclose")

            close_extra_windows()
            vim.cmd("vertical execute 'split'")
            local vertical_execute_split = {
                layout = vim.fn.winlayout(),
                metrics = win_metrics(),
            }

            local vertical_equalize = nested_resize_state("vertical")
            local horizontal_equalize = nested_resize_state("horizontal")

            return {
                vert_help,
                vertical_execute_split,
                vertical_equalize,
                horizontal_equalize,
            }
        ]], root))

        Assert.eq("vertical help uses row layout", result[1].layout[1], "row")
        Assert.eq("vertical help opens help buffer", result[1].buftype, "help")
        Assert.eq("vertical help jumps to tag", result[1].line, "*copy()*")
        Assert.truthy(
            "vertical help opens two side-by-side windows",
            type(result[1].widths) == "table"
                and #result[1].widths == 2
                and result[1].widths[1].width > 0
                and result[1].widths[2].width > 0,
            result[1].widths
        )

        Assert.eq("vertical execute does not affect execute'd split", result[2].layout[1], "col")
        Assert.truthy(
            "vertical execute split keeps full widths",
            type(result[2].metrics) == "table"
                and #result[2].metrics == 2
                and result[2].metrics[1].width == result[2].metrics[2].width,
            result[2].metrics
        )

        Assert.eq("vertical equalize keeps nested layout", result[3].layout[1], "col")
        Assert.eq("vertical equalize keeps widths", result[3].before[1].width, result[3].after[1].width)
        Assert.eq("vertical equalize keeps widths (second)", result[3].before[2].width, result[3].after[2].width)
        Assert.eq("vertical equalize keeps widths (third)", result[3].before[3].width, result[3].after[3].width)

        Assert.eq("horizontal equalize keeps nested layout", result[4].layout[1], "col")
        Assert.eq("horizontal equalize keeps heights", result[4].before[1].height, result[4].after[1].height)
        Assert.eq("horizontal equalize keeps heights (second)", result[4].before[2].height, result[4].after[2].height)
        Assert.eq("horizontal equalize keeps heights (third)", result[4].before[3].height, result[4].after[3].height)
        Assert.truthy(
            "horizontal equalize changes widths",
            result[4].before[1].width ~= result[4].after[1].width
                or result[4].before[2].width ~= result[4].after[2].width
                or result[4].before[3].width ~= result[4].after[3].width,
            result[4]
        )
    end,
}
