return {
    id = "commands.window_modifiers",
    description = "Ports documented window command modifiers from runtime/doc/windows.txt and helphelp.txt for split-producing commands and :wincmd =.", -- luacheck: ignore 631

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

            local function horizontal_helper_state(cmdline, splitbelow)
                close_extra_windows()
                vim.o.splitbelow = false

                local bottom = vim.api.nvim_get_current_win()
                vim.cmd("split")
                local top = vim.api.nvim_get_current_win()

                vim.api.nvim_set_current_win(bottom)
                vim.o.splitbelow = splitbelow
                vim.cmd(cmdline)
                local new = vim.api.nvim_get_current_win()

                return {
                    layout = vim.fn.winlayout(),
                    ids = {
                        top = top,
                        bottom = bottom,
                        new = new,
                    },
                    new_width = vim.api.nvim_win_get_width(new),
                    top_width = vim.api.nvim_win_get_width(top),
                }
            end

            local function vertical_helper_state(cmdline, splitright)
                close_extra_windows()
                vim.o.splitright = false

                local right = vim.api.nvim_get_current_win()
                vim.cmd("vsplit")
                local left = vim.api.nvim_get_current_win()

                vim.api.nvim_set_current_win(right)
                vim.o.splitright = splitright
                vim.cmd(cmdline)
                local new = vim.api.nvim_get_current_win()

                return {
                    layout = vim.fn.winlayout(),
                    ids = {
                        left = left,
                        right = right,
                        new = new,
                    },
                    new_height = vim.api.nvim_win_get_height(new),
                    left_height = vim.api.nvim_win_get_height(left),
                }
            end

            local function nested_horizontal_helper_state(cmdline, splitbelow)
                close_extra_windows()
                vim.o.splitbelow = false
                vim.o.splitright = false

                local bottom_right = vim.api.nvim_get_current_win()
                vim.cmd("split")
                local top = vim.api.nvim_get_current_win()

                vim.api.nvim_set_current_win(bottom_right)
                vim.cmd("vsplit")
                local bottom_left = vim.api.nvim_get_current_win()

                vim.api.nvim_set_current_win(bottom_right)
                vim.o.splitbelow = splitbelow
                vim.cmd(cmdline)
                local new = vim.api.nvim_get_current_win()

                return {
                    layout = vim.fn.winlayout(),
                    ids = {
                        top = top,
                        bottom_left = bottom_left,
                        bottom_right = bottom_right,
                        new = new,
                    },
                    new_width = vim.api.nvim_win_get_width(new),
                    top_width = vim.api.nvim_win_get_width(top),
                }
            end

            local function nested_vertical_helper_state(cmdline, splitright)
                close_extra_windows()
                vim.o.splitbelow = false
                vim.o.splitright = false

                local right_bottom = vim.api.nvim_get_current_win()
                vim.cmd("vsplit")
                local left = vim.api.nvim_get_current_win()

                vim.api.nvim_set_current_win(right_bottom)
                vim.cmd("split")
                local right_top = vim.api.nvim_get_current_win()

                vim.api.nvim_set_current_win(right_bottom)
                vim.o.splitright = splitright
                vim.cmd(cmdline)
                local new = vim.api.nvim_get_current_win()

                return {
                    layout = vim.fn.winlayout(),
                    ids = {
                        left = left,
                        right_top = right_top,
                        right_bottom = right_bottom,
                        new = new,
                    },
                    new_height = vim.api.nvim_win_get_height(new),
                    left_height = vim.api.nvim_win_get_height(left),
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
            local belowright_split = horizontal_helper_state("belowright split", false)
            local aboveleft_split = horizontal_helper_state("aboveleft split", true)
            local topleft_split = horizontal_helper_state("topleft split", false)
            local botright_split = nested_horizontal_helper_state("botright split", false)
            local rightbelow_vsplit = vertical_helper_state("rightbelow vsplit", false)
            local leftabove_vsplit = vertical_helper_state("leftabove vsplit", true)
            local vertical_topleft_split = vertical_helper_state("vertical topleft split", false)
            local vertical_botright_split = nested_vertical_helper_state("vertical botright split", false)

            belowright_split.layout_ok = belowright_split.layout[1] == "col"
                and #belowright_split.layout[2] == 3
                and belowright_split.layout[2][1][1] == "leaf"
                and belowright_split.layout[2][1][2] == belowright_split.ids.top
                and belowright_split.layout[2][2][1] == "leaf"
                and belowright_split.layout[2][2][2] == belowright_split.ids.bottom
                and belowright_split.layout[2][3][1] == "leaf"
                and belowright_split.layout[2][3][2] == belowright_split.ids.new

            aboveleft_split.layout_ok = aboveleft_split.layout[1] == "col"
                and #aboveleft_split.layout[2] == 3
                and aboveleft_split.layout[2][1][1] == "leaf"
                and aboveleft_split.layout[2][1][2] == aboveleft_split.ids.top
                and aboveleft_split.layout[2][2][1] == "leaf"
                and aboveleft_split.layout[2][2][2] == aboveleft_split.ids.new
                and aboveleft_split.layout[2][3][1] == "leaf"
                and aboveleft_split.layout[2][3][2] == aboveleft_split.ids.bottom

            topleft_split.layout_ok = topleft_split.layout[1] == "col"
                and #topleft_split.layout[2] == 3
                and topleft_split.layout[2][1][1] == "leaf"
                and topleft_split.layout[2][1][2] == topleft_split.ids.new
                and topleft_split.layout[2][2][1] == "leaf"
                and topleft_split.layout[2][2][2] == topleft_split.ids.top
                and topleft_split.layout[2][3][1] == "leaf"
                and topleft_split.layout[2][3][2] == topleft_split.ids.bottom

            botright_split.layout_ok = botright_split.layout[1] == "col"
                and #botright_split.layout[2] == 3
                and botright_split.layout[2][1][1] == "leaf"
                and botright_split.layout[2][1][2] == botright_split.ids.top
                and botright_split.layout[2][2][1] == "row"
                and #botright_split.layout[2][2][2] == 2
                and botright_split.layout[2][2][2][1][1] == "leaf"
                and botright_split.layout[2][2][2][1][2] == botright_split.ids.bottom_left
                and botright_split.layout[2][2][2][2][1] == "leaf"
                and botright_split.layout[2][2][2][2][2] == botright_split.ids.bottom_right
                and botright_split.layout[2][3][1] == "leaf"
                and botright_split.layout[2][3][2] == botright_split.ids.new

            rightbelow_vsplit.layout_ok = rightbelow_vsplit.layout[1] == "row"
                and #rightbelow_vsplit.layout[2] == 3
                and rightbelow_vsplit.layout[2][1][1] == "leaf"
                and rightbelow_vsplit.layout[2][1][2] == rightbelow_vsplit.ids.left
                and rightbelow_vsplit.layout[2][2][1] == "leaf"
                and rightbelow_vsplit.layout[2][2][2] == rightbelow_vsplit.ids.right
                and rightbelow_vsplit.layout[2][3][1] == "leaf"
                and rightbelow_vsplit.layout[2][3][2] == rightbelow_vsplit.ids.new

            leftabove_vsplit.layout_ok = leftabove_vsplit.layout[1] == "row"
                and #leftabove_vsplit.layout[2] == 3
                and leftabove_vsplit.layout[2][1][1] == "leaf"
                and leftabove_vsplit.layout[2][1][2] == leftabove_vsplit.ids.left
                and leftabove_vsplit.layout[2][2][1] == "leaf"
                and leftabove_vsplit.layout[2][2][2] == leftabove_vsplit.ids.new
                and leftabove_vsplit.layout[2][3][1] == "leaf"
                and leftabove_vsplit.layout[2][3][2] == leftabove_vsplit.ids.right

            vertical_topleft_split.layout_ok = vertical_topleft_split.layout[1] == "row"
                and #vertical_topleft_split.layout[2] == 3
                and vertical_topleft_split.layout[2][1][1] == "leaf"
                and vertical_topleft_split.layout[2][1][2] == vertical_topleft_split.ids.new
                and vertical_topleft_split.layout[2][2][1] == "leaf"
                and vertical_topleft_split.layout[2][2][2] == vertical_topleft_split.ids.left
                and vertical_topleft_split.layout[2][3][1] == "leaf"
                and vertical_topleft_split.layout[2][3][2] == vertical_topleft_split.ids.right

            vertical_botright_split.layout_ok = vertical_botright_split.layout[1] == "row"
                and #vertical_botright_split.layout[2] == 3
                and vertical_botright_split.layout[2][1][1] == "leaf"
                and vertical_botright_split.layout[2][1][2] == vertical_botright_split.ids.left
                and vertical_botright_split.layout[2][2][1] == "col"
                and #vertical_botright_split.layout[2][2][2] == 2
                and vertical_botright_split.layout[2][2][2][1][1] == "leaf"
                and vertical_botright_split.layout[2][2][2][1][2] == vertical_botright_split.ids.right_top
                and vertical_botright_split.layout[2][2][2][2][1] == "leaf"
                and vertical_botright_split.layout[2][2][2][2][2] == vertical_botright_split.ids.right_bottom
                and vertical_botright_split.layout[2][3][1] == "leaf"
                and vertical_botright_split.layout[2][3][2] == vertical_botright_split.ids.new

            return {
                vert_help,
                vertical_execute_split,
                vertical_equalize,
                horizontal_equalize,
                belowright_split,
                aboveleft_split,
                topleft_split,
                botright_split,
                rightbelow_vsplit,
                leftabove_vsplit,
                vertical_topleft_split,
                vertical_botright_split,
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

        Assert.eq("belowright split stays relative to the current window", result[5].layout_ok, true)
        Assert.eq("aboveleft split stays relative to the current window", result[6].layout_ok, true)
        Assert.eq("topleft split uses a root split", result[7].layout_ok, true)
        Assert.eq("topleft split gives the new window full width", result[7].new_width, result[7].top_width)
        Assert.eq("botright split uses a root split", result[8].layout_ok, true)
        Assert.eq("botright split gives the new window full width", result[8].new_width, result[8].top_width)
        Assert.eq("rightbelow vsplit stays relative to the current window", result[9].layout_ok, true)
        Assert.eq("leftabove vsplit stays relative to the current window", result[10].layout_ok, true)
        Assert.eq("vertical topleft split uses a root split", result[11].layout_ok, true)
        Assert.eq("vertical topleft split gives the new window full height", result[11].new_height, result[11].left_height)
        Assert.eq("vertical botright split uses a root split", result[12].layout_ok, true)
        Assert.eq("vertical botright split gives the new window full height", result[12].new_height, result[12].left_height)
    end,
}
