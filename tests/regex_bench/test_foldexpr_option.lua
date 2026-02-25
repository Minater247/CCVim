local MockEnv = require("vim.tests.test_mocks")

local exmsg_stub = {
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
}

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.exmsg"] = exmsg_stub,
        ["lib.excmd.exmsg"] = exmsg_stub,
        ["lib.highlight"] = {
            GroupExists = function() return false end,
            For = function() return { colors.white, colors.black } end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["lib.autocmd"] = {
            Run = function() return 0 end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Buffer = mock.loadModule("layout.buffer")

local durable_by_ctx = {}
local function run_compiled(script, opts)
    opts = opts or {}
    local key = opts.script_ctx or "__default"
    local durable = durable_by_ctx[key]
    if not durable then
        durable = Runtime.CaptureDurableScriptState({ script_ctx = opts.script_ctx })
        durable.g = Scopes._g
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
    return true, rv
end

local buf = Buffer(true, false, true)
buf.name = "/tmp/test.txt"
buf.lines = { "" }
buf.loaded = true
buf.leave = function() return true end
local win = {
    winnr = 1,
    buffer = buf,
    opts = {},
    cursorx = 1,
    cursory = 1,
    scrolly = { 1, 0 },
    scrollx = 0,
}
buffers[1] = buf
windows[1] = win
tabpages[1].windows = { win }
curwin = 1

local ok_a, err_a = run_compiled([[
let s:base = 40
function s:FoldExpr()
  return s:base + v:lnum
endfunction
setlocal foldexpr=s:FoldExpr()
let s:base = 42
]], { script_ctx = "/tmp/foldexpr_script_a.vim" })
assert_eq("foldexpr script A setup", ok_a, true)

local expr_a = Options.get("foldexpr", win, buf)
assert_eq("foldexpr script A stored value", expr_a, "s:FoldExpr()")

local val_a, ok_eval_a = Options.EvalExprOption("foldexpr", expr_a, win, buf, { lnum = 3 })
assert_eq("foldexpr script A eval ok", ok_eval_a, true)
assert_eq("foldexpr script A sees script-local state", val_a, 45)

local ok_b, err_b = run_compiled([[
let s:tick = 0
function s:FoldExpr()
  let s:tick = s:tick + 1
  return s:tick
endfunction
setlocal foldexpr=s:FoldExpr()
]], { script_ctx = "/tmp/foldexpr_script_b.vim" })
assert_eq("foldexpr script B setup", ok_b, true)

local expr_b = Options.get("foldexpr", win, buf)
assert_eq("foldexpr script B stored value", expr_b, "s:FoldExpr()")

local val_b1, ok_eval_b1 = Options.EvalExprOption("foldexpr", expr_b, win, buf, { lnum = 1 })
assert_eq("foldexpr script B eval #1 ok", ok_eval_b1, true)
assert_eq("foldexpr script B eval #1 value", val_b1, 1)

local val_b2, ok_eval_b2 = Options.EvalExprOption("foldexpr", expr_b, win, buf, { lnum = 1 })
assert_eq("foldexpr script B eval #2 ok", ok_eval_b2, true)
assert_eq("foldexpr script B keeps persistent script-local state", val_b2, 2)

print("foldexpr option tests: OK")
