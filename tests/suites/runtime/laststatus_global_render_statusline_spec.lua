return {
    id = "runtime.laststatus_global_render_statusline",
    description = "Ports global-statusline render smoke coverage on the real runtime render path; lua-editor-only because it asserts CCVim's tabpage rendering internals.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({ bootstrap_default_editor = true })

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")

            screen.width = 20
            screen.height = 8

            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 3, false, nil, nil, true)
            Options.set("statusline", "GLOBAL", false, nil, nil, true)

            local render_ok, render_err = pcall(function()
                tabpages[curtp]:render()
            end)

            Assert.eq("laststatus=3 render does not crash", render_ok, true)
            Assert.eq("laststatus=3 render error string stays empty", tostring(render_err or ""), "")
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
