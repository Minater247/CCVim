local MockEnv = require("vim.tests.test_mocks")

local mock
local Runtime
local autoload_calls = {}

local scriptsource_stub = {}
function scriptsource_stub.PushContext()
end

function scriptsource_stub.PopContext()
end

function scriptsource_stub.source_runtime(path)
    autoload_calls[#autoload_calls + 1] = path
    Runtime = Runtime or mock.loadModule("lib.excmd.runtime")

    if path == "autoload/demo.vim" then
        Runtime._FUNCS["demo#Loaded"] = {
            params = {},
            body = function(rt)
                rt.state.g.demo_loaded = (rt.state.g.demo_loaded or 0) + 1
                return rt.state.g.demo_loaded
            end,
            kind = "compiled",
        }
        return true
    end

    if path == "autoload/luaauto.vim" then
        return false, "missing"
    end
    if path == "autoload/luaauto.lua" then
        Runtime._FUNCS["luaauto#Loaded"] = {
            params = {},
            body = function(rt)
                rt.state.g.luaauto_loaded = 99
                return 99
            end,
            kind = "compiled",
        }
        return true
    end

    if path == "autoload/proxyauto.vim" then
        Runtime._FUNCS["proxyauto#Loaded"] = {
            params = {},
            body = function()
                return 123
            end,
            kind = "compiled",
        }
        return true
    end
    if path == "autoload/demoexpr.vim" then
        Runtime._FUNCS["demoexpr#Loaded"] = {
            params = {},
            body = function()
                return 55
            end,
            kind = "compiled",
        }
        return true
    end

    return false, "missing"
end

mock = MockEnv.setup({
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
        ["lib.scriptsource"] = scriptsource_stub,
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

local function error_text(err)
    if type(err) == "table" and type(err.toString) == "function" then
        return err:toString()
    end
    return tostring(err)
end

local function clear_calls()
    for i = #autoload_calls, 1, -1 do
        autoload_calls[i] = nil
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local VimFn = mock.loadModule("lib.luaapi.fn")

local test_buf = mock.create_buffer(1, "/tmp/test_autoload.vim", { "" }, {})
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
    return true, rv
end

do
    clear_calls()
    local ok, err = run_compiled("call demo#Loaded()", { script_ctx = "/tmp/autoload_demo.vim" })
    assert_true("autoload via :call (.vim)", ok == true, error_text(err))
    assert_eq("autoload .vim path", autoload_calls[1], "autoload/demo.vim")
    assert_eq("autoload .vim no lua fallback", autoload_calls[2], nil)
    assert_eq("autoload function executed", Scopes._g.demo_loaded, 1)
end

do
    clear_calls()
    local ok, err = run_compiled("call luaauto#Loaded()", { script_ctx = "/tmp/autoload_lua.vim" })
    assert_true("autoload via :call fallback (.lua)", ok == true, error_text(err))
    assert_eq("autoload lua probe", autoload_calls[1], "autoload/luaauto.vim")
    assert_eq("autoload lua fallback", autoload_calls[2], "autoload/luaauto.lua")
    assert_eq("autoload lua function executed", Scopes._g.luaauto_loaded, 99)
end

do
    clear_calls()
    local rv = VimFn._call("proxyauto#Loaded")
    assert_eq("vim.fn proxy autoload return value", rv, 123)
    assert_eq("vim.fn proxy autoload path", autoload_calls[1], "autoload/proxyauto.vim")
    assert_eq("vim.fn proxy no lua fallback", autoload_calls[2], nil)
end

do
    clear_calls()
    local ok, err = run_compiled("let g:expr_autoload = demoexpr#Loaded()", { script_ctx = "/tmp/autoload_expr.vim" })
    assert_true("autoload inside expression", ok == true, error_text(err))
    assert_eq("expression autoload path", autoload_calls[1], "autoload/demoexpr.vim")
    assert_eq("expression autoload value", Scopes._g.expr_autoload, 55)
end

do
    clear_calls()
    local ok, err = run_compiled("call missing#Nope()", { script_ctx = "/tmp/autoload_missing.vim" })
    assert_true("missing autoload keeps E117", (not ok) and error_text(err):match("E117"), error_text(err))
    assert_eq("missing autoload .vim probe", autoload_calls[1], "autoload/missing.vim")
    assert_eq("missing autoload .lua fallback", autoload_calls[2], "autoload/missing.lua")
end

print("autoload function resolution test: OK")
