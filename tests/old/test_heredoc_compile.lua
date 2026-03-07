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

local function run_compiled(script, opts)
    opts = opts or {}
    local durable = Runtime.CaptureDurableScriptState({ script_ctx = opts.script_ctx }) or { s = {}, funcs = {} }
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
    return true, rv
end

local ok, rv = run_compiled([[
let s:aria =<< trim END
  alpha
  beta
END
let s:aria_deprecated =<< trim END
  gamma
END
call extend(s:aria, s:aria_deprecated)
let g:heredoc_joined = s:aria->join('|')
]], { script_ctx = "/tmp/heredoc_compile.vim" })
if not ok then
    error(("FAIL heredoc script run: %s"):format(tostring(rv)))
end
assert_eq("heredoc list merged and joined", Scopes._g.heredoc_joined, "alpha|beta|gamma")

print("heredoc compile tests: OK")
