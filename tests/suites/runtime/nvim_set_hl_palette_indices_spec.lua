return {
    id = "runtime.nvim_set_hl_palette_indices",
    description = "Ports CCVim terminal-rendering behavior for palette-index highlights; lua-editor-only because the rendered 16-color palette choice is not exposed by headless Neovim's public API.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local Highlight = backend.mock.loadModule("lib.highlight")

        local result = Assert.eval_block(backend, "nvim_set_hl palette index scenarios", [[
            local colors = _G.colors

            term.getPaletteColor = function(idx)
                if idx == colors.white then
                    return 1, 1, 1
                end
                if idx == colors.black then
                    return 0, 0, 0
                end
                return 0.5, 0.5, 0.5
            end

            vim.api.nvim_set_hl(0, "RegressionPaletteNumeric", {
                fg = colors.white,
                bg = colors.black,
            })

            local pmenu_fg = vim.fn.synIDattr(vim.fn.hlID("Pmenu"), "fg")
            vim.api.nvim_set_hl(0, "RegressionFromSynIDattr", {
                fg = pmenu_fg,
                bg = "NONE",
            })

            vim.api.nvim_set_hl(0, "RegressionRgb", {
                fg = 0xFFFFFF,
                bg = 0x000000,
            })

            vim.api.nvim_set_hl(0, "Normal", {
                fg = colors.red,
                bg = colors.blue,
            })

            vim.api.nvim_set_hl(0, "RegressionInheritNormal", {
                fg = colors.white,
                bg = "NONE",
            })

            return {
                pmenu_fg,
            }
        ]])

        local direct = Highlight.For("RegressionPaletteNumeric", 0, true)
        local inherited = Highlight.For("RegressionFromSynIDattr", 0, true)
        local rgb_for = Highlight.For("RegressionRgb", 0, true)
        local inherit_raw = Highlight.For("RegressionInheritNormal", 0, true)
        local inherit_for = Highlight.For("RegressionInheritNormal", 0)
        local colors = _G.colors

        Assert.eq("direct numeric fg preserves white", direct[1], colors.white)
        Assert.eq("direct numeric bg preserves black", direct[2], colors.black)

        Assert.eq("synIDattr fg returns palette bit", type(result[1]), "number")
        Assert.eq("synIDattr-derived fg stays white", inherited[1], colors.white)
        Assert.eq("NONE background remains unset", inherited[2], nil)

        Assert.eq("rgb fg maps to white palette for rendering", rgb_for[1], colors.white)
        Assert.eq("rgb bg maps to black palette for rendering", rgb_for[2], colors.black)

        Assert.eq("raw NONE background remains unset", inherit_raw[2], nil)
        Assert.eq("resolved NONE background inherits Normal bg", inherit_for[2], colors.blue)
    end,
}
