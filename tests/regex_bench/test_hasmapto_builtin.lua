local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.event"] = {
            StartTimer = function() return 1 end,
            CancelTimer = function() end,
        },
        ["vim.lib.excmd.exmsg"] = {
            echo = function() end,
            echon = function() end,
            echomsg = function() end,
            echoerr = function() end,
        },
    },
})

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: expected true, got false (%s)"):format(label, tostring(detail)))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function key(ch)
    local code = string.byte(ch)
    return {
        numeric = code,
        printable = function() return ch end,
        emittable = function() return ch end,
    }
end

local function seq(str)
    local out = {}
    for i = 1, #str do
        out[#out + 1] = key(str:sub(i, i))
    end
    return out
end

local buf = mock.create_buffer(1, "/tmp/test_hasmapto.vim", { "" }, {})
local win = mock.create_window(1, buf, {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

local Fn = mock.loadModule("vim.lib.luaapi.fn")
local Command = mock.loadModule("vim.lib.command")

Command.clear_mappings({
    "normal",
    "visual",
    "select",
    "operator",
    "insert",
    "lang",
    "cmdline",
    "terminal",
})

Command.remap_keys("normal", seq("g"), seq("<Plug>GlobalTarget"))
assert_eq("default nvo finds normal mapping", Fn.hasmapto("<Plug>GlobalTarget"), 1)

Command.remap_keys("insert", seq("i"), seq("InsertOnly"))
assert_eq("default nvo excludes insert", Fn.hasmapto("InsertOnly"), 0)
assert_eq("explicit insert mode finds insert mapping", Fn.hasmapto("InsertOnly", "i"), 1)

Command.remap_keys("select", seq("s"), seq("SelectOnly"))
assert_eq("v mode includes select", Fn.hasmapto("SelectOnly", "v"), 1)
assert_eq("x mode excludes select-only mapping", Fn.hasmapto("SelectOnly", "x"), 0)

Command.remap_keys("normal", seq("b"), seq("BufLocalOnly"), { buffer_local = true })
assert_eq("buffer-local mappings are searched", Fn.hasmapto("BufLocalOnly", "n"), 1)

assert_eq("abbr mode returns no mapping", Fn.hasmapto("<Plug>GlobalTarget", "n", 1), 0)

local ok, err = pcall(function()
    Fn.hasmapto("x", "n", 0, 1)
end)
assert_true("too many args keeps E118", (not ok) and tostring(err):find("E118", 1, true), tostring(err))

print("hasmapto builtin tests: OK")
