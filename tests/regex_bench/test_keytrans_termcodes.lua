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

install_keys()

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Key = mock.loadModule("lib.key")
local Fn = mock.loadModule("lib.luaapi.fn")
local Api = mock.loadModule("lib.luaapi.api")
local Runtime = mock.loadModule("lib.excmd.runtime")

local repl_cr = Key.replace_termcodes("<CR>", true, true)
assert_eq("replace_termcodes CR byte", string.byte(repl_cr), 13)

local repl_cmd = Key.replace_termcodes("<Cmd>echo 1<CR>", true, true)
assert_eq("replace_termcodes Cmd prefix b1", string.byte(repl_cmd, 1), 128)
assert_eq("replace_termcodes Cmd prefix b2", string.byte(repl_cmd, 2), 253)
assert_eq("replace_termcodes Cmd prefix b3", string.byte(repl_cmd, 3), 104)
assert_eq("replace_termcodes Cmd suffix byte", string.byte(repl_cmd, #repl_cmd), 13)
assert_eq("replace_termcodes Cmd keytrans", Key.keytrans(repl_cmd), "<Cmd>echo<Space>1<CR>")

local star = Key.replace_termcodes("<*C-j>", true, true)
assert_eq("keytrans star ctrl-j", Key.keytrans(star), "<NL>")
assert_eq("builtin keytrans star ctrl-j", Fn.keytrans(star), "<NL>")
assert_eq("api replace_termcodes delegates", Api.nvim_replace_termcodes("<*C-j>", true, true, true), star)

local nonstar = Key.replace_termcodes("<C-j>", true, true)
assert_eq("keytrans non-star ctrl-j", Key.keytrans(nonstar), "<NL>")

local state = Runtime.MakeRuntimeState({
    g = {},
    s = {},
    script_ctx = "/tmp/test_keytrans_termcodes.vim",
})
local rt = Runtime.new(state)

local expr_star = rt:eval_expr([["\<*C-j>"]])
assert_eq("expr star uses internal keycode", Key.keytrans(expr_star), "<C-J>")

local expr_cmd = rt:eval_expr([["\<Cmd>echo 1\<CR>"]])
assert_eq("expr cmd prefix b1", string.byte(expr_cmd, 1), 128)
assert_eq("expr cmd prefix b2", string.byte(expr_cmd, 2), 253)
assert_eq("expr cmd prefix b3", string.byte(expr_cmd, 3), 104)
assert_eq("expr cmd suffix byte", string.byte(expr_cmd, #expr_cmd), 13)
assert_eq("expr cmd keytrans", Key.keytrans(expr_cmd), "<Cmd>echo<Space>1<CR>")

print("keytrans/termcodes tests: OK")
