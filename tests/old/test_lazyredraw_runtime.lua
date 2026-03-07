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
    module_stubs = {
        ["lib.command"] = {
            HandleKey = function() end,
        },
        ["lib.key"] = {
            new = function() end,
        },
        ["lib.luaapi.on_key"] = {
            dispatch = function() return false end,
        },
        ["lib.excmd.exmsg"] = {
            Finalize = function() end,
            echoerr = function() end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
Options.set("lazyredraw", true)

local render_count = 0
tabpages = {
    [1] = {
        render = function()
            render_count = render_count + 1
        end,
    },
}
curtp = 1

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

assert_eq("lazyredraw blocks redraw while active", render_count, 0)
assert_eq("pending redraw kept while blocked", need_redraw, true)

lazyredraw_force = true
Event.StartTimer(0, function()
    Event.HaltLoop()
end)
Event.RunLoop()

assert_eq("forced redraw bypasses lazyredraw block", render_count, 1)

print("lazyredraw runtime tests: OK")
