local MockEnv = require("vim.tests.test_mocks")

local messages = {}
local exmsg_stub = {
    echo = function(msg)
        messages[#messages + 1] = msg
    end,
    echon = function() end,
    echomsg = function() end,
    echoerr = function() end,
    echohl = function() end,
    PushSilent = function() end,
    PushUnsilent = function() end,
    PushUISuppress = function() end,
    PopUISuppress = function() end,
    StartCapture = function() return {} end,
    EndCapture = function() return "", nil end,
    PopSilent = function() end,
    _writeWithHL = function() end,
}

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.exmsg"] = function() return exmsg_stub end,
        ["lib.excmd.exmsg"] = exmsg_stub,
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local api = ApiBuild.Build()

assert_eq("notify_once is exported on vim", type(api.vim.notify_once), "function")

assert_eq("first call displays", api.vim.notify_once("alpha", 2, { title = "one" }), true)
assert_eq(
    "second call with same message is suppressed",
    api.vim.notify_once("alpha", 3, { title = "two" }),
    false
)
assert_eq("different message displays", api.vim.notify_once("beta", 3, { title = "three" }), true)

local chunk_1 = assert(load("return vim.notify_once('gamma')", "=(notify_once_chunk_1)", "t", api))
local chunk_2 = assert(load("return vim.notify_once('gamma')", "=(notify_once_chunk_2)", "t", api))

assert_eq("first separate chunk call displays", chunk_1(), true)
assert_eq("second separate chunk call is suppressed", chunk_2(), false)

assert_eq("notify emitted exactly once per unique message", #messages, 3)
assert_true("first emitted message contains alpha", messages[1]:find("alpha", 1, true) ~= nil, messages[1])
assert_true("second emitted message contains beta", messages[2]:find("beta", 1, true) ~= nil, messages[2])
assert_true("third emitted message contains gamma", messages[3]:find("gamma", 1, true) ~= nil, messages[3])

print("notify_once runtime tests: OK")
