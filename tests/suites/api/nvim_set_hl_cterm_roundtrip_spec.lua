return {
    id = "api.nvim_set_hl_cterm_roundtrip",
    description = "Checks that nvim_set_hl/nvim_get_hl preserve cterm color fields independently from RGB fields.", -- luacheck: ignore 631

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "nvim_set_hl cterm roundtrip scenarios", [[
            vim.api.nvim_set_hl(0, "RoundtripCtermOnly", {
                ctermfg = 196,
                ctermbg = 16,
            })

            vim.api.nvim_set_hl(0, "RoundtripRgbAndCterm", {
                fg = 0x112233,
                bg = 0x445566,
                ctermfg = 202,
                ctermbg = 17,
            })

            return {
                vim.api.nvim_get_hl(0, { name = "RoundtripCtermOnly", link = false }),
                vim.api.nvim_get_hl(0, { name = "RoundtripRgbAndCterm", link = false }),
            }
        ]])

        Assert.eq("cterm-only fg round-trips", result[1].ctermfg, 196)
        Assert.eq("cterm-only bg round-trips", result[1].ctermbg, 16)
        Assert.eq("cterm-only fg omits rgb", result[1].fg, nil)
        Assert.eq("cterm-only bg omits rgb", result[1].bg, nil)

        Assert.eq("mixed rgb fg round-trips", result[2].fg, 0x112233)
        Assert.eq("mixed rgb bg round-trips", result[2].bg, 0x445566)
        Assert.eq("mixed cterm fg round-trips", result[2].ctermfg, 202)
        Assert.eq("mixed cterm bg round-trips", result[2].ctermbg, 17)
    end,
}
