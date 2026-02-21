local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.exmsg"] = function() return mock.loadModule("lib.excmd.exmsg") end,
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
        ["vim.lib.syntax"] = {
            ParseLinetypes = function() end,
            OwnSyntax = function() end,
            ExecuteCommand = function() return true end,
            SyntimeReport = function() return {} end,
            SyntimeSet = function() end,
            SyntimeClear = function() end,
            MatchCommand = function() return true end,
            OnWindowBufferChanged = function() end,
        },
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

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")

local test_buf = mock.create_buffer(1, "/tmp/test_compiler.vim", { "" }, {})
local test_win = mock.create_window(1, test_buf, {})
mock.create_tabpage(1, { test_win }, {})
curtp = 1
curwin = 1

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
    if not ok then return false, rv, state, code end
    return true, rv, state, code
end

-- Test: execute $'...' with interpolation of {expr}
do
    local ok, rv, state, code = run_compiled([[
let s_val = 42
execute $'let g:interp_exec = {s_val}'
]], { script_ctx = "/tmp/exec_interp.vim" })
    assert_true("execute $' interpolation runs", ok == true)
    assert_eq("interpolated value set", state.g.interp_exec, 42)
end

-- Test: execute with mixed expression args where some args are $'...'
-- (same shape used by runtime/syntax/help.vim).
do
    local ok, rv, state, code = run_compiled([[
let s_lang = 'vim'
let s_syntax = 'vim'
execute 'echo' $'"@helpExampleHighlight_{s_lang}"' $'"syntax/{s_syntax}.vim"'
]], { script_ctx = "/tmp/exec_interp_multi_args.vim" })
    assert_true("execute mixed args with $'...' runs", ok == true)
end

-- Repro: help.vim pattern that previously caused
-- "Invalid numeric coercion! Type=nil" under MockEnv.
do
    local ok, rv, state, code = run_compiled([[
if !exists('g:help_example_languages')
  let g:help_example_languages = #{ vim: 'vim' }
endif
for [s:lang, s:syntax] in g:help_example_languages->items()
  execute 'silent! syn include' $'@helpExampleHighlight_{s:lang}'
        \ $'syntax/{s:syntax}.vim'
endfor
]], { script_ctx = "/tmp/exec_interp_help_repro.vim" })
    assert_true("execute help.vim interpolation pattern runs", ok == true)
end

print("excmd execute $'... interpolation test: OK")
