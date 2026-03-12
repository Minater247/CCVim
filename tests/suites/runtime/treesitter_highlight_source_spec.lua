return {
    id = "runtime.treesitter_highlight_source",
    description = "Ports treesitter capture reporting and highlight-source changes on CCVim's runtime render path; lua-editor-only because it asserts internal render state.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local function find_capture(items, wanted)
                for i = 1, #items do
                    if items[i].capture == wanted then
                        return items[i]
                    end
                end
                return nil
            end

            local Highlight = mock.loadModule("lib.highlight")
            local Scopes = mock.loadModule("lib.luaapi.scopes")
            local Treesitter = mock.loadModule("lib.luaapi.treesitter")
            local Syntax = mock.loadModule("lib.syntax")
            local Runtime = mock.loadModule("lib.excmd.runtime")

            local line = "local function foo(x) return x + 1 end -- doc"
            local buf = mock.create_buffer(1, "/tmp/test_ts.lua", { line }, { filetype = "lua", syntax = "" })
            local win = mock.create_window(1, buf, {})
            mock.create_tabpage(1, { win }, {})
            curtp = 1
            curwin = 1

            local local_col = assert(string.find(line, "local", 1, true)) - 1
            local foo_col = assert(string.find(line, "foo", 1, true)) - 1
            local return_col = assert(string.find(line, "return", 1, true)) - 1

            local function fg_at_col(blits, lnum, col0)
                local normal = colors.toBlit(Highlight.For("Normal")[1])
                if not blits or not blits[lnum] or not blits[lnum].fg then
                    return normal
                end
                return blits[lnum].fg:sub(col0 + 1, col0 + 1)
            end

            local function bg_at_col(blits, lnum, col0)
                local normal = colors.toBlit(Highlight.For("Normal")[2])
                if not blits or not blits[lnum] or not blits[lnum].bg then
                    return normal
                end
                return blits[lnum].bg:sub(col0 + 1, col0 + 1)
            end

            local before = Syntax.LinesToBlit(buf, 1, 1, win)
            local before_local = fg_at_col(before, 1, local_col)

            Treesitter.start(buf.bufnr, "lua")
            Assert.eq("b:ts_highlight enabled", Scopes._b_by_buf[buf.bufnr].ts_highlight, 1)
            Assert.truthy("highlighter active", Treesitter.highlighter.active[buf.bufnr] ~= nil)

            local caps_local = Treesitter.get_captures_at_pos(buf.bufnr, 0, local_col)
            local caps_foo = Treesitter.get_captures_at_pos(buf.bufnr, 0, foo_col)
            local caps_return = Treesitter.get_captures_at_pos(buf.bufnr, 0, return_col)

            local c_local = find_capture(caps_local, "keyword")
            local c_foo = find_capture(caps_foo, "function")
            local c_return = find_capture(caps_return, "keyword.return")

            Assert.truthy("local capture exists", c_local ~= nil)
            Assert.truthy("foo capture exists", c_foo ~= nil)
            Assert.truthy("return capture exists", c_return ~= nil)
            Assert.eq("capture lang", c_local.lang, "lua")
            Assert.truthy("capture id > 0", type(c_local.id) == "number" and c_local.id > 0)

            local after_start = Syntax.LinesToBlit(buf, 1, 1, win)
            local keyword_blit = colors.toBlit(Highlight.For("Keyword")[1])
            local function_blit = colors.toBlit(Highlight.For("Function")[1])

            Assert.eq("local becomes keyword after start", fg_at_col(after_start, 1, local_col), keyword_blit)
            Assert.eq("foo becomes function after start", fg_at_col(after_start, 1, foo_col), function_blit)
            Assert.truthy("start changed color from baseline", fg_at_col(after_start, 1, local_col) ~= before_local)

            local ok_run, err_run = Runtime.run([[
                colorscheme default
                colorscheme elflord
                colorscheme darkblue
            ]])
            Assert.eq("colorscheme sequence runs", ok_run, true, err_run)

            local after_schemes = Syntax.LinesToBlit(buf, 1, 1, win)
            local normal_bg = colors.toBlit(Highlight.For("Normal")[2])

            Assert.eq(
                "treesitter capture background follows Normal after repeated colorscheme loads",
                bg_at_col(after_schemes, 1, local_col),
                normal_bg
            )

            Treesitter.stop(buf.bufnr)
            Assert.eq("highlighter inactive", Treesitter.highlighter.active[buf.bufnr], nil)

            local after_stop = Syntax.LinesToBlit(buf, 1, 1, win)
            Assert.eq(
                "local returns to current Normal after stop",
                fg_at_col(after_stop, 1, local_col),
                colors.toBlit(Highlight.For("Normal")[1])
            )
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
