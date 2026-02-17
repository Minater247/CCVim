local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.exmsg"] = function() return mock.loadModule("vim.lib.excmd.exmsg") end,
        ["vim.lib.excmd.exmsg"] = {
            messages = {},
            echo = function() end,
            echon = function() end,
            echomsg = function() end,
            echoerr = function() end,
            echohl = function() end,
            PushSilent = function() end,
            PushUnsilent = function() end,
            PopSilent = function() end,
            _writeWithHL = function() end,
        },
        ["vim.layout.buffer"] = {},
        ["vim.layout.window"] = {},
        ["vim.lib.tags"] = { SearchFile = function() return nil end },
        ["vim.lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["vim.lib.key"] = { strtoseq = function() return {} end },
        ["vim.lib.pack"] = { add = function() return true end, load_start = function() return true end },
        ["vim.lib.sign"] = { define = function() end, getdefined = function() return {} end },
    },
})

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s: expected true, got false"):format(label))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
local Compiler = mock.loadModule("vim.lib.excmd.compiler")
local Runtime = mock.loadModule("vim.lib.excmd.runtime")
local Scopes = mock.loadModule("vim.lib.luaapi.scopes")

local durable_by_ctx = {}
local function run_compiled(script, opts)
    opts = opts or {}
    local key = opts.script_ctx or "__default"
    local durable = durable_by_ctx[key]
    if not durable then
        durable = Runtime.CaptureDurableScriptState({ script_ctx = opts.script_ctx }) or { s = {}, funcs = {} }
        durable.g = durable.g or Scopes._g
        durable_by_ctx[key] = durable
    end

    local state = Runtime.MakeRuntimeState(durable)
    state.g = durable.g
    local runtime = Runtime.new(state)

    local code, err = Compiler.compile_script(script, { state = state })
    if not code then return false, err end

    local env = setmetatable({ runtime = runtime, _G = _G }, { __index = _G })
    local chunk, lerr = load(code, "excmd_compiled", "t", env)
    if not chunk then return false, lerr end

    local fn = chunk()
    local ok, rv = pcall(fn, state, runtime)
    if not ok then return false, rv end
    return true, rv, state, code
end

do
    local ok, rv, state, code = run_compiled([[
try
    nosuchcommand
catch /E492/
    let g:tc_caught=1
endtry
]], { script_ctx = "/tmp/trycatch_492.vim" })
    assert_true("try/catch E492 script runs", ok == true)
    if ok ~= true then error(tostring(rv)) end
    assert_eq("catch body executed", state.g.tc_caught, 1)
    assert_true("structured try emitted", code:find("runtime:catch_matches", 1, true) ~= nil)
end

do
    local ok, rv, state = run_compiled([[
let g:tc_finally=0
try
    let g:tc_path='ok'
catch /E492/
    let g:tc_path='caught'
finally
    let g:tc_finally=1
endtry
]], { script_ctx = "/tmp/tryfinally.vim" })
    assert_true("try/finally script runs", ok == true)
    if ok ~= true then error(tostring(rv)) end
    assert_eq("finally executed", state.g.tc_finally, 1)
    assert_eq("no catch on success", state.g.tc_path, "ok")
end

do
    local ok, rv = run_compiled([[
try
    nosuchcommand
catch /E118/
    let g:tc_wrong_catch=1
endtry
]], { script_ctx = "/tmp/trycatch_miss.vim" })
    assert_true("unmatched catch propagates error", ok == false)
    if ok == true then
        error("expected failure")
    end
end

do
    local ok, rv, state = run_compiled([[
let g:tc_loop_break = 0
while 1
    try
        let g:tc_loop_break = g:tc_loop_break + 1
        break
    catch /.*/
        let g:tc_loop_break = -99
    endtry
endwhile
]], { script_ctx = "/tmp/try_loop_break.vim" })
    assert_true("break inside try exits loop", ok == true)
    if ok ~= true then error(tostring(rv)) end
    assert_eq("break inside try not swallowed by catch", state.g.tc_loop_break, 1)
end

do
    local ok, rv, state = run_compiled([[
let g:tc_loop_n = 0
let g:tc_loop_continue_hits = 0
while g:tc_loop_n < 3
    let g:tc_loop_n = g:tc_loop_n + 1
    try
        if g:tc_loop_n < 3
            continue
        endif
    catch /.*/
        let g:tc_loop_continue_hits = -99
    endtry
    let g:tc_loop_continue_hits = g:tc_loop_continue_hits + 1
endwhile
]], { script_ctx = "/tmp/try_loop_continue.vim" })
    assert_true("continue inside try continues loop", ok == true)
    if ok ~= true then error(tostring(rv)) end
    assert_eq("loop reached final iteration", state.g.tc_loop_n, 3)
    assert_eq("continue skipped body twice", state.g.tc_loop_continue_hits, 1)
end

do
    local ok, rv, state = run_compiled([[
let g:tc_loop_catch = 0
while 1
    try
        nosuchcommand
    catch /E492/
        let g:tc_loop_catch = g:tc_loop_catch + 1
        break
    endtry
endwhile
]], { script_ctx = "/tmp/try_loop_regular_catch.vim" })
    assert_true("regular catch in loop still works", ok == true)
    if ok ~= true then error(tostring(rv)) end
    assert_eq("regular catch executed once", state.g.tc_loop_catch, 1)
end

print("try/catch compiler tests: OK")
