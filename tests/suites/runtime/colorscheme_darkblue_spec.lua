return {
    id = "runtime.colorscheme_darkblue",
    description = "Loads the bundled darkblue colorscheme, keeps forced links, and renders using the resolved RGB highlights.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "darkblue colorscheme load", [[
            local Highlight = loadModule("lib.highlight")
            local Options = loadModule("lib.options")
            local FrameTree = loadModule("lib.frame")

            local function actual_group_color(name, which)
                local hl = Highlight.For(name, 0, true)
                return which == "fg" and hl[1] or hl[2]
            end

            screen.width = 16
            screen.height = 6
            Options.set("cmdheight", 1, false, nil, nil, true)
            Options.set("showtabline", 0, false, nil, nil, true)
            Options.set("laststatus", 0, false, nil, nil, true)
            Options.set("number", false, false, nil, nil, true)
            Options.set("relativenumber", false, false, nil, nil, true)
            Options.set("linebreak", false, false, nil, nil, true)
            Options.set("wrap", false, false, nil, nil, true)
            Options.set("signcolumn", "no", false, nil, nil, true)

            local win = windows[curwin]
            local buf = win.buffer
            buf.name = "/tmp/darkblue-render.txt"
            buf.lines = { "abc" }
            buf.loaded = true

            vim.cmd.colorscheme("darkblue")
            tabpages[curtp]:render()

            local normal = Highlight.For("Normal", 0, true)
            local _, text_x = win:textwidth()
            local frame_x, frame_y = FrameTree.GetXY(win.frame)
            return {
                vim.g.colors_name,
                vim.fn.execute("highlight CursorColumn"),
                vim.fn.execute("highlight Terminal"),
                actual_group_color("Normal", "bg"),
                actual_group_color("StatusLine", "fg"),
                actual_group_color("StatusLine", "bg"),
                frame_x,
                frame_y,
                text_x,
                normal[2],
            }
        ]])

        local cells = backend.mock.term_cells()
        local blank_bg = cells[result[8]][result[7] + result[9] + 2].bg
        local globals = backend.mock.globals()
        local blank_r, blank_g, blank_b = globals.term.getPaletteColor(globals.colors.fromBlit(blank_bg))
        local blank_bg_rgb = globals.colors.packRGB(blank_r, blank_g, blank_b)

        Assert.eq("darkblue becomes active", result[1], "darkblue")
        Assert.truthy(
            "CursorColumn keeps forced link",
            type(result[2]) == "string" and result[2]:find("links to CursorLine", 1, true) ~= nil,
            result[2]
        )
        Assert.truthy(
            "Terminal keeps forced link",
            type(result[3]) == "string" and result[3]:find("links to Normal", 1, true) ~= nil,
            result[3]
        )
        Assert.eq("darkblue Normal background stays deep blue", result[4], 0x000040)
        Assert.eq("darkblue StatusLine foreground stays deep blue", result[5], 0x000040)
        Assert.eq("darkblue StatusLine background stays light gray", result[6], 0xC0C0C0)
        Assert.eq("rendered blank area uses Normal background", blank_bg_rgb, result[10])
    end,
}
