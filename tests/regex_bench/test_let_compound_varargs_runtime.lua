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
        ["lib.exmsg"] = function() return exmsg_stub end,
        ["lib.excmd.exmsg"] = exmsg_stub,
        ["lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["lib.syntax"] = {
            ParseLinetypes = function() end,
            OwnSyntax = function() end,
            ExecuteCommand = function() return true end,
            SyntimeReport = function() return {} end,
            SyntimeSet = function() end,
            SyntimeClear = function() end,
        },
        ["lib.autocmd"] = {
            Run = function() return 0 end,
        },
    },
})

local Options = mock.loadModule("lib.options")
_G.options = Options

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local function run_compiled(script, script_ctx)
    local Compiler = mock.loadModule("lib.excmd.compiler")
    local Runtime = mock.loadModule("lib.excmd.runtime")
    local Scopes = mock.loadModule("lib.luaapi.scopes")

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
function! s:Collect()
  let r = []
  for filename in ['a', 'b']
    let r += [filename]
  endfor
  return r
endfunction
let g:collect = s:Collect()
]], "/tmp/let_plus_eq.vim")
    assert_true("compound let script runs", ok == true, tostring(out))
    local g = out.state.g
    assert_true(
        "compiled code keeps real lhs for +=",
        out.code:find('runtime:assign("r +",', 1, true) == nil,
        out.code
    )
    assert_true(
        "list += appends first item",
        type(g.collect) == "table" and g.collect[1] == "a",
        tostring(g.collect and g.collect[1])
    )
    assert_true(
        "list += appends second item",
        type(g.collect) == "table" and g.collect[2] == "b",
        tostring(g.collect and g.collect[2])
    )
end

do
    local ok, out = run_compiled([[
function! s:Pick(...)
  let f = a:0 > 0 ? a:1 : 0
  return [a:0, a:000, f]
endfunction
let g:noarg = s:Pick()
let g:witharg = s:Pick(42, 99)
]], "/tmp/vararg_ternary.vim")
    assert_true("vararg script runs", ok == true, tostring(out))
    local g = out.state.g
    assert_true(
        "a:0 on noarg call is zero",
        type(g.noarg) == "table" and g.noarg[1] == 0,
        tostring(g.noarg and g.noarg[1])
    )
    assert_true(
        "ternary fallback uses zero",
        type(g.noarg) == "table" and g.noarg[3] == 0,
        tostring(g.noarg and g.noarg[3])
    )
    assert_true(
        "a:0 on vararg call counts extras",
        type(g.witharg) == "table" and g.witharg[1] == 2,
        tostring(g.witharg and g.witharg[1])
    )
    assert_true(
        "a:000 captures extras",
        type(g.witharg[2]) == "table" and g.witharg[2][1] == 42 and g.witharg[2][2] == 99,
        tostring(g.witharg and g.witharg[2])
    )
    assert_true(
        "ternary picks first extra",
        type(g.witharg) == "table" and g.witharg[3] == 42,
        tostring(g.witharg and g.witharg[3])
    )
end

print("let compound + varargs runtime tests: OK")
