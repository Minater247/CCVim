return {
    id = "runtime.syntax_insert_dirty",
    description = "Checks insert-mode edits dirty the edited syntax line during visible-range redraw.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Highlight = mock.loadModule("lib.highlight")
            local Syntax = mock.loadModule("lib.syntax")

            local buf = mock.create_buffer(1, "/tmp/syntax-insert-dirty.txt", { "", "", "" }, { modified = false })
            local win = mock.create_window(1, buf, { cursorx = 1, cursory = 2 })
            mock.create_tabpage(1, { win }, {})
            curtp = 1
            curwin = 1
            windows[1] = win

            Syntax.ExecuteCommand(win, "keyword Comment foo")
            Syntax.LinesToBlit(buf, 1, 3, win)

            win:insertText("foo")

            local blits = Syntax.LinesToBlit(buf, 1, 3, win)
            local comment_hl = Highlight.GetId("Comment")

            Assert.truthy("edited line has syntax blit", blits[2] ~= nil and blits[2].hl ~= nil)
            Assert.eq("edited second line is highlighted immediately", blits[2].hl[1], comment_hl)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
