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
        ["vim.lib.exmsg"] = function() return exmsg_stub end,
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
        ["vim.lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["vim.lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["vim.lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["vim.lib.syntax"] = {
            ParseLinetypes = function() end,
            OwnSyntax = function() end,
            ExecuteCommand = function() return true end,
            SyntimeReport = function() return {} end,
            SyntimeSet = function() end,
            SyntimeClear = function() end,
        },
        ["vim.lib.autocmd"] = {
            Run = function() return 0 end,
        },
    },
})

local Options = mock.loadModule("vim.lib.options")
_G.options = Options

local buf = mock.create_buffer(1, "/tmp/a", { "line1" })
mock.create_window(1, buf, {})
_G.curwin = 1
_G.curtp = 1
_G.tabpages = { { opts = {}, tabnr = 1, windows = _G.windows } }

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local function run_compiled(script, script_ctx)
    local Compiler = mock.loadModule("vim.lib.excmd.compiler")
    local Runtime = mock.loadModule("vim.lib.excmd.runtime")
    local Scopes = mock.loadModule("vim.lib.luaapi.scopes")

    local durable = Runtime.CaptureDurableScriptState({ script_ctx = script_ctx }) or { s = {}, funcs = {} }
    durable.g = durable.g or Scopes._g
    local state = Runtime.MakeRuntimeState(durable)
    state.g = durable.g
    local runtime = Runtime.new(state)

    local code, err = Compiler.compile_script(script, { state = state })
    if not code then
        return false, err
    end

    local env = setmetatable({ runtime = runtime, _G = _G }, { __index = _G })
    local chunk, lerr = load(code, "excmd_compiled", "t", env)
    if not chunk then
        return false, lerr
    end

    local fn = chunk()
    local ok, rv = pcall(fn, state, runtime)
    if not ok then
        return false, rv
    end

    return true, { state = state, code = code, rv = rv }
end

do
    local ok, out = run_compiled([[
function! s:SavePosn(posndict)
  if !exists('g:arg_exists_history')
    let g:arg_exists_history = []
  endif
  call add(g:arg_exists_history, exists("a:posndict[bufnr('%')]"))
  if !exists("a:posndict[bufnr('%')]")
    let a:posndict[bufnr('%')] = []
  endif
  call add(g:arg_exists_history, exists("a:posndict[bufnr('%')]"))
  call add(a:posndict[bufnr('%')], {'lnum': 1})
  return a:posndict
endfunction

let g:netrw_posn = {}
call s:SavePosn(g:netrw_posn)
let g:count_after_first = len(g:netrw_posn[bufnr('%')])
call s:SavePosn(g:netrw_posn)
let g:count_after_second = len(g:netrw_posn[bufnr('%')])
]], "/tmp/netrw_saveposn_runtime.vim")

    assert_true("netrw saveposn script runs", ok == true, tostring(out))
    local g = out.state.g
    assert_true("exists() before first set is false", type(g.arg_exists_history) == "table" and g.arg_exists_history[1] == 0,
        tostring(g.arg_exists_history and g.arg_exists_history[1]))
    assert_true("exists() after first set is true", type(g.arg_exists_history) == "table" and g.arg_exists_history[2] == 1,
        tostring(g.arg_exists_history and g.arg_exists_history[2]))
    assert_true("exists() before second set is true", type(g.arg_exists_history) == "table" and g.arg_exists_history[3] == 1,
        tostring(g.arg_exists_history and g.arg_exists_history[3]))
    assert_true("exists() after second set is true", type(g.arg_exists_history) == "table" and g.arg_exists_history[4] == 1,
        tostring(g.arg_exists_history and g.arg_exists_history[4]))
    assert_true("first save adds one entry", g.count_after_first == 1, tostring(g.count_after_first))
    assert_true("second save appends to same list", g.count_after_second == 2, tostring(g.count_after_second))
end

print("netrw saveposn runtime test: OK")
