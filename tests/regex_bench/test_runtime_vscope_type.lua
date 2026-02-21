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
        ["vim.lib.autocmd"] = {
            Run = function() return 0 end,
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
        ["vim.lib.tags"] = {
            SearchFile = function() return nil end,
        },
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
        ["vim.lib.key"] = {
            strtoseq = function() return {} end,
        },
        ["vim.layout.buffer"] = {},
        ["vim.layout.window"] = {},
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

local Options = mock.loadModule("vim.lib.options")
_G.options = Options

local Runtime = mock.loadModule("vim.lib.excmd.runtime")
local Scopes = mock.loadModule("vim.lib.luaapi.scopes")

local test_buf = mock.create_buffer(1, "/tmp/test_runtime_vscope_type.vim", { "" }, {})
local test_win = mock.create_window(1, test_buf, {})
mock.create_tabpage(1, { test_win }, {})
curtp = 1
curwin = 1

local state = {
    g = Scopes._g,
    s = {},
    v = Scopes._v,
    funcs = Runtime._FUNCS,
    frames = {},
    commands = {},
}

local ok, rv = Runtime.run([[
function! TestVScope(enable)
  if a:enable
    let g:v_scope_last = 1
  else
    let g:v_scope_last = 0
  endif
endfunction
call TestVScope(v:true)
let g:v_scope_true = g:v_scope_last
call TestVScope(v:false)
let g:v_scope_false = g:v_scope_last
let g:type_empty_dict = type({})
let g:type_empty_list = type([])
]], {
    state = state,
    script_ctx = "/tmp/test_runtime_vscope_type.vim",
})

assert_true("runtime run succeeds", ok == true, rv)
assert_eq("v:true resolves truthy in shared v scope", Scopes._g.v_scope_true, 1)
assert_eq("v:false resolves falsey in shared v scope", Scopes._g.v_scope_false, 0)
assert_eq("type({}) reports dict", Scopes._g.type_empty_dict, 4)
assert_eq("type([]) reports list", Scopes._g.type_empty_list, 3)

print("runtime vscope/type tests: OK")
