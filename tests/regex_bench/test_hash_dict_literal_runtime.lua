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
        ["vim.lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
            on_lines_changed = function() end,
        },
    },
})

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
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

local test_buf = mock.create_buffer(1, "/tmp/hash_dict_test.vim", { "" }, {})
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
    if not ok then return false, rv end
    return true, rv, state
end

local script = [[
if !exists('g:help_example_languages')
  let g:help_example_languages = #{ vim: 'vim' }
endif
]]

do
    local ok, rv, state = run_compiled(script, { script_ctx = "/tmp/hash_dict_literal_runtime.vim" })
    assert_true("hash-dict literal script executes", ok == true, rv)

    local tbl = state.g.help_example_languages
    assert_true("g:help_example_languages set", type(tbl) == "table", type(tbl))
    assert_eq("dict key populated", tbl.vim, "vim")
end

do
    local g = Scopes._g
    g.help_example_languages = { vim = "kept" }
    local ok, rv, state = run_compiled(script, { script_ctx = "/tmp/hash_dict_literal_runtime_2.vim" })
    assert_true("hash-dict literal script executes when var exists", ok == true, rv)
    assert_eq("if !exists gate respected", state.g.help_example_languages.vim, "kept")
end

print("hash-dict literal runtime tests: OK")
