return {
    id = "runtime.normal_screen_bottom",
    description = "Checks L and counted L against the bottom displayed row with wrapped and unwrapped text",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")
        local mock = MockEnv.setup({ term_width = 20, term_height = 8 })

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            local Event = mock.loadModule("lib.event")
            local Key = mock.loadModule("lib.key")

            Event.LoadCommandModule()
            mock.loadModule("lib.mappings", { immediate = true })
            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("number", false, false, nil, nil, true)
            Options.set("relativenumber", false, false, nil, nil, true)
            Options.set("signcolumn", "no", false, nil, nil, true)

            local win = windows[curwin]
            local lines = {}
            for i = 1, 30 do lines[i] = "line " .. i end
            win.buffer.lines = lines
            win.buffer.loaded = true
            win.scrolly = { 5, 0 }
            win:_set_cursor_raw(5, 1)

            local function feed(text)
                local seq = Key.strtoseq(text)
                for i = 1, #seq do Event.ProcessEvent({ "key", seq[i].numeric }) end
            end

            local height = win:textheight()
            feed("L")
            Assert.eq("L reaches the last displayed line", win.cursory, 5 + height - 1)

            win.scrolly = { 5, 0 }
            win:_set_cursor_raw(5, 1)
            feed("2L")
            Assert.eq("2L reaches the second line from the bottom", win.cursory, 5 + height - 2)

            Options.set("wrap", true, true, win, win.buffer)
            win.buffer.lines = {
                string.rep("a", 50),
                string.rep("b", 50),
                string.rep("c", 50),
                string.rep("d", 50),
            }
            win.scrolly = { 1, 0 }
            win:_set_cursor_raw(1, 1)
            feed("L")
            Assert.eq("L reaches the last displayed wrapped row", win:cursorScreenRow(), height - 1)
        end)

        mock.cleanup()
        if not ok then error(err) end
    end,
}
