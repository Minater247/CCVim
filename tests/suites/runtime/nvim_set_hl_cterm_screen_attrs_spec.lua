return {
    id = "runtime.nvim_set_hl_cterm_screen_attrs",
    description = "Checks that cterm highlight fields flow through to screen attrs and default colors for the local runtime.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "cterm attrs reach screen state", [[
            local Highlight = loadModule("lib.highlight")

            vim.api.nvim_set_hl(0, "Normal", {
                fg = 0x102030,
                bg = 0x405060,
                ctermfg = 196,
                ctermbg = 16,
            })

            vim.api.nvim_set_hl(0, "InheritedCtermBg", {
                fg = 0x112233,
            })

            vim.api.nvim_set_hl(0, "ExplicitCterm", {
                ctermfg = 202,
                ctermbg = 17,
            })

            local normal_id = Highlight.GetId("Normal", 0)
            local inherit_id = Highlight.GetId("InheritedCtermBg", 0)
            local explicit_id = Highlight.GetId("ExplicitCterm", 0)

            return {
                screen.hl_attrs(0),
                screen.hl_attrs(normal_id),
                screen.hl_attrs(inherit_id),
                screen.hl_attrs(explicit_id),
            }
        ]])

        Assert.eq("default rgb fg syncs from Normal", result[1].foreground, 0x102030)
        Assert.eq("default rgb bg syncs from Normal", result[1].background, 0x405060)
        Assert.eq("default cterm fg syncs from Normal", result[1].cterm_foreground, 196)
        Assert.eq("default cterm bg syncs from Normal", result[1].cterm_background, 16)

        Assert.eq("Normal screen attr rgb fg", result[2].foreground, 0x102030)
        Assert.eq("Normal screen attr rgb bg", result[2].background, 0x405060)
        Assert.eq("Normal screen attr cterm fg", result[2].cterm_foreground, 196)
        Assert.eq("Normal screen attr cterm bg", result[2].cterm_background, 16)

        Assert.eq("missing cterm fg inherits Normal default", result[3].cterm_foreground, 196)
        Assert.eq("missing cterm bg inherits Normal default", result[3].cterm_background, 16)
        Assert.eq("explicit rgb fg is preserved", result[3].foreground, 0x112233)
        Assert.eq("missing rgb bg inherits Normal default", result[3].background, 0x405060)

        Assert.eq("explicit cterm fg reaches screen attrs", result[4].cterm_foreground, 202)
        Assert.eq("explicit cterm bg reaches screen attrs", result[4].cterm_background, 17)
        Assert.eq("cterm-only attrs do not fabricate rgb fg", result[4].foreground, 0x102030)
        Assert.eq("cterm-only attrs do not fabricate rgb bg", result[4].background, 0x405060)
    end,
}
