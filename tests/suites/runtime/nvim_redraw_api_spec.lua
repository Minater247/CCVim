return {
    id = "runtime.nvim_redraw_api",
    description = "Validates window-targeted and global redraw flags for nvim__redraw.",
    supports = { lua_editor = true, headless_nvim = false },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local api = backend.mock.loadModule("lib.luaapi.api")
        local Decoration = backend.mock.loadModule("lib.decoration")

        local buf1 = backend.mock.create_buffer(1, "/tmp/redraw-api-1.txt", { "one" }, { refcount = 1 })
        local buf2 = backend.mock.create_buffer(2, "/tmp/redraw-api-2.txt", { "two" }, { refcount = 1 })

        local win1 = { winnr = 1, buffer = buf1, need_redraw = false }
        local win2 = { winnr = 2, buffer = buf2, need_redraw = false }
        windows[1] = win1
        windows[2] = win2
        curtp = 1
        curwin = 1

        local render_count = 0
        tabpages[1].windows = { win1, win2 }
        tabpages[1].render = function()
            render_count = render_count + 1
        end

        local function reset_flags()
            win1.need_redraw = false
            win2.need_redraw = false
            need_redraw = false
            what_redraw = {}
        end

        reset_flags()
        api.nvim__redraw({ win = win1.winnr, valid = false, flush = false })
        Assert.eq("target window marked", win1.need_redraw, true)
        Assert.eq("other window untouched", win2.need_redraw, false)
        Assert.eq("targeted redraw avoids global windows", what_redraw.windows, nil)
        Assert.eq("no flush render", render_count, 0)

        reset_flags()
        api.nvim__redraw({ buf = buf1.bufnr, valid = true, flush = false })
        Assert.eq("buffer redraw marks attached window", win1.need_redraw, true)
        Assert.eq("buffer redraw leaves other window", win2.need_redraw, false)

        reset_flags()
        api.nvim__redraw({ tabline = true, flush = false })
        Assert.eq("tabline marked", what_redraw.tabline, true)
        Assert.eq("tabline no windows flag", what_redraw.windows, nil)

        reset_flags()
        api.nvim__redraw({ statusline = true, win = win1.winnr, flush = false })
        Assert.eq("statusline target marked", win1.need_redraw, true)
        Assert.eq("statusline target leaves other", win2.need_redraw, false)

        reset_flags()
        api.nvim__redraw({ statusline = true, flush = false })
        Assert.eq("statusline global marks win1", win1.need_redraw, true)
        Assert.eq("statusline global marks win2", win2.need_redraw, true)

        reset_flags()
        api.nvim__redraw({})
        Assert.eq("flush default renders", render_count, 1)

        reset_flags()
        Decoration.begin_redraw()
        api.nvim__redraw({ win = win1.winnr, flush = true })
        Decoration.end_redraw()
        Assert.eq("flush suppressed during callbacks", render_count, 1)
        Assert.eq("target still marked", win1.need_redraw, true)
    end,
}
