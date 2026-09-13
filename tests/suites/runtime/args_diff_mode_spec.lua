return {
    id = "runtime.args_diff_mode",
    description = "Checks that -d opens every argument in a vertical diff window with the documented local options.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local first = Assert.temp_path(ctx.backend, "args-diff-left", ".txt")
        local second = Assert.temp_path(ctx.backend, "args-diff-right", ".txt")
        Assert.write_file(ctx.backend, first, "left\n")
        Assert.write_file(ctx.backend, second, "right\n")

        local Args = ctx.backend.mock.loadModule("lib.args")
        local FrameTree = ctx.backend.mock.loadModule("lib.frame")
        Assert.eq("-d parse succeeds", Args.parse({ [0] = "nvim", "-d", first, second }), true)
        local startup_tab
        for _, tab in pairs(tabpages) do
            if #tab.windows == 2 then startup_tab = tab break end
        end
        Assert.truthy("-d startup tab exists", startup_tab ~= nil)
        Assert.eq("-d creates one window per argument", #startup_tab.windows, 2)
        Assert.eq("-d uses vertical splits", startup_tab.windows[1].frame.height,
            startup_tab.windows[2].frame.height)
        local first_x = select(1, FrameTree.GetXY(startup_tab.windows[1].frame))
        local second_x = select(1, FrameTree.GetXY(startup_tab.windows[2].frame))
        Assert.eq("first argument remains in first window", startup_tab.windows[1].buffer.name, first)
        Assert.eq("second argument remains in second window", startup_tab.windows[2].buffer.name, second)
        Assert.truthy("first argument is left of second argument", first_x < second_x, first_x .. " vs " .. second_x)
        for _, win in ipairs(startup_tab.windows) do
            Assert.eq("diff enabled", win.opts.diff, true)
            Assert.eq("scroll binding enabled", win.opts.scrollbind, true)
            Assert.eq("cursor binding enabled", win.opts.cursorbind, true)
            Assert.eq("wrapping disabled", win.opts.wrap, false)
            Assert.eq("diff fold method selected", win.opts.foldmethod, "diff")
            Assert.eq("default diff fold column selected", win.opts.foldcolumn, "2")
        end
    end,
}
