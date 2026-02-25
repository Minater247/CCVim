local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.event"] = {
            StartTimer = function() return 1 end,
            CancelTimer = function() end,
        },
        ["lib.excmd.exmsg"] = {
            echo = function() end,
            echon = function() end,
            echomsg = function() end,
            echoerr = function() end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local loaded = mock.create_buffer(1, "/tmp/loaded.txt", { "" }, {})
local unloaded = mock.create_buffer(2, "/tmp/unloaded.txt", { "" }, {})
unloaded.loaded = false
unloaded.lines = {}

local win = mock.create_window(1, loaded, {})
win.altbuf = 2
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

local Fn = mock.loadModule("lib.luaapi.fn")

assert_eq("number loaded", Fn.bufloaded(1), 1)
assert_eq("number unloaded", Fn.bufloaded(2), 0)
assert_eq("number missing", Fn.bufloaded(99), 0)

assert_eq("name loaded", Fn.bufloaded("/tmp/loaded.txt"), 1)
assert_eq("name unloaded", Fn.bufloaded("/tmp/unloaded.txt"), 0)
assert_eq("name missing", Fn.bufloaded("/tmp/missing.txt"), 0)

assert_eq("alt buffer via 0", Fn.bufloaded(0), 0)
win.altbuf = 1
assert_eq("alt loaded via 0", Fn.bufloaded(0), 1)
win.altbuf = nil
assert_eq("no alt buffer", Fn.bufloaded(0), 0)

assert_eq("invalid arg type", Fn.bufloaded({}), 0)

print("bufloaded builtin tests: OK")
