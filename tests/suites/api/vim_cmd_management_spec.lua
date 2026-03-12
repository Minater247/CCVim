return {
    id = "api.vim_cmd_management",
    description = "Ports structured vim.cmd buffer, window, and tabpage management commands against Neovim-visible behavior.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local split_path = Assert.temp_path(backend, "vim-cmd-split", ".txt")
        local tabedit_path = Assert.temp_path(backend, "vim-cmd-tabedit", ".txt")
        local split_tail = split_path:match("[^/]+$")
        local tabedit_tail = tabedit_path:match("[^/]+$")

        local result = Assert.eval_block(backend, "vim.cmd management parity", string.format([[
            local function basename(path)
                return vim.fn.fnamemodify(path, ":t")
            end

            local function close_extra_windows()
                local wins = vim.api.nvim_tabpage_list_wins(0)
                local keep = wins[1] or vim.api.nvim_get_current_win()
                vim.api.nvim_set_current_win(keep)
                for i = #wins, 1, -1 do
                    if wins[i] ~= keep then
                        vim.api.nvim_win_close(wins[i], true)
                    end
                end
            end

            local function close_extra_tabs()
                while vim.fn.tabpagenr("$") > 1 do
                    vim.cmd.tabclose({ args = { "$" } })
                end
            end

            local function named_layout()
                local out = {}
                local wins = vim.api.nvim_tabpage_list_wins(0)
                for i = 1, #wins do
                    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(wins[i]))
                    out[#out + 1] = basename(name)
                end
                return out
            end

            local function sorted_copy(items)
                local out = vim.deepcopy(items)
                table.sort(out)
                return out
            end

            close_extra_tabs()
            close_extra_windows()

            vim.cmd("enew!")
            vim.cmd("file cmd_buffer_one")
            local buf1 = vim.api.nvim_get_current_buf()
            vim.cmd("enew!")
            vim.cmd("file cmd_buffer_two")
            local buf2 = vim.api.nvim_get_current_buf()

            local buffer_empty_before = vim.api.nvim_get_current_buf()
            local buffer_empty_ok, buffer_empty_err = pcall(function()
                vim.cmd.buffer({})
            end)
            local buffer_empty_after = vim.api.nvim_get_current_buf()

            vim.cmd.buffer({ count = buf1 })
            local buffer_count = {
                vim.api.nvim_get_current_buf(),
                basename(vim.api.nvim_buf_get_name(0)),
            }

            vim.cmd.buffer({ range = { buf2 } })
            local buffer_range = {
                vim.api.nvim_get_current_buf(),
                basename(vim.api.nvim_buf_get_name(0)),
            }

            close_extra_windows()
            vim.cmd("enew!")
            vim.cmd.split({ args = { %q } })
            local split_result = {
                #vim.api.nvim_tabpage_list_wins(0),
                basename(vim.api.nvim_buf_get_name(0)),
            }
            local split_count_ok, split_count_err = pcall(function()
                vim.cmd.split({ count = 2 })
            end)

            close_extra_windows()
            vim.cmd("enew!")
            vim.cmd("file cmd_window_one")
            vim.cmd("split")
            vim.cmd("enew!")
            vim.cmd("file cmd_window_two")
            vim.cmd("split")
            vim.cmd("enew!")
            vim.cmd("file cmd_window_three")
            vim.cmd("1wincmd w")
            local close_current_before = vim.api.nvim_get_current_win()
            vim.cmd.close({ count = 2 })
            local close_result = {
                sorted_copy(named_layout()),
                vim.api.nvim_get_current_win(),
                close_current_before,
            }

            close_extra_windows()
            vim.cmd("enew!")
            vim.cmd("split")
            vim.cmd("split")
            vim.cmd("1wincmd w")
            local wincmd_target = vim.api.nvim_tabpage_list_wins(0)[3]
            vim.cmd.wincmd({ count = 3, args = { "w" } })
            local wincmd_result = {
                vim.api.nvim_get_current_win(),
                wincmd_target,
            }

            close_extra_windows()
            vim.cmd("enew!")
            local resize_count_ok, resize_count_err = pcall(function()
                vim.cmd.resize({ count = 2 })
            end)
            vim.cmd.resize({ args = { "5" } })
            local resize_result = vim.api.nvim_win_get_height(0)

            close_extra_tabs()
            close_extra_windows()
            vim.cmd("enew!")
            vim.cmd.tabnew({})
            local tabnew_result = {
                vim.fn.tabpagenr("$"),
                vim.fn.tabpagenr(),
            }
            vim.cmd.tabedit({ args = { %q } })
            local tabedit_result = {
                vim.fn.tabpagenr("$"),
                vim.fn.tabpagenr(),
                basename(vim.api.nvim_buf_get_name(0)),
            }
            vim.cmd.tabnext({ args = { "2" } })
            local tabnext_result = vim.fn.tabpagenr()
            vim.cmd.tabprevious({ args = { "1" } })
            local tabprevious_result = vim.fn.tabpagenr()
            vim.cmd.tabclose({ args = { "3" } })
            local tabclose_result = {
                vim.fn.tabpagenr("$"),
                vim.fn.tabpagenr(),
            }
            local tabnew_count_ok, tabnew_count_err = pcall(function()
                vim.cmd.tabnew({ count = 1 })
            end)
            local tabnext_count_ok, tabnext_count_err = pcall(function()
                vim.cmd.tabnext({ count = 2 })
            end)

            close_extra_tabs()
            local tabclose_last_ok, tabclose_last_err = pcall(function()
                vim.cmd.tabclose({})
            end)

            return {
                buffer_empty_ok = buffer_empty_ok,
                buffer_empty_err = tostring(buffer_empty_err or ""),
                buffer_empty_same = (buffer_empty_before == buffer_empty_after),
                buffer_count = buffer_count,
                buffer_range = buffer_range,
                split_result = split_result,
                split_count_ok = split_count_ok,
                split_count_err = tostring(split_count_err or ""),
                close_result = close_result,
                wincmd_result = wincmd_result,
                resize_count_ok = resize_count_ok,
                resize_count_err = tostring(resize_count_err or ""),
                resize_result = resize_result,
                tabnew_result = tabnew_result,
                tabedit_result = tabedit_result,
                tabnext_result = tabnext_result,
                tabprevious_result = tabprevious_result,
                tabclose_result = tabclose_result,
                tabnew_count_ok = tabnew_count_ok,
                tabnew_count_err = tostring(tabnew_count_err or ""),
                tabnext_count_ok = tabnext_count_ok,
                tabnext_count_err = tostring(tabnext_count_err or ""),
                tabclose_last_ok = tabclose_last_ok,
                tabclose_last_err = tostring(tabclose_last_err or ""),
            }
        ]], split_path, tabedit_path))

        Assert.eq("vim.cmd.buffer({}) succeeds", result.buffer_empty_ok, true)
        Assert.eq("vim.cmd.buffer({}) keeps current buffer", result.buffer_empty_same, true)
        Assert.eq("vim.cmd.buffer count switches to first buffer", result.buffer_count[2], "cmd_buffer_one")
        Assert.eq("vim.cmd.buffer range switches to second buffer", result.buffer_range[2], "cmd_buffer_two")

        Assert.eq("vim.cmd.split with args opens a second window", result.split_result[1], 2)
        Assert.eq("vim.cmd.split with args loads requested file", result.split_result[2], split_tail)
        Assert.eq("vim.cmd.split rejects structured count", result.split_count_ok, false)
        Assert.truthy(
            "vim.cmd.split count error message",
            result.split_count_err:find("Command cannot accept count: split", 1, true) ~= nil,
            result.split_count_err
        )

        Assert.table_eq("vim.cmd.close count removes target window", result.close_result[1], {
            "cmd_window_one",
            "cmd_window_three",
        })
        Assert.eq("vim.cmd.close count keeps current window", result.close_result[2], result.close_result[3])
        Assert.eq("vim.cmd.wincmd count selects target window", result.wincmd_result[1], result.wincmd_result[2])

        Assert.eq("vim.cmd.resize rejects structured count", result.resize_count_ok, false)
        Assert.truthy(
            "vim.cmd.resize count error message",
            result.resize_count_err:find("Command cannot accept count: resize", 1, true) ~= nil,
            result.resize_count_err
        )
        Assert.eq("vim.cmd.resize args set explicit height", result.resize_result, 5)

        Assert.table_eq("vim.cmd.tabnew creates a second tab and focuses it", result.tabnew_result, { 2, 2 })
        Assert.table_eq("vim.cmd.tabedit opens requested file in a new tab", result.tabedit_result, {
            3,
            3,
            tabedit_tail,
        })
        Assert.eq("vim.cmd.tabnext jumps to requested tab", result.tabnext_result, 2)
        Assert.eq("vim.cmd.tabprevious jumps to requested tab", result.tabprevious_result, 1)
        Assert.table_eq("vim.cmd.tabclose closes the requested tab", result.tabclose_result, { 2, 1 })

        Assert.eq("vim.cmd.tabnew rejects structured count", result.tabnew_count_ok, false)
        Assert.truthy(
            "vim.cmd.tabnew count error message",
            result.tabnew_count_err:find("Command cannot accept count: tabnew", 1, true) ~= nil,
            result.tabnew_count_err
        )
        Assert.eq("vim.cmd.tabnext rejects structured count", result.tabnext_count_ok, false)
        Assert.truthy(
            "vim.cmd.tabnext count error message",
            result.tabnext_count_err:find("Command cannot accept count: tabnext", 1, true) ~= nil,
            result.tabnext_count_err
        )
        Assert.eq("vim.cmd.tabclose on the last tab fails", result.tabclose_last_ok, false)
        Assert.top_error_code("vim.cmd.tabclose last-tab error", result.tabclose_last_err, "E784")
    end,
}
