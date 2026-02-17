-- Test lua scope indexing (b:, w:, t: scopes)
local MockEnv = require("vim.tests.test_mocks")
local mock = MockEnv.setup()

-- Set up test environment
local buf1 = mock.create_buffer(1, "/tmp/a", { "" })
local buf2 = mock.create_buffer(2, "/tmp/b", { "" })
local win1 = mock.create_window(1, buf1)
mock.create_tabpage(1, { win1 })

_G.curwin = 1
_G.curtp = 1

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s: expected true, got false"):format(label))
    end
end

local Scopes = mock.loadModule("vim.lib.luaapi.scopes")

Scopes.b.current_flag = "one"
assert_eq("b: current buffer write", Scopes._b_by_buf[1].current_flag, "one")
assert_eq("b: current buffer read", Scopes.b.current_flag, "one")

Scopes.b[2].other_flag = "two"
assert_eq("b[bufnr] write", Scopes._b_by_buf[2].other_flag, "two")
assert_eq("b[bufnr] read", Scopes.b[2].other_flag, "two")

Scopes.b[0].zero_alias = "cur"
assert_eq("b[0] aliases current buffer", Scopes._b_by_buf[1].zero_alias, "cur")

Scopes.w.win_flag = "w1"
assert_eq("w: current window write", Scopes._w_by_win[1].win_flag, "w1")
Scopes.w[0].win_zero = "w1z"
assert_eq("w[0] aliases current window", Scopes._w_by_win[1].win_zero, "w1z")

Scopes.t.tab_flag = "t1"
assert_eq("t: current tab write", Scopes._t_by_tab[1].tab_flag, "t1")
Scopes.t[0].tab_zero = "t1z"
assert_eq("t[0] aliases current tab", Scopes._t_by_tab[1].tab_zero, "t1z")

local ok_b = pcall(function() return Scopes.b[999].x end)
assert_true("invalid b[bufnr] errors", ok_b == false)

local ok_w = pcall(function() return Scopes.w[999].x end)
assert_true("invalid w[winid] errors", ok_w == false)

local ok_t = pcall(function() return Scopes.t[999].x end)
assert_true("invalid t[tabnr] errors", ok_t == false)

print("lua scope indexing tests: OK")
