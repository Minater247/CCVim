return {
    id = "runtime.nvim_set_hl_palette_indices",
    description = "Checks that raw palette-style numbers are preserved at the API surface while the renderer resolves them to RGB.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local Highlight = backend.mock.loadModule("lib.highlight")
        local globals = backend.mock.globals()
        local function palette_rgb(slot)
            local r, g, b = globals.screen.get_palette_slot(slot)
            return r * 65536 + g * 256 + b
        end

        local result = Assert.eval_block(backend, "nvim_set_hl palette index scenarios", [[
            local colors = _G.colors

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
                vim.api.nvim_get_hl(0, { name = "RegressionPaletteNumeric", link = false }),
                vim.api.nvim_get_hl(0, { name = "RegressionFromSynIDattr", link = false }),
                vim.api.nvim_get_hl(0, { name = "RegressionRgb", link = false }),
                vim.api.nvim_get_hl(0, { name = "RegressionInheritNormal", link = false }),
            }
        ]])

        local direct = Highlight.For("RegressionPaletteNumeric", 0, true)
        local inherited = Highlight.For("RegressionFromSynIDattr", 0, true)
        local rgb_for = Highlight.For("RegressionRgb", 0, true)
        local inherit_raw = Highlight.For("RegressionInheritNormal", 0, true)
        local inherit_for = Highlight.For("RegressionInheritNormal", 0)
        local colors = _G.colors

        Assert.eq("direct numeric fg resolves through the active palette", direct[1], palette_rgb(0))
        Assert.eq("direct numeric bg resolves through the active palette", direct[2], palette_rgb(15))
        Assert.table_eq("nvim_get_hl preserves direct numeric values", result[2], {
            fg = colors.white,
            bg = colors.black,
        })

        Assert.eq("synIDattr fg matches headless empty string", result[1], "")
        Assert.table_eq("synIDattr-derived empty fg does not materialize colors", result[3], {})
        Assert.eq("synIDattr-derived fg stays unset", inherited[1], nil)
        Assert.eq("NONE background remains unset", inherited[2], nil)

        Assert.table_eq("nvim_get_hl keeps rgb values", result[4], {
            fg = 0xFFFFFF,
            bg = 0x000000,
        })
        Assert.eq("rgb fg stays rgb for rendering", rgb_for[1], 0xFFFFFF)
        Assert.eq("rgb bg stays rgb for rendering", rgb_for[2], 0x000000)

        Assert.table_eq("nvim_get_hl keeps explicit fg with NONE bg omitted", result[5], {
            fg = colors.white,
        })
        Assert.eq("raw NONE background remains unset", inherit_raw[2], nil)
        Assert.eq("resolved NONE background inherits Normal bg", inherit_for[2], palette_rgb(11))
    end,
}
