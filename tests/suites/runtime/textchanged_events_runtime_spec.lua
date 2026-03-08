return {
    id = "runtime.textchanged_events",
    description = "Ports TextChanged and TextChangedI dispatch behavior on the real buffer/autocmd runtime path; lua-editor-only because it currently depends on CCVim's direct buffer mutation path and mode flag rather than a backend-neutral public edit driver.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            _G.options = Options

            local Autocmd = mock.loadModule("lib.autocmd")
            local buf = windows[curwin].buffer
            buf.name = "/tmp/textchanged.txt"
            buf.lines = { "x" }
            buf.loaded = true

            local normal_count, insert_count = 0, 0
            local normal_buf, insert_buf = nil, nil

            Autocmd.CreateAutocommand({ "TextChanged" }, { "*" }, function(info)
                normal_count = normal_count + 1
                normal_buf = info.bufnr
            end, nil, 1, false, false, nil, nil)

            Autocmd.CreateAutocommand({ "TextChangedI" }, { "*" }, function(info)
                insert_count = insert_count + 1
                insert_buf = info.bufnr
            end, nil, 1, false, false, nil, nil)

            _G.vimmode = "normal"
            buf:set_line(1, "normal-change")

            _G.vimmode = "insert"
            buf:set_line(1, "insert-change")

            Assert.eq("TextChanged fired once", normal_count, 1)
            Assert.eq("TextChangedI fired once", insert_count, 1)
            Assert.eq("TextChanged bufnr", normal_buf, buf.bufnr)
            Assert.eq("TextChangedI bufnr", insert_buf, buf.bufnr)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
