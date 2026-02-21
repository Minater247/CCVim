local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local buf = mock.create_buffer(1, "/tmp/utf8.txt", { "aé✓", "\té" })
local win = mock.create_window(1, buf, {})
win.cursory = 1
win.cursorx = 1
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

assert_eq("str_len counts codepoints", buf:str_len("aé✓"), 3)
assert_eq("line_len counts codepoints", buf:line_len(1, true), 3)
assert_eq("line_sub keeps utf8 character boundaries", buf:line_sub(1, 2, 2, true), "é")
assert_eq("line_byte_index maps char col to byte index", buf:line_byte_index(1, 3, true, true), 4)
assert_eq("str_col_from_byte maps byte index to char col", buf:str_col_from_byte(buf:get_line(1, true), 4, true), 3)

print("utf8 buffer helper tests: OK")
