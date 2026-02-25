local MockEnv = require("vim.tests.test_mocks")

local autocmd_run_count = 0

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
        ["lib.autocmd"] = {
            Run = function()
                autocmd_run_count = autocmd_run_count + 1
            end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local cur = mock.create_buffer(1, "/tmp/current.txt", { "" }, {})
local win = mock.create_window(1, cur, {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

local Fn = mock.loadModule("lib.luaapi.fn")

local a = Fn.bufadd("/tmp/a.txt")
assert_true("bufadd created buffer", a > 0, a)
assert_eq("bufadd does not trigger BufAdd autocmds", autocmd_run_count, 0)
assert_true("bufadd creates unloaded buffer", buffers[a].loaded == false, tostring(buffers[a].loaded))
assert_eq("bufadd creates unloaded buffer lines empty", #buffers[a].lines, 0)
assert_eq("bufadd creates unlisted buffer", buffers[a].opts.buflisted and 1 or 0, 0)
assert_eq("bufadd preserves name", buffers[a].name, "/tmp/a.txt")

local a2 = Fn.bufadd("/tmp/a.txt")
assert_eq("bufadd returns existing by name", a2, a)

local scratch = Fn.bufadd("")
assert_true("bufadd empty creates new buffer", scratch ~= a, scratch)
assert_eq("bufadd empty does not trigger BufAdd autocmds", autocmd_run_count, 0)
assert_eq("bufadd empty has empty name", buffers[scratch].name, "")
assert_true("bufadd empty is unloaded", buffers[scratch].loaded == false, tostring(buffers[scratch].loaded))
assert_eq("bufadd empty lines are empty", #buffers[scratch].lines, 0)

assert_eq("setreg charwise ok", Fn.setreg("a", "hello"), 0)
assert_eq("setreg charwise stored", registers["a"][2], "hello")
assert_eq("setreg updates unnamed", registers.unnamed[2], "hello")

assert_eq("setreg append via uppercase ok", Fn.setreg("A", " world"), 0)
assert_eq("setreg append via uppercase merged", registers["a"][2], "hello world")

assert_eq("setreg linewise list ok", Fn.setreg("b", { "one", "two" }), 0)
assert_eq("setreg linewise kind", registers["b"][1], "linewise")
assert_eq("setreg linewise payload size", #registers["b"][2], 2)
assert_eq("setreg linewise payload 1", registers["b"][2][1], "one")
assert_eq("setreg linewise payload 2", registers["b"][2][2], "two")

local alt = Fn.bufadd("/tmp/alt.txt")
assert_eq("setreg # accepts bufnr", Fn.setreg("#", alt), 0)
assert_eq("bufnr(#) tracks alt register", Fn.bufnr("#"), alt)

assert_eq("setreg # clear", Fn.setreg("#", ""), 0)
assert_eq("bufnr(#) cleared", Fn.bufnr("#"), -1)

print("bufadd/setreg builtin tests: OK")
