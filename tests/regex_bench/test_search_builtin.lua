local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: expected true, got false (%s)"):format(label, tostring(detail)))
    end
end

_G.options = mock.loadModule("lib.options")
local Fn = mock.loadModule("lib.luaapi.fn")

local buf = mock.create_buffer(1, "/tmp/test_search.vim", {
    "alpha",
    "beta foo",
    "foo gamma",
    "omega",
}, {})
local win = mock.create_window(1, buf, {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

win.cursory = 1
win.cursorx = 1
assert_eq("forward finds first hit", Fn.fn.search("foo"), 2)
assert_eq("forward moves line", win.cursory, 2)
assert_eq("forward moves col", win.cursorx, 6)

win.cursory = 1
win.cursorx = 1
assert_eq("n flag returns match line", Fn.fn.search("foo", "n"), 2)
assert_eq("n flag keeps line", win.cursory, 1)
assert_eq("n flag keeps col", win.cursorx, 1)

win.cursory = 2
win.cursorx = 6
assert_eq("without c skips current match", Fn.fn.search("foo", "n"), 3)
assert_eq("with c accepts current match", Fn.fn.search("foo", "nc"), 2)

win.cursory = 3
win.cursorx = 1
assert_eq("backward no-wrap finds previous", Fn.fn.search("foo", "bnW"), 2)

win.cursory = 4
win.cursorx = 1
assert_eq("default wrap finds from top", Fn.fn.search("foo", "n"), 2)
assert_eq("W disables wrap", Fn.fn.search("foo", "nW"), 0)

win.cursory = 1
win.cursorx = 1
assert_eq("stopline limits forward search", Fn.fn.search("foo", "n", 1), 0)
assert_eq("stopline includes matching line", Fn.fn.search("foo", "n", 2), 2)

win.cursory = 1
win.cursorx = 1
assert_eq("e flag moves to end of match", Fn.fn.search("foo", "e"), 2)
assert_eq("e flag line", win.cursory, 2)
assert_eq("e flag col", win.cursorx, 8)

win.cursory = 4
win.cursorx = 1
assert_eq("search handles \\M mode marker", Fn.fn.search("^\\Momega", "n"), 4)

win.scrolly = { 2, 0 }
win.cursory = 4
assert_eq("winline returns cursor row in window", Fn.fn.winline(), 3)

win.cursory = 1
win.cursorx = 1
assert_eq("skip function skips first hit", Fn.fn.search("foo", "n", 0, 0, function()
    return windows[curwin].cursory == 2
end), 3)
assert_eq("skip function keeps cursor with n", win.cursory, 1)

win.cursory = 1
win.cursorx = 1
assert_eq("skip error returns -1", Fn.fn.search("foo", "n", 0, 0, function()
    error("boom")
end), -1)

local ok, err = pcall(function()
    Fn.fn.search("foo", "", 0, 0, nil, "extra")
end)
assert_true("too many args throws E118", (not ok) and tostring(err):find("E118", 1, true), tostring(err))

print("search builtin tests: OK")
