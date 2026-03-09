return {
    id = "api.nvim_open_win_split_size",
    description = "Checks that split windows created through nvim_open_win honor requested width and height.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nvim_open_win split size scenarios", [[
            vim.cmd("enew!")
            local base = vim.api.nvim_get_current_win()

            local left = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "left",
                width = 12,
            })

            local below = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "below",
                height = 5,
            })

            local right = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "right",
                width = 9,
            })

            local above = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "above",
                height = 4,
            })

            return {
                #vim.api.nvim_tabpage_list_wins(0),
                vim.api.nvim_win_get_width(left),
                vim.api.nvim_win_get_height(below),
                vim.api.nvim_win_get_width(right),
                vim.api.nvim_win_get_height(above),
                vim.api.nvim_win_get_width(base) > 0,
                vim.api.nvim_win_get_height(base) > 0,
            }
        ]])

        Assert.eq("split windows created", result[1], 5)
        Assert.eq("left split honors requested width", result[2], 12)
        Assert.eq("below split honors requested height", result[3], 5)
        Assert.eq("right split honors requested width", result[4], 9)
        Assert.eq("above split honors requested height", result[5], 4)
        Assert.eq("base window width stays positive", result[6], true)
        Assert.eq("base window height stays positive", result[7], true)

        result = Assert.eval_block(backend, "nvim_open_win preserves explicit sizes across follow-up splits", [[
            local out = {}

            local function run_case(equalalways, split_same_window)
                local current = vim.api.nvim_get_current_win()
                for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                    if win ~= current then
                        vim.api.nvim_win_close(win, true)
                    end
                end
                vim.cmd("enew!")
                vim.o.equalalways = equalalways

                local base = vim.api.nvim_get_current_win()
                local left = vim.api.nvim_open_win(0, false, {
                    win = base,
                    split = "left",
                    width = 12,
                })

                local follow_target = split_same_window and left or base
                local below = vim.api.nvim_open_win(0, false, {
                    win = follow_target,
                    split = "below",
                    height = 5,
                })

                out[#out + 1] = #vim.api.nvim_tabpage_list_wins(0)
                out[#out + 1] = vim.api.nvim_win_get_width(left)
                out[#out + 1] = vim.api.nvim_win_get_height(below)
                out[#out + 1] = vim.api.nvim_win_get_height(base) > 0
                out[#out + 1] = vim.api.nvim_win_get_height(follow_target) > 0
            end

            run_case(true, false)
            run_case(true, true)
            run_case(false, false)
            run_case(false, true)

            return out
        ]])

        Assert.table_eq("sizes preserved across follow-up splits", result, {
            3, 12, 5, true, true,
            3, 12, 5, true, true,
            3, 12, 5, true, true,
            3, 12, 5, true, true,
        })

        result = Assert.eval_block(backend, "nvim_open_win oversize requests are best effort", [[
            local current = vim.api.nvim_get_current_win()
            for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                if win ~= current then
                    vim.api.nvim_win_close(win, true)
                end
            end

            vim.cmd("enew!")
            local base = vim.api.nvim_get_current_win()
            local base_width = vim.api.nvim_win_get_width(base)
            local base_height = vim.api.nvim_win_get_height(base)

            local left = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "left",
                width = base_width * 2,
            })

            local above = vim.api.nvim_open_win(0, false, {
                win = base,
                split = "above",
                height = base_height * 2,
            })

            return {
                #vim.api.nvim_tabpage_list_wins(0),
                vim.api.nvim_win_get_width(left) < (base_width * 2),
                vim.api.nvim_win_get_width(left) > 0,
                vim.api.nvim_win_get_width(base) > 0,
                vim.api.nvim_win_get_height(above) < (base_height * 2),
                vim.api.nvim_win_get_height(above) > 0,
                vim.api.nvim_win_get_height(base) > 0,
            }
        ]])

        Assert.table_eq("oversize requests are clamped", result, {
            3, true, true, true, true, true, true,
        })

        result = Assert.eval_block(backend, "nvim_open_win width pressure follows equalalways semantics", [[
            local out = {}

            local function reset_to_single_window()
                local current = vim.api.nvim_get_current_win()
                for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                    if win ~= current then
                        vim.api.nvim_win_close(win, true)
                    end
                end
                vim.cmd("enew!")
            end

            local function run_case(equalalways)
                reset_to_single_window()

                local old_equalalways = vim.o.equalalways
                local old_winminwidth = vim.o.winminwidth
                local old_winwidth = vim.o.winwidth

                local ok, case = pcall(function()
                    vim.o.equalalways = equalalways
                    local base = vim.api.nvim_get_current_win()
                    local min_width = math.max(1, math.floor(vim.api.nvim_win_get_width(base) / 3))

                    vim.o.winwidth = math.max(old_winwidth, min_width)
                    vim.o.winminwidth = min_width

                    local left = vim.api.nvim_open_win(0, false, {
                        win = base,
                        split = "left",
                        width = min_width,
                    })

                    local split_ok, split_err = pcall(vim.api.nvim_open_win, 0, false, {
                        win = left,
                        split = "left",
                        width = min_width,
                    })

                    return {
                        split_ok,
                        tostring(split_err),
                        #vim.api.nvim_tabpage_list_wins(0),
                        vim.api.nvim_win_get_width(left),
                        vim.api.nvim_win_get_width(base),
                        min_width,
                    }
                end)

                vim.o.winminwidth = old_winminwidth
                vim.o.winwidth = old_winwidth
                vim.o.equalalways = old_equalalways

                if not ok then
                    error(case)
                end

                for i = 1, #case do
                    out[#out + 1] = case[i]
                end
            end

            run_case(true)
            run_case(false)

            return out
        ]])

        Assert.eq("width pressure with equalalways succeeds", result[1], true)
        Assert.eq("width pressure with equalalways creates third window", result[3], 3)
        Assert.eq("width pressure with equalalways keeps left above min width", result[4] >= result[6], true)
        Assert.eq("width pressure with equalalways keeps base above min width", result[5] >= result[6], true)
        Assert.eq("width pressure without equalalways fails", result[7], false)
        Assert.truthy("width pressure without equalalways reports E36", result[8]:find("E36", 1, true) ~= nil, result[8])
        Assert.eq("width pressure without equalalways keeps two windows", result[9], 2)
        Assert.eq("width pressure without equalalways keeps left above min width", result[10] >= result[12], true)

        result = Assert.eval_block(backend, "nvim_open_win height pressure fails in both equalalways modes", [[
            local out = {}

            local function reset_to_single_window()
                local current = vim.api.nvim_get_current_win()
                for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
                    if win ~= current then
                        vim.api.nvim_win_close(win, true)
                    end
                end
                vim.cmd("enew!")
            end

            local function run_case(equalalways)
                reset_to_single_window()

                local old_equalalways = vim.o.equalalways
                local old_winheight = vim.o.winheight
                local old_winminheight = vim.o.winminheight

                local ok, case = pcall(function()
                    vim.o.equalalways = equalalways
                    local base = vim.api.nvim_get_current_win()
                    local min_height = math.max(1, math.floor(vim.api.nvim_win_get_height(base) / 3))

                    vim.o.winheight = math.max(old_winheight, min_height)
                    vim.o.winminheight = min_height

                    local above = vim.api.nvim_open_win(0, false, {
                        win = base,
                        split = "above",
                        height = min_height,
                    })

                    local split_ok, split_err = pcall(vim.api.nvim_open_win, 0, false, {
                        win = above,
                        split = "above",
                        height = min_height,
                    })

                    return {
                        split_ok,
                        tostring(split_err),
                        #vim.api.nvim_tabpage_list_wins(0),
                        vim.api.nvim_win_get_height(above),
                        min_height,
                    }
                end)

                vim.o.winminheight = old_winminheight
                vim.o.winheight = old_winheight
                vim.o.equalalways = old_equalalways

                if not ok then
                    error(case)
                end

                for i = 1, #case do
                    out[#out + 1] = case[i]
                end
            end

            run_case(true)
            run_case(false)

            return out
        ]])

        Assert.eq("height pressure with equalalways fails", result[1], false)
        Assert.truthy("height pressure with equalalways reports E36", result[2]:find("E36", 1, true) ~= nil, result[2])
        Assert.eq("height pressure with equalalways keeps two windows", result[3], 2)
        Assert.eq("height pressure with equalalways keeps first split above min height", result[4] >= result[5], true)
        Assert.eq("height pressure without equalalways fails", result[6], false)
        Assert.truthy("height pressure without equalalways reports E36", result[7]:find("E36", 1, true) ~= nil, result[7])
        Assert.eq("height pressure without equalalways keeps two windows", result[8], 2)
        Assert.eq("height pressure without equalalways keeps first split above min height", result[9] >= result[10], true)
    end,
}
