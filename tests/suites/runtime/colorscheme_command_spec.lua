return {
    id = "runtime.colorscheme_command",
    description = "Loads :colorscheme files through runtimepath search, fires ColorScheme events, and rebuilds the 16-color palette from tracked scheme colors.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local function unpack_rgb(rgb)
            local r = math.floor(rgb / 65536) % 256
            local g = math.floor(rgb / 256) % 256
            local b = rgb % 256
            return r, g, b
        end

        local root = Assert.temp_path(backend, "colorscheme-runtime", "")
        local colors_dir = root .. "/colors"
        local scheme_vim = colors_dir .. "/testpalette.vim"

        Assert.ensure_dir(backend, colors_dir)
        Assert.write_file(backend, scheme_vim, table.concat({
            "hi clear",
            "let g:colors_name = 'testpalette'",
            "hi Normal guifg=#111111 guibg=#eeeeee",
            "hi Comment guifg=#123456",
            "hi String guifg=#abcdef",
            "hi Keyword guifg=#ff0000 guibg=#00ff00",
            "hi Special guifg=#0000ff",
            "",
        }, "\n"))

        local result = Assert.eval_block(backend, "colorscheme command scenarios", string.format([=[
            local colors = _G.colors
            local Highlight = loadModule("lib.highlight")
            local events = {}

            local function trim(s)
                return tostring(s or ""):gsub("^%%s+", ""):gsub("%%s+$", "")
            end

            local function actual_group_color(name, which)
                local hl = Highlight.For(name, 0, true)
                local slot = which == "fg" and hl[1] or hl[2]
                local r, g, b = term.getPaletteColor(slot)
                return colors.packRGB(r, g, b)
            end

            vim.api.nvim_create_autocmd("ColorSchemePre", {
                pattern = "testpalette",
                callback = function(ev)
                    events[#events + 1] = ("pre|%%s|%%s|%%s"):format(
                        tostring(ev.match or ""),
                        tostring(ev.file or ""),
                        tostring(vim.g.colors_name or "")
                    )
                end,
            })

            vim.api.nvim_create_autocmd("ColorScheme", {
                pattern = "testpalette",
                callback = function(ev)
                    events[#events + 1] = ("post|%%s|%%s|%%s"):format(
                        tostring(ev.match or ""),
                        tostring(ev.file or ""),
                        tostring(vim.g.colors_name or "")
                    )
                end,
            })

            vim.cmd("set runtimepath^=" .. vim.fn.fnameescape(%q))

            local before = trim(vim.fn.execute("colorscheme"))
            vim.cmd.colorscheme("testpalette")
            local after = trim(vim.fn.execute("colorscheme"))

            return {
                before,
                after,
                vim.g.colors_name,
                events,
                actual_group_color("Normal", "fg"),
                actual_group_color("Normal", "bg"),
                actual_group_color("Comment", "fg"),
                actual_group_color("String", "fg"),
                actual_group_color("Keyword", "fg"),
                actual_group_color("Keyword", "bg"),
                actual_group_color("Special", "fg"),
            }
        ]=], root))

        Assert.eq("colorscheme defaults to default name", result[1], "default")
        Assert.eq("colorscheme reports active name", result[2], "testpalette")
        Assert.eq("g:colors_name set", result[3], "testpalette")
        Assert.table_eq("colorscheme events", result[4], {
            "pre|testpalette|testpalette|",
            "post|testpalette|testpalette|testpalette",
        })

        Assert.truthy("Normal fg stays dark", result[5] <= 0x404040, result[5])
        Assert.truthy("Normal bg stays light", result[6] >= 0xCCCCCC, result[6])
        Assert.truthy("Comment and String stay distinct", result[7] ~= result[8], result[7] .. " vs " .. result[8])
        local kr, kg, kb = unpack_rgb(result[9])
        Assert.truthy("Keyword fg stays red-dominant", kr > kg and kr > kb, result[9])

        local br, bg, bb = unpack_rgb(result[10])
        Assert.truthy("Keyword bg stays green-dominant", bg > br and bg > bb, result[10])

        local sr, sg, sb = unpack_rgb(result[11])
        Assert.truthy("Special fg stays blue-dominant", sb > sr and sb > sg, result[11])

        Assert.expect_error_code_block(backend, "missing colorscheme returns E185", [[
            vim.cmd.colorscheme("missing_palette")
        ]], "E185")

        local replay = Assert.eval_block(backend, "colorscheme reload resets root palette", [[
            local colors = _G.colors
            local Highlight = loadModule("lib.highlight")

            local function actual_group_color(name, which)
                local hl = Highlight.For(name, 0, true)
                local slot = which == "fg" and hl[1] or hl[2]
                local r, g, b = term.getPaletteColor(slot)
                return colors.packRGB(r, g, b)
            end

            local function snapshot()
                return {
                    actual_group_color("Normal", "fg"),
                    actual_group_color("Normal", "bg"),
                    actual_group_color("StatusLine", "fg"),
                    actual_group_color("StatusLine", "bg"),
                }
            end

            vim.cmd.colorscheme("default")
            local first_default = snapshot()
            vim.cmd.colorscheme("darkblue")
            vim.cmd.colorscheme("default")
            local second_default = snapshot()

            return {
                first_default,
                second_default,
            }
        ]])

        Assert.table_eq("default colorscheme is stable after another colorscheme", replay[2], replay[1])
    end,
}
