return {
    id = "runtime.treesitter_syntax_bridge",
    description = "Ports treesitter-to-syntax highlight bridging on CCVim's runtime render path; lua-editor-only because it asserts internal blit output.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Highlight = mock.loadModule("lib.highlight")
            local Treesitter = mock.loadModule("lib.luaapi.treesitter")
            local Syntax = mock.loadModule("lib.syntax")

            local line = "local value = 42"
            local buf = mock.create_buffer(1, "/tmp/test_ts_bridge.lua", { line }, { filetype = "lua", syntax = "" })
            local win = mock.create_window(1, buf, {})
            mock.create_tabpage(1, { win }, {})
            curtp = 1
            curwin = 1

            local function hl_at_start(blits)
                local normal = Highlight.GetId("Normal")
                if not blits or not blits[1] or not blits[1].hl then
                    return normal
                end
                return blits[1].hl[1]
            end

            local normal_hl = Highlight.GetId("Normal")
            local keyword_hl = Highlight.GetId("Keyword")

            local before = Syntax.LinesToBlit(buf, 1, 1, win)
            Assert.eq("before start is normal", hl_at_start(before), normal_hl)

            Treesitter.start(buf.bufnr, "lua")
            local with_ts = Syntax.LinesToBlit(buf, 1, 1, win)
            Assert.eq("after start is keyword", hl_at_start(with_ts), keyword_hl)

            Treesitter.stop(buf.bufnr)
            local after_stop = Syntax.LinesToBlit(buf, 1, 1, win)
            Assert.eq("after stop returns to normal", hl_at_start(after_stop), normal_hl)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
