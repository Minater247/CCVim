return {
    id = "runtime.colorscheme_darkblue",
    description = "Loads the bundled darkblue colorscheme, keeps forced links, and reapplies the palette to the render back buffer.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "darkblue colorscheme load", [[
            local colors = _G.colors
            local Highlight = loadModule("lib.highlight")
            local Options = loadModule("lib.options")
            local FrameTree = loadModule("lib.frame")

            local function actual_group_color(name, which)
                local hl = Highlight.For(name, 0, true)
                local slot = which == "fg" and hl[1] or hl[2]
                local r, g, b = term.getPaletteColor(slot)
                return colors.packRGB(r, g, b)
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
            local apply_targets = {}
            local old_set_palette = Highlight.SetPalette
            Highlight.SetPalette = function(next_palette, target)
                apply_targets[#apply_targets + 1] = target
                return old_set_palette(next_palette, target)
            end
            tabpages[curtp]:render()
            Highlight.SetPalette = old_set_palette

            local normal = Highlight.For("Normal", 0, true)
            local backwin = tabpages[curtp]._backwin
            local _, text_x = win:textwidth()
            local frame_x, frame_y = FrameTree.GetXY(win.frame)
            return {
                vim.g.colors_name,
                vim.fn.execute("highlight CursorColumn"),
                vim.fn.execute("highlight Terminal"),
                actual_group_color("Normal", "bg"),
                actual_group_color("StatusLine", "fg"),
                actual_group_color("StatusLine", "bg"),
                apply_targets[#apply_targets] == backwin,
                frame_x,
                frame_y,
                text_x,
                colors.toBlit(normal[2]),
            }
        ]])

        local cells = backend.mock.term_cells()
        local blank_bg = cells[result[9]][result[8] + result[10] + 2].bg

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
        Assert.eq("tabpage render reapplies palette to back buffer", result[7], true)
        Assert.eq("rendered blank area uses Normal background", blank_bg, result[11])
    end,
}
