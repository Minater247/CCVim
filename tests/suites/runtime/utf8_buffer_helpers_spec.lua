return {
    id = "runtime.utf8_buffer_helpers",
    description = "Ports UTF-8 buffer helper behavior on the real CCVim buffer/window objects; lua-editor-only because it exercises internal buffer methods directly.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({ bootstrap_default_editor = false })

        local ok, err = pcall(function()
            local Utf8 = loadModule("lib.utf8")

            local buf = mock.create_buffer(1, "/tmp/utf8.txt", { "aé✓", "\té" })
            local win = mock.create_window(1, buf, {})
            win.cursory = 1
            win.cursorx = 1
            mock.create_tabpage(1, { win }, {})
            curtp = 1
            curwin = 1

            Assert.eq("Utf8.len counts codepoints", Utf8.len("aé✓"), 3)
            Assert.eq("line_len counts codepoints", buf:line_len(1, true), 3)
            Assert.eq("line_sub keeps utf8 character boundaries", buf:line_sub(1, 2, 2, true), "é")
            Assert.eq("line_byte_index maps char col to byte index", buf:line_byte_index(1, 3, true, true), 4)
            Assert.eq("Utf8.col_from_byte maps byte index to char col", Utf8.col_from_byte(buf:get_line(1, true), 4, true), 3)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
