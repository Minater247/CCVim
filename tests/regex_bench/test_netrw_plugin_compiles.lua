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

local function read_file(path)
    local f, err = io.open(path, "r")
    if not f then
        error("open failed: " .. tostring(err))
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s: expected true, got false"):format(label))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")

local src_path = "vim/runtime/pack/dist/opt/netrw/plugin/netrwPlugin.vim"
local script = read_file(src_path)

local durable = Runtime.CaptureDurableScriptState({ script_ctx = src_path }) or { s = {}, funcs = {} }
durable.g = durable.g or Scopes._g

local state = Runtime.MakeRuntimeState(durable)
state.g = durable.g
local runtime = Runtime.new(state)

local code, err = Compiler.compile_script(script, { state = state })
assert_true("compile netrw plugin", code ~= nil)
if not code then
    error(tostring(err))
end

local env = setmetatable({ runtime = runtime, _G = _G }, { __index = _G })
local chunk, lerr = load(code, "excmd_compiled", "t", env)
assert_true("load compiled netrw plugin", chunk ~= nil)
if not chunk then
    error(tostring(lerr))
end

print("netrw plugin compile/load test: OK")
