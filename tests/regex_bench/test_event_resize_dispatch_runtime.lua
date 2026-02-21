local MockEnv = require("vim.tests.test_mocks")

local exmsg_calls = {
    echoerr = {},
}

local exmsg_stub = {
    echo = function() end,
    echon = function() end,
    echomsg = function() end,
    echoerr = function(msg)
        exmsg_calls.echoerr[#exmsg_calls.echoerr + 1] = tostring(msg)
    end,
    Finalize = function() end,
}

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.command"] = {
            HandleKey = function() end,
        },
        ["vim.lib.key"] = {
            new = function() end,
        },
        ["vim.lib.luaapi.on_key"] = {
            dispatch = function() return false end,
        },
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail or "assertion failed")))
    end
end

local pulled = 0
_G.os = {
    startTimer = function()
        return 99
    end,
    cancelTimer = function() end,
    pullEvent = function()
        pulled = pulled + 1
        if pulled == 1 then
            return "term_resize"
        elseif pulled == 2 then
            return "monitor_resize"
        elseif pulled == 3 then
            return "timer", 99
        end
        error("unexpected pullEvent call: " .. tostring(pulled))
    end,
}

local size_calls = 0
_G.term = _G.term or {}
_G.term.getSize = function()
    size_calls = size_calls + 1
    if size_calls == 1 then
        return 120, 40
    end
    return 121, 41
end

local resize_calls = {}
local Error = mock.loadModule("vim.lib.error")
_G._V = {
    apply_terminal_resize = function(w, h, source)
        resize_calls[#resize_calls + 1] = { w = w, h = h, source = source }
        if source == "monitor_resize" then
            return false, Error(36)
        end
        return true
    end,
}

need_redraw = false
what_redraw = {}
tabpages = {
    [1] = {
        render = function() end,
    },
}
curtp = 1

local Event = mock.loadModule("vim.lib.event")
Event.LoadCommandModule()

Event.StartTimer(0, function()
    Event.HaltLoop()
end)

Event.RunLoop()

assert_eq("resize called twice", #resize_calls, 2)
assert_eq("first resize source", resize_calls[1].source, "term_resize")
assert_eq("first resize width", resize_calls[1].w, 120)
assert_eq("first resize height", resize_calls[1].h, 40)
assert_eq("second resize source", resize_calls[2].source, "monitor_resize")
assert_eq("second resize width", resize_calls[2].w, 121)
assert_eq("second resize height", resize_calls[2].h, 41)
assert_eq("failed resize echoed once", #exmsg_calls.echoerr, 1)
assert_true(
    "echoerr contains E36",
    exmsg_calls.echoerr[1]:find("E36", 1, true) ~= nil,
    exmsg_calls.echoerr[1]
)

print("event resize dispatch runtime tests: OK")
