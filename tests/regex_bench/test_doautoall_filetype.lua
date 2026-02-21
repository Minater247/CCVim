-- Test doautoall filetype detection
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
        ["vim.lib.tags"] = {
            SearchFile = function() return nil end,
        },
        ["vim.lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["vim.lib.key"] = {
            strtoseq = function() return {} end,
        },
        ["vim.lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["vim.lib.sign"] = {
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

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Autocmd = mock.loadModule("lib.autocmd")
local Scopes = mock.loadModule("lib.luaapi.scopes")

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

local buf1 = mock.create_buffer(1, "/tmp/one.lua", { "" })
local buf2 = mock.create_buffer(2, "/tmp/two.py", { "" })

local win = mock.create_window(1, buf1)
win.cursorx = 1
win.cursory = 1
win.scrolly = { 1, 0 }
win.scrollx = 0
tabpages[1].windows = { win }

Options.set("filetype", "lua", true, win, buf1)
Options.set("filetype", "python", true, win, buf2)

local seen = {}
Autocmd.CreateAutocommand({ "FileType" }, { "*" }, function(info)
    seen[#seen + 1] = ("%d:%s"):format(info.bufnr or 0, tostring(info.match or ""))
end, nil, nil, false, false, nil, nil)

local ok, rv = run_compiled("doautoall FileType")
assert_true("doautoall command succeeds", ok == true)
if ok ~= true then
    error(tostring(rv))
end

local got = {}
for i = 1, #seen do
    got[seen[i]] = true
end

assert_true("buf1 uses filetype as <amatch>", got["1:lua"] == true)
assert_true("buf2 uses filetype as <amatch>", got["2:python"] == true)

print("doautoall FileType pattern tests: OK")
