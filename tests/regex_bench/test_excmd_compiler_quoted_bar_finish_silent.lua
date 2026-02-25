local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.exmsg"] = function() return mock.loadModule("lib.excmd.exmsg") end,
        ["lib.excmd.exmsg"] = {
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
        ["layout.buffer"] = {},
        ["layout.window"] = {},
        ["lib.tags"] = {
            SearchFile = function() return nil end,
        },
        ["lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["lib.key"] = {
            strtoseq = function() return {} end,
        },
        ["lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
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

local function err_string(err)
    if type(err) == "table" then
        if type(err.toString) == "function" then
            return err:toString()
        end
        if err.code then
            return ("code=%s message=%s"):format(tostring(err.code), tostring(err.message))
        end
    end
    return tostring(err)
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

do
    local ok, rv, state, code = run_compiled([[
let s_skip = "1"
execute 'if ' . s_skip . ' | let g:quoted_bar_ok = 42 | endif'
]], { script_ctx = "/tmp/quoted_bar.vim" })
    assert_true("quoted-bar script runs", ok == true)
    if ok ~= true then
        error(tostring(rv))
    end
    assert_true("execute line preserved as single runtime:execute", code:find("runtime:execute", 1, true) ~= nil)
    assert_eq("quoted-bar execute sets g var", state.g.quoted_bar_ok, 42)
end

do
    local ok, rv, state, code = run_compiled([[
let g:finish_seen = 1
finish
let g:finish_seen = 2
]], { script_ctx = "/tmp/finish.vim" })
    assert_true("finish script runs", ok == true)
    if ok ~= true then
        error(tostring(rv))
    end
    assert_eq("finish stops script", state.g.finish_seen, 1)
    assert_true("finish lowered directly", code:find("error(runtime:return_exc(nil))", 1, true) ~= nil)
    assert_true("finish avoids generic command invoke", code:find("runtime:invoke_compiled_command({ name = \"finish\"", 1, true) == nil)
end

do
    local ok, rv, state, code = run_compiled([[
silent let g:silent_seen = 7
]], { script_ctx = "/tmp/silent.vim" })
    if ok ~= true then
        error("silent failure: " .. err_string(rv))
    end
    assert_true("silent script runs", ok == true)
    assert_eq("silent command exists", state.g.silent_seen, 7)
end

do
    local ok, rv, state, code = run_compiled([[
let s:cpo_save = &cpo
let i = -1
if i < 0
  let g:cmp_fast = 1
endif
]], { script_ctx = "/tmp/fast_expr.vim" })
    if ok ~= true then
        error("fast expr failure: " .. err_string(rv))
    end
    assert_eq("option fast path assigns cpo", type(state.s.cpo_save), "string")
    assert_eq("comparison fast path executes", state.g.cmp_fast, 1)
    assert_true("option lowered to runtime:get_option", code:find("runtime:get_option(\"cpo\", \"auto\")", 1, true) ~= nil)
    assert_true("comparison lowered to runtime:cmp", code:find("runtime:cmp(runtime:get_var(\"i\"), \"<\", 0)", 1, true) ~= nil)
    assert_true("comparison no eval_expr", code:find("runtime:eval_expr(\"i < 0\")", 1, true) == nil)
end

do
    local ok, rv, state, code = run_compiled([[
set buftype=terminal
if &buftype ==# 'terminal'
  let g:case_cmp_term_ok = 1
endif
]], { script_ctx = "/tmp/case_cmp_term.vim" })
    assert_true("case-sensitive option comparison runs", ok == true)
    if ok ~= true then
        error("case-sensitive option comparison failure: " .. err_string(rv))
    end
    assert_eq("case-sensitive option comparison branch", state.g.case_cmp_term_ok, 1)
    assert_true("no split RHS '# ...' lowering", code:find("runtime:eval_expr(\"# 'terminal'\")", 1, true) == nil)
    assert_true("==# compiled as full expression", code:find("runtime:eval_expr(\"&buftype ==# 'terminal'\")", 1, true) ~= nil)
end

-- ensure `|` inside a quoted `syn match` pattern is NOT treated as a
-- command separator (regression test for the quoted-bar handling)
do
    local ok, rv, state, code = run_compiled([[
syn match luaError "\<\%(end\|else\|elseif\|then\|until\|in\)\>"
]], { script_ctx = "/tmp/syn_quoted_bar.vim" })
    assert_true("syn match with escaped pipes compiles", ok == true)
    local has_single = code:find("\\%(end\\|else\\|elseif\\|then\\|until\\|in\\)", 1, true) ~= nil
    local has_escaped = code:find("\\\\%(end\\\\|else\\\\|elseif\\\\|then\\\\|until\\\\|in\\\\)", 1, true) ~= nil
    assert_true("pattern preserved in compiled code", has_single or has_escaped)
end

do
    local ok, rv, state, code = run_compiled([[
com! Rexplore if exists("g:rexlocal")|let g:rex_branch='yes'|else|let g:rex_branch='no'|endif
let g:rexlocal = 1
Rexplore
unlet g:rexlocal
Rexplore
]], { script_ctx = "/tmp/command_bar_body.vim" })
    assert_true("command definition with bar body compiles/runs", ok == true)
    if ok ~= true then
        error(tostring(rv))
    end
    assert_true("compiled script has no stray top-level else", code:find("runtime:set_exec_cursor%([^%)]-\"else\"", 1) == nil)
    assert_eq("second command invocation ran else branch", state.g.rex_branch, "no")
end

do
    local ok, rv, state = run_compiled([[
command! -nargs=* KeepjCmd keepj <args>
let g:keepj_cmd_probe = 0
KeepjCmd let g:keepj_cmd_probe = 9
]], { script_ctx = "/tmp/user_cmd_args_expand.vim" })
    assert_true("user command <args> expands and executes", ok == true)
    if ok ~= true then
        error(tostring(rv))
    end
    assert_eq("keepj command expansion executed body", state.g.keepj_cmd_probe, 9)
end

do
    local ok, rv, state = run_compiled([[
command! -nargs=* UArgs let g:uargs_raw = "<args>" | let g:uargs_q = <q-args> | let g:uargs_f = [<f-args>]
UArgs one two
]], { script_ctx = "/tmp/user_cmd_expand_tokens.vim" })
    assert_true("user command token expansion", ok == true)
    if ok ~= true then
        error(tostring(rv))
    end
    assert_eq("expanded <args>", state.g.uargs_raw, "one two")
    assert_eq("expanded <q-args>", state.g.uargs_q, "one two")
    assert_eq("expanded <f-args>[1]", state.g.uargs_f[1], "one")
    assert_eq("expanded <f-args>[2]", state.g.uargs_f[2], "two")
end

do
    local ok, rv, state, code = run_compiled([[
if 1|nmap <buffer> <silent> <nowait> - <Plug>NetrwBrowseUpDir|endif
let g:nmap_bar_split = 1
]], { script_ctx = "/tmp/nmap_bar_split.vim" })
    assert_true("inline if|nmap|endif compiles/runs", ok == true)
    if ok ~= true then
        error(tostring(rv))
    end
    assert_true("nmap arg does not swallow endif", code:find("NetrwBrowseUpDir|endif", 1, true) == nil)
    assert_true("nmap invoke generated", code:find("runtime:invoke_compiled_command({ name = \"nmap\"", 1, true) ~= nil)
    assert_true("nmap qargs preserved", code:find("qargs = \"<buffer> <silent> <nowait> - <Plug>NetrwBrowseUpDir\"", 1, true) ~= nil)
    assert_true("nmap ws args pre-split", code:find("ws_args = { \"<buffer>\", \"<silent>\", \"<nowait>\", \"-\", \"<Plug>NetrwBrowseUpDir\" }", 1, true) ~= nil)
    assert_eq("script continues after inline endif", state.g.nmap_bar_split, 1)
end

do
    local code, err = Compiler.compile_script([[
let s:netrwcnt = 0
windo if getline(2) =~# "Netrw" | let s:netrwcnt= s:netrwcnt + 1 | endif
let g:windo_bar_split = 1
]], { state = {} })
    assert_true("windo inline if|let|endif compiles", code ~= nil)
    if code == nil then
        error(err_string(err))
    end
    assert_true("windo keeps full command chain", code:find("runtime:invoke_compiled_command({ name = \"windo\"", 1, true) ~= nil)
    assert_true("windo qargs preserved", code:find("qargs = \"if getline(2) =~# \\\"Netrw\\\" | let s:netrwcnt= s:netrwcnt + 1 | endif\"", 1, true) ~= nil)
    assert_true("windo arg does not emit top-level endif", code:find("runtime:set_exec_cursor(3, \"endif\", \"endif\", \"\")", 1, true) == nil)
end

do
    local code, err = Compiler.compile_script([[
nnoremap <silent><buffer> [[ m':call search('^\s*\(fu\%[nction]\\|def\)\>', "bW")<CR>
]], { state = {} })
    assert_true("map rhs escaped bar after mark quote does not split command", code ~= nil)
    if code == nil then
        error(err_string(err))
    end
    assert_true("mapping compile emits nnoremap invoke", code:find("runtime:invoke_compiled_command({ name = \"nnoremap\"", 1, true) ~= nil)
    assert_true("mapping compile keeps escaped regex alternation text", code:find("\\\\|def", 1, true) ~= nil)
    assert_true("mapping compile does not create bogus def command", code:find("runtime:invoke_compiled_command({ name = \"def\"", 1, true) == nil)
end

print("excmd compiler quoted-bar/finish/silent tests: OK")
