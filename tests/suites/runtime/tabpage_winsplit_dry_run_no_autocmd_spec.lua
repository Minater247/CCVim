return {
    id = "runtime.tabpage_winsplit_dry_run_no_autocmd",
    description = "Ports internal Tabpage dry-run split behavior; lua-editor-only because it probes Tabpage internals directly.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({
            module_stubs = {
                ["lib.autocmd"] = {
                    Run = function(event, evt_ctx)
                        _G.__tabpage_autocmd_calls = _G.__tabpage_autocmd_calls or {}
                        _G.__tabpage_autocmd_calls[#_G.__tabpage_autocmd_calls + 1] = {
                            event = event,
                            ctx = evt_ctx or {},
                        }
                        return 0
                    end,
                },
            },
        })

        local ok, err = pcall(function()
            _G.__tabpage_autocmd_calls = {}
            screen.width = 20
            screen.height = 8

            local Options = mock.loadModule("lib.options")
            local tab1 = tabpages[curtp]
            local win1 = windows[curwin]
            tab1:updateFrameview()

            Options.set("winminwidth", 1, false, nil, nil, true)
            Options.set("winminheight", 1, false, nil, nil, true)

            do
                local before_calls = #_G.__tabpage_autocmd_calls
                local before_root = tab1.tree
                local before_children = #tab1.windows
                local before_winnr = curwin

                local probe = tab1:MakeSplitProbe(win1)
                local split_ok = tab1:WinSplit(0, probe, true, { dry_run = true })
                Assert.eq("feasible dry-run succeeds", split_ok, true)
                Assert.eq("dry-run emits no autocmd", #_G.__tabpage_autocmd_calls, before_calls)
                Assert.eq("dry-run keeps same root", tab1.tree, before_root)
                Assert.eq("dry-run keeps same window count", #tab1.windows, before_children)
                Assert.eq("dry-run keeps current window", curwin, before_winnr)
            end

            do
                local before_calls = #_G.__tabpage_autocmd_calls
                local before_root = tab1.tree
                local before_children = #tab1.windows
                local before_winnr = curwin

                Options.set("winminwidth", 20, false, nil, nil, true)
                local probe = tab1:MakeSplitProbe(win1)
                local split_ok = tab1:WinSplit(0, probe, true, { dry_run = true })
                Assert.eq("infeasible dry-run fails", split_ok, false)
                Assert.eq("failed dry-run emits no autocmd", #_G.__tabpage_autocmd_calls, before_calls)
                Assert.eq("failed dry-run keeps same root", tab1.tree, before_root)
                Assert.eq("failed dry-run keeps same window count", #tab1.windows, before_children)
                Assert.eq("failed dry-run keeps current window", curwin, before_winnr)
                Assert.truthy("original window still framed", win1.frame == tab1.tree, "frame detached unexpectedly")
            end
        end)

        mock.cleanup()
        _G.__tabpage_autocmd_calls = nil

        if not ok then
            error(err)
        end
    end,
}
