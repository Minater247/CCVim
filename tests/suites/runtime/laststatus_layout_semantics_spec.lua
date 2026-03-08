return {
    id = "runtime.laststatus_layout_semantics",
    description = "Ports laststatus layout sizing and dry-run split semantics on the real tabpage/window runtime objects.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({
            module_stubs = {
                ["lib.autocmd"] = {
                    Run = function(event, evt_ctx)
                        _G.__laststatus_autocmd_calls = _G.__laststatus_autocmd_calls or {}
                        _G.__laststatus_autocmd_calls[#_G.__laststatus_autocmd_calls + 1] = {
                            event = event,
                            ctx = evt_ctx or {},
                        }
                        return 0
                    end,
                },
            },
        })

        local ok, err = pcall(function()
            _G.__laststatus_autocmd_calls = {}
            screen.width = 20
            screen.height = 6

            local Options = mock.loadModule("lib.options")
            _G.options = Options

            local tab1 = tabpages[curtp]
            local win1 = windows[curwin]

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 1, false, nil, nil, true)
            Options.set("winminwidth", 1, false, nil, nil, true)
            Options.set("winminheight", 1, false, nil, nil, true)

            Options.set("laststatus", 3, false, nil, nil, true)
            tab1:updateFrameview()
            Assert.eq("laststatus=3 reserves one global statusline row", tab1.tree.height, 4)

            Options.set("laststatus", 2, false, nil, nil, true)
            tab1:updateFrameview()
            Assert.eq("laststatus=2 uses full non-cmdheight area", tab1.tree.height, 5)

            screen.height = 4
            Options.set("laststatus", 3, false, nil, nil, true)
            tab1:updateFrameview()
            Assert.eq("laststatus=3 recomputes reduced layout height", tab1.tree.height, 2)

            do
                local before_calls = #_G.__laststatus_autocmd_calls
                local probe = tab1:MakeSplitProbe(win1)
                local split_ok = tab1:WinSplit(0, probe, false, { dry_run = true })
                Assert.eq("split dry-run fails with global statusline when separator would consume text row", split_ok, false)
                Assert.eq("dry-run emits no autocmd for ls=3", #_G.__laststatus_autocmd_calls, before_calls)
            end

            Options.set("laststatus", 2, false, nil, nil, true)
            tab1:updateFrameview()
            Assert.eq("laststatus=2 recomputes larger frame height", tab1.tree.height, 3)

            do
                local before_calls = #_G.__laststatus_autocmd_calls
                local probe = tab1:MakeSplitProbe(win1)
                local split_ok = tab1:WinSplit(0, probe, false, { dry_run = true })
                Assert.eq("split dry-run fails when local statuslines leave no text row", split_ok, false)
                Assert.eq("dry-run emits no autocmd for ls=2", #_G.__laststatus_autocmd_calls, before_calls)
            end
        end)

        mock.cleanup()
        _G.__laststatus_autocmd_calls = nil

        if not ok then
            error(err)
        end
    end,
}
