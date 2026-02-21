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

local buf = mock.create_buffer(1, "/tmp/test_setline.vim", { "one", "two", "three" }, { modified = false })
function buf:set_lines(start0, stop0, _, replacement)
    local start1 = start0 + 1
    local remove_count = stop0 - start0
    for _ = 1, remove_count do
        table.remove(self.lines, start1)
    end
    for i = 1, #replacement do
        table.insert(self.lines, start1 + i - 1, replacement[i])
    end
    if #self.lines == 0 then
        self.lines = { "" }
    end
    self.opts.modified = true
end

local win = mock.create_window(1, buf, {})
win.cursory = 2
win.cursorx = 1
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

local Fn = mock.loadModule("lib.luaapi.fn")

assert_eq("setline numeric line success", Fn.setline(2, "TWO"), 0)
assert_eq("line 2 updated", buf.lines[2], "TWO")

assert_eq("setline $ success", Fn.setline("$", "THREE"), 0)
assert_eq("last line updated", buf.lines[3], "THREE")

assert_eq("setline append at last+1", Fn.setline(4, "FOUR"), 0)
assert_eq("line appended", buf.lines[4], "FOUR")

assert_eq("setline . uses cursor line", Fn.setline(".", "CUR"), 0)
assert_eq("cursor line updated", buf.lines[2], "CUR")

assert_eq("setline list converts values", Fn.setline(1, { 10, true }), 0)
assert_eq("list item 1 converted", buf.lines[1], "10")
assert_eq("list item 2 converted", buf.lines[2], "v:true")

assert_eq("setline list extends below last line", Fn.setline(4, { "x", "y", "z" }), 0)
assert_eq("extended line 4", buf.lines[4], "x")
assert_eq("extended line 5", buf.lines[5], "y")
assert_eq("extended line 6", buf.lines[6], "z")

local before_empty = table.concat(buf.lines, "\n")
assert_eq("setline empty list is success-noop", Fn.setline(3, {}), 0)
assert_eq("empty list leaves lines unchanged", table.concat(buf.lines, "\n"), before_empty)

local before_invalid = table.concat(buf.lines, "\n")
assert_eq("setline invalid low lnum fails", Fn.setline(0, "bad"), 1)
assert_eq("invalid low lnum leaves lines unchanged", table.concat(buf.lines, "\n"), before_invalid)
assert_eq("setline invalid high lnum fails", Fn.setline(#buf.lines + 2, "bad"), 1)
assert_eq("invalid high lnum leaves lines unchanged", table.concat(buf.lines, "\n"), before_invalid)

local ok, err = pcall(function()
    Fn.setline(1, "x", "extra")
end)
assert_true("setline too many args E118", (not ok) and tostring(err):find("E118", 1, true), tostring(err))

print("setline builtin tests: OK")
