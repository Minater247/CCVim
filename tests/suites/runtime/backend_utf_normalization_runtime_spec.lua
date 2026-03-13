return {
    id = "runtime.backend_utf_normalization",
    description = "Keeps native Unicode intact while ComputerCraft-specific replacements can swap colors per glyph.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local root = mock.globals().ccvim_path

            do
                local CC = dofile(root .. "/lib/backend/cc.lua")
                local left, left_swap = CC.normalize_codepoint(0xE0B2)
                local right, right_swap = CC.normalize_codepoint(0xE0B0)
                local round_right, round_right_swap = CC.normalize_codepoint(0xE0B4)
                local round_left, round_left_swap = CC.normalize_codepoint(0xE0B6)
                local full_right, full_right_swap = CC.normalize_codepoint(0xE0BA)
                local full_left, full_left_swap = CC.normalize_codepoint(0xE0B8)

                Assert.eq("cc left separator glyph", left, string.char(0x94))
                Assert.eq("cc left separator swap", left_swap, false)
                Assert.eq("cc right separator glyph", right, string.char(0x97))
                Assert.eq("cc right separator swap", right_swap, true)
                Assert.eq("cc rounded right thin glyph", round_right, string.char(0x88))
                Assert.eq("cc rounded right thin swap", round_right_swap, false)
                Assert.eq("cc rounded left thin glyph", round_left, string.char(0x84))
                Assert.eq("cc rounded left thin swap", round_left_swap, false)
                Assert.eq("cc full slanted right glyph", full_right, string.char(0x87))
                Assert.eq("cc full slanted right swap", full_right_swap, true)
                Assert.eq("cc full slanted left glyph", full_left, string.char(0x8B))
                Assert.eq("cc full slanted left swap", full_left_swap, true)

                CC.default_colors_set(0xF0F0F0, 0x111111, nil, nil, nil)
                CC.hl_define(1, { foreground = 0xF0F0F0, background = 0x111111 })
                CC.begin_frame()
                CC.grid_line(1, 0, 0, {
                    { right, 1, 1, true },
                    { full_right, 1, 1, true },
                    { full_left, 1, 1, true },
                }, false)
                CC.end_frame()

                local cells = mock.term_cells()[1]
                Assert.eq("cc swapped slanted char drawn", cells[1].ch, string.char(0x97))
                Assert.eq("cc swapped slanted fg", cells[1].fg, "f")
                Assert.eq("cc swapped slanted bg", cells[1].bg, "0")
                Assert.eq("cc swapped full slanted right char drawn", cells[2].ch, string.char(0x87))
                Assert.eq("cc swapped full slanted right fg", cells[2].fg, "f")
                Assert.eq("cc swapped full slanted right bg", cells[2].bg, "0")
                Assert.eq("cc swapped full slanted left char drawn", cells[3].ch, string.char(0x8B))
                Assert.eq("cc swapped full slanted left fg", cells[3].fg, "f")
                Assert.eq("cc swapped full slanted left bg", cells[3].bg, "0")
            end

            do
                local saved_term = term
                term = nil
                local Native = dofile(root .. "/lib/backend/native.lua")
                term = saved_term

                local checkmark, swap = Native.normalize_codepoint(0x2713)
                local box = Native.normalize_codepoint(0x2500)
                Assert.eq("native keeps checkmark unicode", checkmark, "✓")
                Assert.eq("native unicode has no swap", swap, false)
                Assert.eq("native keeps box drawing unicode", box, "─")
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
