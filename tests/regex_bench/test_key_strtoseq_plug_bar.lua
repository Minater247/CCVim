local MockEnv = require("vim.tests.test_mocks")

local function install_keys()
    local next_code = 1
    local keymap = {}
    setmetatable(keymap, {
        __index = function(t, k)
            local v = next_code
            next_code = next_code + 1
            rawset(t, k, v)
            return v
        end,
    })
    _G.keys = keymap
end

local mock = MockEnv.setup({})
install_keys()

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Key = mock.loadModule("lib.key")

local function parse_text(s)
    return Key.seqtostr(Key.strtoseq(s))
end

assert_eq("plug token canonicalizes", parse_text("<plug>(Foo)"), "<Plug>(Foo)")
assert_eq("plug token keeps canonical form", parse_text("<Plug>(Foo)"), "<Plug>(Foo)")
assert_eq("bar token maps to literal pipe", parse_text("<bar>"), "|")
assert_eq("bar token case-insensitive", parse_text("<Bar>"), "|")
assert_eq("space token maps to literal space", parse_text("<Space>"), " ")
local ctrl_s = Key.strtoseq("<C-s>")
assert_eq("ctrl-s parses as key, not shift modifier", Key.printable_number(ctrl_s[1].numeric), "<C-s>")

local ok_cword = pcall(Key.strtoseq, "<cword>")
assert_true("cword remains non-key at this layer", ok_cword == false, ok_cword)

print("key strtoseq plug/bar tests: OK")
