local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local cur = mock.create_buffer(1, "/tmp/current.txt", { "" }, {})
local win = mock.create_window(1, cur, {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

local Fn = mock.loadModule("lib.luaapi.fn")

assert_eq("reg_recording default", Fn.reg_recording(), "")
assert_eq("reg_executing default", Fn.reg_executing(), "")
assert_eq("reg_recorded default", Fn.reg_recorded(), "")

registers.__recording_register = "q"
registers.__executing_register = "a"
registers.__last_recorded_register = "z"

assert_eq("reg_recording set", Fn.reg_recording(), "q")
assert_eq("reg_executing set", Fn.reg_executing(), "a")
assert_eq("reg_recorded set", Fn.reg_recorded(), "z")

registers.__recording_register = ""
registers.__executing_register = nil
registers.__last_recorded_register = "x"

assert_eq("reg_recording empty", Fn.reg_recording(), "")
assert_eq("reg_executing nil", Fn.reg_executing(), "")
assert_eq("reg_recorded reset", Fn.reg_recorded(), "x")

print("reg_* builtin tests: OK")
