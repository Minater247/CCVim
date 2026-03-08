return {
    id = "runtime.menu_commands_runtime",
    description = "Ports menu command runtime behavior through real menu commands and menu_info().",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "menu command runtime", [[
            local prefix = "CodexMenuRuntime"

            local function capture(cmd)
                local ok, err = pcall(vim.cmd, cmd)
                if ok then
                    return { true, nil }
                end
                return { false, tostring(err or "") }
            end

            local function menu_info(path, modes)
                return vim.fn.eval(string.format("menu_info(%q, %q)", path, modes))
            end

            capture("aunmenu " .. prefix)
            capture("tunmenu ToolBar")
            capture("menutrans clear")

            vim.cmd("menut Foo Baz")
            vim.cmd("amenu Foo.Action :let g:menu_exec = 42<CR>")
            local disable_translated = capture("amenu disable Baz.*")
            local disabled = menu_info("Foo.Action", "a")
            local enable_menu = capture("amenu enable Foo.Action")
            local enabled = menu_info("Foo.Action", "a")

            vim.cmd("tmenu ToolBar.Open Open\\ file")
            local tooltip_before = menu_info("ToolBar.Open", "t")
            capture("tunmenu ToolBar")
            local tooltip_after = menu_info("ToolBar.Open", "t")

            vim.cmd("emenu Foo.Action")

            local abbrev_cases = {
                { "an", prefix .. ".Abbrev.An" },
                { "me", prefix .. ".Abbrev.Me" },
                { "noreme", prefix .. ".Abbrev.Nore" },
                { "unme", prefix .. ".Abbrev.Me" },
                { "cme", prefix .. ".Abbrev.C" },
                { "cnoreme", prefix .. ".Abbrev.Cnore" },
                { "ime", prefix .. ".Abbrev.I" },
                { "inoreme", prefix .. ".Abbrev.Inore" },
                { "nme", prefix .. ".Abbrev.N" },
                { "nnoreme", prefix .. ".Abbrev.Nnore" },
                { "onoreme", prefix .. ".Abbrev.O" },
                { "snoreme", prefix .. ".Abbrev.S" },
                { "vme", prefix .. ".Abbrev.V" },
                { "vnoreme", prefix .. ".Abbrev.Vnore" },
                { "xme", prefix .. ".Abbrev.X" },
                { "xnoreme", prefix .. ".Abbrev.Xnore" },
                { "tm", prefix .. ".Abbrev.TTip" },
                { "tln", prefix .. ".Abbrev.Tl" },
                { "tlu", prefix .. ".Abbrev.Tl" },
                { "menut", "Alpha Omega" },
                { "menutrans", "Beta Gamma" },
            }

            local abbrev_results = {}
            for i = 1, #abbrev_cases do
                local abbr = abbrev_cases[i][1]
                local arg = abbrev_cases[i][2]
                local ok
                if abbr == "tm" then
                    ok = capture(abbr .. " " .. arg .. " Tip")[1]
                elseif abbr == "tln" then
                    ok = capture(abbr .. " " .. arg .. " :let g:tl=1<CR>")[1]
                elseif abbr == "tlu" then
                    ok = capture(abbr .. " " .. arg)[1]
                elseif abbr == "unme" then
                    capture("amenu " .. arg .. " :let g:tmp=1<CR>")
                    ok = capture(abbr .. " " .. arg)[1]
                elseif abbr == "menut" or abbr == "menutrans" then
                    ok = capture(abbr .. " " .. arg)[1]
                else
                    ok = capture(abbr .. " " .. arg .. " :let g:abbr=" .. i .. "<CR>")[1]
                end
                abbrev_results[i] = { abbr, ok }
            end

            return {
                menu_exec = vim.g.menu_exec,
                disable_translated = disable_translated,
                enable_menu = enable_menu,
                disabled = disabled,
                enabled = enabled,
                tooltip_before = tooltip_before,
                tooltip_after = tooltip_after,
                abbrev_results = abbrev_results,
            }
        ]])

        Assert.eq("menu action executed via emenu", result.menu_exec, 42)
        Assert.eq("translated disable succeeds", result.disable_translated[1], true)
        Assert.eq("enable succeeds", result.enable_menu[1], true)
        Assert.eq("translated disable marks menu disabled", result.disabled.enabled, false)
        Assert.eq("enable restores menu", result.enabled.enabled, true)
        Assert.eq("menu rhs preserved", result.enabled.rhs, ":let g:menu_exec = 42<CR>")
        Assert.eq("tooltip text stored", result.tooltip_before.rhs, "Open\\ file")
        Assert.truthy("tooltip removed by tunmenu", backend:is_empty_dict(result.tooltip_after), result.tooltip_after)

        for i = 1, #result.abbrev_results do
            local row = result.abbrev_results[i]
            Assert.eq("menu abbreviation " .. row[1], row[2], true)
        end
    end,
}
