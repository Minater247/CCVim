local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local mock = MockEnv.setup()
local api = mock.loadModule("lib.luaapi.api")

local buf = mock.create_buffer(1, "/tmp/current-line-test", { "alpha", "beta", "gamma" })
local win = mock.create_window(1, buf)
win.cursory = 1
win.cursorx = 1
curwin = 1

assert_eq("line at row 1", api.nvim_get_current_line(), "alpha")

win.cursory = 3
assert_eq("line at row 3", api.nvim_get_current_line(), "gamma")

local empty_buf = mock.create_buffer(2, "/tmp/current-line-empty", {})
win.buffer = empty_buf
win.cursory = 1
assert_eq("zero-line buffer edge returns empty string", api.nvim_get_current_line(), "")

print("nvim_get_current_line tests: OK")
