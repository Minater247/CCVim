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
local VimFn = mock.loadModule("lib.luaapi.fn")
local Buffer = mock.loadModule("layout.buffer")

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
    return true, rv
end
local Autocmd = mock.loadModule("lib.autocmd")

local buf = Buffer(true, false)
buf.name = "/tmp/test.txt"
buf.lines = { "" }
local win = {
    winnr = 1,
    buffer = buf,
    opts = {},
    cursorx = 1,
    cursory = 1,
    scrolly = { 1, 0 },
    scrollx = 0,
}
windows[1] = win
tabpages[1].windows = { win }
curwin = 1

assert_eq("bufnr('%') resolves current buffer", VimFn._proxy.bufnr("%"), buf.bufnr)
assert_eq("bufnr(0) resolves current buffer", VimFn._proxy.bufnr(0), buf.bufnr)

do
    local prev_dir = shell.dir
    shell.dir = function() return "vim" end
    assert_eq("getcwd canonicalizes relative shell.dir()", VimFn._proxy.getcwd(), "/vim")
    shell.dir = prev_dir
end

local ok_setup, err_setup = run_compiled([[
let s:val = 1
autocmd User ScriptStateTest let s:val = s:val + 1 | let g:autocmd_seen = s:val
let s:val = 2
]], { script_ctx = "/tmp/autocmd_script_state.vim" })
assert_eq("autocmd script setup", ok_setup, true)

Autocmd.Run("User", {
    pattern = "ScriptStateTest",
    bufnr = buf.bufnr,
    bufname = buf.name,
})
assert_eq("autocmd run #1 sees latest script-local state", Scopes._g.autocmd_seen, 3)

Autocmd.Run("User", {
    pattern = "ScriptStateTest",
    bufnr = buf.bufnr,
    bufname = buf.name,
})
assert_eq("autocmd run #2 keeps persistent script-local state", Scopes._g.autocmd_seen, 4)

local ok_if = run_compiled([[
if "x" ==# "x"
  let g:expr_string_head_ok = 1
endif
]])
assert_eq("if expression can start with a string literal", ok_if, true)
assert_eq("if string expression body executed", Scopes._g.expr_string_head_ok, 1)

buf.lines = { "vim9script", "let g:x = 1" }
local ok_if_join = run_compiled([[
if "\n" .. getline(1, 32)->join("\n") =~# '\n\s*vim9\%[script]\>'
  let g:expr_join_ok = 1
endif
]])
assert_eq("if expression with getline()->join()", ok_if_join, true)
assert_eq("if getline()->join() branch executed", Scopes._g.expr_join_ok, 1)

local ok_digit_cmd = run_compiled([[
command! -nargs=* Vim9X let g:digit_cmd_qargs = <q-args>
Vim9X "abc"
]])
assert_eq("user command names accept digits", ok_digit_cmd, true)
assert_eq("digit command preserves quoted args", Scopes._g.digit_cmd_qargs, "\"abc\"")

local ok_com_abbrev = run_compiled([[
com! -nargs=* Vim9Z execute <q-args> 1 ? "" : "contained"
Vim9Z let g:com_abbrev_ok = 1
]])
assert_eq("command abbreviation keeps ternary tail", ok_com_abbrev, true)
assert_eq("command abbreviation execution", Scopes._g.com_abbrev_ok, 1)

local ok_cmd_persist_define = run_compiled([[
command! -nargs=* PersistCmd let g:persist_cmd_qargs = <q-args>
]], { script_ctx = "/tmp/persist_cmd_define.vim" })
assert_eq("user command define for persistence test", ok_cmd_persist_define, true)

local ok_cmd_persist_call = run_compiled([[
PersistCmd "still here"
]], { script_ctx = "/tmp/persist_cmd_call.vim" })
assert_eq("user command persists across runtime states", ok_cmd_persist_call, true)
assert_eq("persisted command keeps quoted args", Scopes._g.persist_cmd_qargs, "\"still here\"")

local ok_exe_abbrev = run_compiled([[
let g:zipPlugin_ext='*.zip,*.jar'
exe "au BufReadCmd ".g:zipPlugin_ext.' call zip#Browse(expand("<amatch>"))'
]])
assert_eq("execute abbreviation keeps quoted body", ok_exe_abbrev, true)

local ok_verbose_exe = run_compiled([[0verbose exe "let g:verbose_exe_ok = 1"]])
assert_eq("verbose + execute abbreviation", ok_verbose_exe, true)
assert_eq("verbose execute body executed", Scopes._g.verbose_exe_ok, 1)

local ok_verbose_level = run_compiled([[3verbose let g:verbose_level_seen = &verbose]])
assert_eq("verbose count prefix parse", ok_verbose_level, true)
assert_eq("3verbose applies level 3", Scopes._g.verbose_level_seen, 3)

local ok_scope_dict = run_compiled([[
let g:scope_probe = 12
let g:scope_get = get(g:, 'scope_probe', -1)
let g:scope_missing = get(g:, 'scope_probe_missing', 77)
]])
assert_eq("scope dict reference parse", ok_scope_dict, true)
assert_eq("get(g:, key, default)", Scopes._g.scope_get, 12)
assert_eq("get(g:, missing, default)", Scopes._g.scope_missing, 77)

local ok_bare_scope = run_compiled([[
let bare_scope_probe = 42
let g:bare_scope_exists = exists('bare_scope_probe')
let g:bare_scope_read = bare_scope_probe
let s:bare_script_only = 99
let g:bare_scope_script_hidden = exists('bare_script_only')
]])
assert_eq("bare assignment run", ok_bare_scope, true)
assert_eq("bare assignment stored globally", Scopes._g.bare_scope_probe, 42)
assert_eq("exists() sees bare global", Scopes._g.bare_scope_exists, 1)
assert_eq("bare expression reads global", Scopes._g.bare_scope_read, 42)
assert_eq("bare name does not read s: vars", Scopes._g.bare_scope_script_hidden, 0)

local ok_bare_unlet = run_compiled([[
unlet bare_scope_probe
let g:bare_scope_after_unlet = exists('bare_scope_probe')
]])
assert_eq("bare unlet run", ok_bare_unlet, true)
assert_eq("bare unlet clears global", Scopes._g.bare_scope_after_unlet, 0)

local ok_script_a = run_compiled([[
function! s:Helper()
  return 'A'
endfunction
function! g:CallScriptA()
  return s:Helper()
endfunction
]], { script_ctx = "/tmp/script_a_ctx.vim" })
assert_eq("script A function definitions", ok_script_a, true)

local ok_script_b = run_compiled([[
function! s:Helper()
  return 'B'
endfunction
let g:script_local_call_ctx = g:CallScriptA()
]], { script_ctx = "/tmp/script_b_ctx.vim" })
assert_eq("cross-script call executes", ok_script_b, true)
assert_eq("callee keeps defining script-local context", Scopes._g.script_local_call_ctx, "A")

local ok_underscore_arg = run_compiled([[
function! foo#ArgUnder(tutor_name)
  let g:underscore_arg_type = type(a:tutor_name)
  let g:underscore_arg_value = a:tutor_name
endfunction
call foo#ArgUnder('abc')
]])
assert_eq("function arg with underscore executes", ok_underscore_arg, true)
assert_eq("underscore arg type is string", Scopes._g.underscore_arg_type, 1)
assert_eq("underscore arg value is preserved", Scopes._g.underscore_arg_value, "abc")

print("autocmd script-state tests: OK")
