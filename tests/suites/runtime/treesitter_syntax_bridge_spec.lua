return {
    id = "runtime.treesitter_syntax_bridge",
    description = "Ports treesitter-to-syntax highlight bridging on CCVim's runtime render path; lua-editor-only because it asserts internal blit output.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")

            local Highlight = mock.loadModule("lib.highlight")
            local Treesitter = mock.loadModule("lib.luaapi.treesitter")
            local Syntax = mock.loadModule("lib.syntax")

            local line = "local value = 42"
            local buf = mock.create_buffer(1, "/tmp/test_ts_bridge.lua", { line }, { filetype = "lua", syntax = "" })
            local win = mock.create_window(1, buf, {})
            mock.create_tabpage(1, { win }, {})
            curtp = 1
            curwin = 1

            local function fg_char(blits)
                local normal = colors.toBlit(Highlight.For("Normal")[1])
                if not blits or not blits[1] or not blits[1].fg then
                    return normal
                end
                return blits[1].fg:sub(1, 1)
            end

            local normal_char = colors.toBlit(Highlight.For("Normal")[1])
            local keyword_char = colors.toBlit(Highlight.For("Keyword")[1])

            local before = Syntax.LinesToBlit(buf, 1, 1, win)
            Assert.eq("before start is normal", fg_char(before), normal_char)

            Treesitter.start(buf.bufnr, "lua")
            local with_ts = Syntax.LinesToBlit(buf, 1, 1, win)
            Assert.eq("after start is keyword", fg_char(with_ts), keyword_char)

            Treesitter.stop(buf.bufnr)
            local after_stop = Syntax.LinesToBlit(buf, 1, 1, win)
            Assert.eq("after stop returns to normal", fg_char(after_stop), normal_char)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
