return {
    id = "runtime.lazyredraw",
    description = "Ports lazyredraw event-loop behavior on the real runtime with controlled timer delivery; lua-editor-only because it inspects CCVim's internal redraw scheduler state during the ComputerCraft event loop.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local timer_id = 0
        local mock = MockEnv.setup({
            os = {
                startTimer = function()
                    timer_id = timer_id + 1
                    return timer_id
                end,
                cancelTimer = function() end,
                pullEvent = function()
                    return "timer", timer_id
                end,
            },
        })

        local ok, err = pcall(function()
            local Options = mock.loadModule("lib.options")
            Options.set("lazyredraw", true)

            local render_count = 0
            tabpages[curtp].render = function()
                render_count = render_count + 1
            end

            local Event = mock.loadModule("lib.event")
            Event.LoadCommandModule()

            need_redraw = true
            what_redraw = {}
            lazyredraw_block = 1
            lazyredraw_force = false

            Event.StartTimer(0, function()
                Event.HaltLoop()
            end)
            Event.RunLoop()

            Assert.eq("lazyredraw blocks redraw while active", render_count, 0)
            Assert.eq("pending redraw kept while blocked", need_redraw, true)

            lazyredraw_force = true
            Event.StartTimer(0, function()
                Event.HaltLoop()
            end)
            Event.RunLoop()

            Assert.eq("forced redraw bypasses lazyredraw block", render_count, 1)
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
