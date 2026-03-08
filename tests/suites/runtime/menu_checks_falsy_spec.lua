return {
    id = "runtime.menu_checks_falsy",
    description = "Ports menu command falsy/error regressions through real ex commands on both backends.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "menu falsy-check regressions", [[
            local prefix = "CodexMenuSpec"

            local function capture(cmd)
                local ok, err = pcall(vim.cmd, cmd)
                if ok then
                    return { true, nil }
                end
                return { false, tonumber(tostring(err or ""):match("E(%d+):")) }
            end

            return {
                capture("amenu " .. prefix .. ".One.Two :let g:v=1<CR>"),
                capture("amenu disable " .. prefix .. ".One.*"),
                capture("amenu disable " .. prefix .. ".Missing.*"),
                capture("amenu disable ."),
                capture("aunmenu " .. prefix .. ".Missing"),
                capture("aunmenu ."),
                capture("tmenu " .. prefix .. ".One.Two.Three Tip"),
                capture("tunmenu " .. prefix .. ".One.*"),
                capture("tunmenu *"),
                capture("tunmenu ."),
                capture("emenu " .. prefix .. ".Missing.Menu"),
                capture("amenu <unique> " .. prefix .. ".Unique.Menu :let g:u=1<CR>"),
                capture("amenu <unique> " .. prefix .. ".Unique.Menu :let g:u=2<CR>"),
                capture("amenu " .. prefix .. ".Unique.Menu :let g:u=3<CR>"),
            }
        ]])

        Assert.eq("define menu succeeds", result[1][1], true)
        Assert.eq("disable existing wildcard succeeds", result[2][1], true)

        Assert.eq("disable missing wildcard errors", result[3][1], false)
        Assert.eq("disable missing wildcard code", result[3][2], 329)

        Assert.eq("disable invalid path errors", result[4][1], false)
        Assert.eq("disable invalid path code", result[4][2], 475)

        Assert.eq("unmenu missing errors", result[5][1], false)
        Assert.eq("unmenu missing code", result[5][2], 329)

        Assert.eq("unmenu invalid path errors", result[6][1], false)
        Assert.eq("unmenu invalid path code", result[6][2], 475)

        Assert.eq("tooltip define errors on non-submenu path", result[7][1], false)
        Assert.eq("tooltip define error code", result[7][2], 327)

        Assert.eq("tooltip wildcard segment errors", result[8][1], false)
        Assert.eq("tooltip wildcard segment code", result[8][2], 329)

        Assert.eq("tooltip clear all succeeds", result[9][1], true)

        Assert.eq("tooltip invalid path errors", result[10][1], false)
        Assert.eq("tooltip invalid path code", result[10][2], 475)

        Assert.eq("emenu missing errors", result[11][1], false)
        Assert.eq("emenu missing code", result[11][2], 334)

        Assert.eq("unique define errors on menu-bar path", result[12][1], false)
        Assert.eq("unique define error code", result[12][2], 331)

        Assert.eq("second unique define keeps same error", result[13][1], false)
        Assert.eq("second unique define error code", result[13][2], 331)

        Assert.eq("non-unique overwrite succeeds", result[14][1], true)
    end,
}
