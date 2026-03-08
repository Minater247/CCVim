return {
    id = "api.nvim_set_hl_roundtrip",
    description = "Ports backend-neutral nvim_set_hl/nvim_get_hl round-trip behavior for numeric, NONE, and RGB values.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nvim_set_hl roundtrip scenarios", [[
            vim.api.nvim_set_hl(0, "RoundtripPaletteNumeric", {
                fg = 15,
                bg = 0,
            })

            vim.api.nvim_set_hl(0, "RoundtripNoneBg", {
                fg = 15,
                bg = "NONE",
            })

            vim.api.nvim_set_hl(0, "RoundtripRgb", {
                fg = 0xFFFFFF,
                bg = 0x000000,
            })

            return {
                vim.api.nvim_get_hl(0, { name = "RoundtripPaletteNumeric", link = false }),
                vim.api.nvim_get_hl(0, { name = "RoundtripNoneBg", link = false }),
                vim.api.nvim_get_hl(0, { name = "RoundtripRgb", link = false }),
            }
        ]])

        Assert.eq("numeric fg round-trips", result[1].fg, 15)
        Assert.eq("numeric bg round-trips", result[1].bg, 0)
        Assert.eq("NONE bg keeps fg", result[2].fg, 15)
        Assert.eq("NONE bg remains unset", result[2].bg, nil)
        Assert.eq("rgb fg round-trips", result[3].fg, 0xFFFFFF)
        Assert.eq("rgb bg round-trips", result[3].bg, 0x000000)
    end,
}
