return {
    id = "runtime.texren_utf8_ascii",
    description = "Ports UTF-8 fallback rendering through CCVim's text renderer; lua-editor-only because it asserts internal renderer output.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            _G.options = Options

            local Tab = mock.loadModule("lib.tab")
            local TexRen = mock.loadModule("lib.texren")

            local buf = mock.create_buffer(1, "/tmp/texren-utf8.txt", { "" })
            local params = {
                wraplen = 0,
                wordwrap = false,
                tabcfg = Tab.get_tab_config(buf),
            }

            do
                local lines = TexRen.parse("é", params)
                Assert.eq("utf8 latin-1 fallback", lines[1], "?")
            end

            do
                local lines = TexRen.parse("✓", params)
                Assert.eq("utf8 checkmark fallback", lines[1], "v")
            end

            do
                local lines = TexRen.parse("aé", params)
                Assert.eq("mixed ascii/utf8 fallback", lines[1], "a?")
            end

            do
                local lines, _, pos = TexRen.parse("aé", params, 2)
                Assert.eq("bytepos maps to second cell", pos.column, 2)
                Assert.eq("bytepos character maps through fallback", pos.ch, "?")
                Assert.eq("bytepos line", pos.line, 1)
                Assert.eq("rendered line", lines[1], "a?")
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
