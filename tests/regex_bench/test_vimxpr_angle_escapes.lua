local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({})
local Runtime = mock.loadModule("vim.lib.excmd.runtime")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function char_len(s)
    if utf8 and utf8.len then
        return utf8.len(s)
    end
    return #s
end

local state = Runtime.MakeRuntimeState({
    g = {},
    s = {},
    script_ctx = "/tmp/test_vimxpr_angle_escapes.vim",
})
local rt = Runtime.new(state)

local v_ff = rt:eval_expr([["\<Char-0xff>"]])
assert_eq("char-hex chars", char_len(v_ff), 1)
assert_eq("char-hex byte1", string.byte(v_ff, 1), 195)
assert_eq("char-hex byte2", string.byte(v_ff, 2), 191)

local v_01 = rt:eval_expr([["\<Char-0x01>"]])
assert_eq("char-01 len", #v_01, 1)
assert_eq("char-01 byte", string.byte(v_01), 1)

local v_cv = rt:eval_expr([["\<C-V>"]])
assert_eq("ctrl-v len", #v_cv, 1)
assert_eq("ctrl-v byte", string.byte(v_cv), 22)

local v_unknown = rt:eval_expr([["\<NotAKey>"]])
assert_eq("unknown literal", v_unknown, [[\<NotAKey>]])

print("vimxpr angle escape decoding test: OK")
