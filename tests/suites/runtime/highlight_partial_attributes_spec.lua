return {
    id = "runtime.highlight_partial_attributes",
    description = "Keeps background-only highlight groups defined and implements NONE as a per-field reset.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "partial highlight attributes", [[
            local Highlight = loadModule("lib.highlight")

            vim.cmd("highlight PartialAttrs guifg=#112233 guibg=#445566")
            vim.cmd("highlight PartialAttrs guifg=NONE")
            local after_fg_clear = Highlight.RawFor("PartialAttrs")
            local after_fg_clear_fg = after_fg_clear[1]
            local after_fg_clear_bg = after_fg_clear[2]

            vim.cmd("highlight PartialAttrs guifg=#112233")
            vim.cmd("highlight PartialAttrs guibg=NONE")
            local after_bg_clear = Highlight.RawFor("PartialAttrs")
            local after_bg_clear_fg = after_bg_clear[1]
            local after_bg_clear_bg = after_bg_clear[2]

            vim.cmd("highlight BackgroundOnly guibg=#364143")
            local listing = vim.fn.execute("highlight BackgroundOnly")
            local background_only = Highlight.RawFor("BackgroundOnly")

            local names = Highlight.ListNames()
            for i = 1, #names do
                Highlight.Clear(names[i])
            end
            Highlight.SetHL(0, "Normal", { fg = 0xEEEEEE, bg = 0x111111 })
            Highlight.SetHL(0, "BackgroundOnly", { bg = 0x364143 })
            Highlight.BeginPaletteTracking()
            Highlight.CommitPaletteTracking()

            local palette = Highlight.GetPalette()
            local has_background = false
            for slot = 0, 15 do
                if palette[slot] == 0x364143 then
                    has_background = true
                    break
                end
            end

            return {
                after_fg_clear_fg,
                after_fg_clear_bg,
                after_bg_clear_fg,
                after_bg_clear_bg,
                listing,
                background_only[1],
                background_only[2],
                has_background,
            }
        ]])

        Assert.eq("guifg=NONE clears only foreground", result[1], nil)
        Assert.eq("guifg=NONE preserves background", result[2], 0x445566)
        Assert.eq("guibg=NONE preserves foreground", result[3], 0x112233)
        Assert.eq("guibg=NONE clears only background", result[4], nil)
        Assert.eq("background-only group is not listed as cleared", result[5]:find("cleared", 1, true), nil)
        Assert.eq("background-only group has no foreground", result[6], nil)
        Assert.eq("background-only group preserves background", result[7], 0x364143)
        Assert.eq("background-only color participates in palette selection", result[8], true)
    end,
}
