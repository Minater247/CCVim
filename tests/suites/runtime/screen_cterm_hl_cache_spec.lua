return {
    id = "runtime.screen_cterm_hl_cache",
    description = "Checks that the real screen highlight cache keeps cterm attrs distinct from RGB-only equality; lua-editor-only because it loads lib.screen directly.", -- luacheck: ignore 631
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()
        local ok, err = pcall(function()
            local Screen = mock.loadModule("lib.screen", { immediate = true })
            Screen.init(mock.globals().backend)
            Screen.default_colors_set(0x102030, 0x405060, nil, 196, 16)

            local default_id = Screen.hl_id_for({
                foreground = 0x102030,
                background = 0x405060,
                cterm_foreground = 196,
                cterm_background = 16,
            })
            local distinct_id = Screen.hl_id_for({
                foreground = 0x102030,
                background = 0x405060,
                cterm_foreground = 202,
                cterm_background = 17,
            })

            Assert.eq("default-matching attrs still use hl id 0", default_id, 0)
            Assert.truthy("different cterm attrs get a distinct hl id", distinct_id ~= 0, distinct_id)

            local attrs = Screen.hl_attrs(distinct_id)
            Assert.eq("distinct hl keeps cterm fg", attrs.cterm_foreground, 202)
            Assert.eq("distinct hl keeps cterm bg", attrs.cterm_background, 17)
            Assert.eq("distinct hl preserves rgb fg", attrs.foreground, 0x102030)
            Assert.eq("distinct hl preserves rgb bg", attrs.background, 0x405060)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
