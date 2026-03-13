return {
    id = "api.synidattr_color_modes",
    description = "Checks that synIDattr() follows Neovim's gui/cterm color mode selection semantics.",

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_block(backend, "synIDattr gui and cterm color modes", [[
            vim.o.termguicolors = false
            vim.api.nvim_set_hl(0, "RgbOnly", {
                fg = 0x112233,
                bg = 0x445566,
            })

            local rgb_id = vim.fn.hlID("RgbOnly")
            local initial = {
                plain_fg = vim.fn.synIDattr(rgb_id, "fg#"),
                plain_bg = vim.fn.synIDattr(rgb_id, "bg#"),
                gui_fg = vim.fn.synIDattr(rgb_id, "fg#", "gui"),
                gui_bg = vim.fn.synIDattr(rgb_id, "bg#", "gui"),
            }

            vim.o.termguicolors = true
            local tgc = {
                plain_fg = vim.fn.synIDattr(rgb_id, "fg#"),
                plain_bg = vim.fn.synIDattr(rgb_id, "bg#"),
                gui_fg = vim.fn.synIDattr(rgb_id, "fg", "gui"),
                gui_bg = vim.fn.synIDattr(rgb_id, "bg", "gui"),
            }

            vim.o.termguicolors = false
            vim.api.nvim_set_hl(0, "CtermOnly", {
                ctermfg = 196,
                ctermbg = 16,
            })

            local cterm_id = vim.fn.hlID("CtermOnly")
            local cterm = {
                plain_fg = vim.fn.synIDattr(cterm_id, "fg"),
                plain_bg = vim.fn.synIDattr(cterm_id, "bg"),
                plain_fg_hash = vim.fn.synIDattr(cterm_id, "fg#"),
                plain_bg_hash = vim.fn.synIDattr(cterm_id, "bg#"),
                gui_fg = vim.fn.synIDattr(cterm_id, "fg#", "gui"),
                gui_bg = vim.fn.synIDattr(cterm_id, "bg#", "gui"),
                cterm_fg = vim.fn.synIDattr(cterm_id, "fg", "cterm"),
                cterm_bg = vim.fn.synIDattr(cterm_id, "bg", "cterm"),
            }

            return {
                initial = initial,
                tgc = tgc,
                cterm = cterm,
            }
        ]])

        Assert.table_eq("rgb-only attrs stay empty in plain cterm mode", result.initial, {
            plain_fg = "",
            plain_bg = "",
            gui_fg = "#112233",
            gui_bg = "#445566",
        })

        Assert.table_eq("termguicolors makes plain lookups use gui colors", result.tgc, {
            plain_fg = "#112233",
            plain_bg = "#445566",
            gui_fg = "#112233",
            gui_bg = "#445566",
        })

        Assert.table_eq("cterm-only attrs stay numeric outside gui mode", result.cterm, {
            plain_fg = "196",
            plain_bg = "16",
            plain_fg_hash = "196",
            plain_bg_hash = "16",
            gui_fg = "",
            gui_bg = "",
            cterm_fg = "196",
            cterm_bg = "16",
        })
    end,
}
