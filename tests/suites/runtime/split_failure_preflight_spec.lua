return {
    id = "runtime.split_failure_preflight",
    description = "Ports split/vsplit preflight with actual commands so feasible layouts commit and infeasible layouts fail with E36 before changing layout or firing window/buffer autocmds.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "split failure preflight scenarios", [[
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

            local function attempt(command, opts)
                reset_single_window()

                vim.o.laststatus = 0
                vim.o.cmdheight = 1
                vim.o.winminwidth = 1
                vim.o.winminheight = 1
                vim.o.winwidth = opts.winwidth
                vim.o.winheight = opts.winheight
                vim.o.winminwidth = opts.winminwidth
                vim.o.winminheight = opts.winminheight

                local events = {}
                local group = vim.api.nvim_create_augroup("SplitFailurePreflight", { clear = true })
                vim.api.nvim_create_autocmd({ "WinNew", "WinEnter", "WinLeave", "BufEnter", "BufLeave" }, {
                    group = group,
                    callback = function(args)
                        events[#events + 1] = args.event
                    end,
                })

                local before = {
                    wincount = #vim.api.nvim_tabpage_list_wins(0),
                    current = vim.api.nvim_get_current_win(),
                    layout = vim.fn.string(vim.fn.winlayout()),
                }

                local ok, err = pcall(vim.cmd, command)

                local after = {
                    wincount = #vim.api.nvim_tabpage_list_wins(0),
                    current = vim.api.nvim_get_current_win(),
                    layout = vim.fn.string(vim.fn.winlayout()),
                }

                vim.api.nvim_del_augroup_by_id(group)

                return {
                    ok,
                    tostring(err or ""),
                    before,
                    after,
                    events,
                }
            end

            return {
                attempt("vsplit", {
                    winwidth = 20,
                    winheight = 1,
                    winminwidth = 20,
                    winminheight = 1,
                }),
                attempt("split", {
                    winwidth = 1,
                    winheight = 1,
                    winminwidth = 1,
                    winminheight = 1,
                }),
                attempt("vsplit", {
                    winwidth = 100,
                    winheight = 1,
                    winminwidth = 100,
                    winminheight = 1,
                }),
                attempt("split", {
                    winwidth = 1,
                    winheight = 100,
                    winminwidth = 1,
                    winminheight = 100,
                }),
            }
        ]])

        Assert.eq("vsplit success returns ok", result[1][1], true)
        Assert.eq("vsplit success leaves empty error", result[1][2], "")
        Assert.eq("vsplit success starts from one window", result[1][3].wincount, 1)
        Assert.eq("vsplit success ends with two windows", result[1][4].wincount, 2)
        Assert.eq("vsplit success changes layout", result[1][4].layout == result[1][3].layout, false)
        Assert.truthy("vsplit success fires autocmds", #result[1][5] > 0, #result[1][5])

        Assert.eq("split success returns ok", result[2][1], true)
        Assert.eq("split success leaves empty error", result[2][2], "")
        Assert.eq("split success starts from one window", result[2][3].wincount, 1)
        Assert.eq("split success ends with two windows", result[2][4].wincount, 2)
        Assert.eq("split success changes layout", result[2][4].layout == result[2][3].layout, false)
        Assert.truthy("split success fires autocmds", #result[2][5] > 0, #result[2][5])

        Assert.eq("vsplit preflight fails", result[3][1], false)
        Assert.top_error_code("vsplit preflight reports E36", result[3][2], "E36")
        Assert.table_eq("vsplit keeps window count/current/layout", result[3][4], result[3][3])
        Assert.eq("vsplit preflight fires no autocmd", #result[3][5], 0)

        Assert.eq("split preflight fails", result[4][1], false)
        Assert.top_error_code("split preflight reports E36", result[4][2], "E36")
        Assert.table_eq("split keeps window count/current/layout", result[4][4], result[4][3])
        Assert.eq("split preflight fires no autocmd", #result[4][5], 0)
    end,
}
