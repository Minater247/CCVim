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

local key_inputs = {}

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.exmsg"] = function() return exmsg_stub end,
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
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
            strtoseq = function(s)
                key_inputs[#key_inputs + 1] = tostring(s or "")
                return {}
            end,
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

local Options = mock.loadModule("lib.options")
_G.options = Options

local test_buf = mock.create_buffer(1, "/tmp/test_sid_script_local_runtime.vim", { "" }, {})
local test_win = mock.create_window(1, test_buf, {})
mock.create_tabpage(1, { test_win }, {})
curtp = 1
curwin = 1

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
function! s:NetrwGetWord()
  return 'target'
endfunction
function! s:NetrwBrowseChgDir(p1, p2, p3)
  return [a:p1, a:p2, a:p3]
endfunction
function! s:LocalBrowseCheck(x)
  let g:sid_expr_probe = a:x
endfunction
function! s:NetrwSortStyle(flag)
  let g:sid_sort_probe = a:flag
endfunction
call s:LocalBrowseCheck(<SID>NetrwBrowseChgDir(1, <SID>NetrwGetWord(), 1))
call <SID>NetrwSortStyle(7)
let g:sid_direct_word = <SID>NetrwGetWord()
]], "/tmp/sid_expr_runtime.vim")
    assert_true("sid expr script runs", ok == true, tostring(out))
    local g = out.state.g
    assert_true("sid nested expression returns list", type(g.sid_expr_probe) == "table", type(g.sid_expr_probe))
    assert_eq("sid nested expression first arg", g.sid_expr_probe[1], 1)
    assert_eq("sid nested expression second arg", g.sid_expr_probe[2], "target")
    assert_eq("sid nested expression third arg", g.sid_expr_probe[3], 1)
    assert_eq("sid direct :call works", g.sid_sort_probe, 7)
    assert_eq("sid direct expression call works", g.sid_direct_word, "target")
end

do
    key_inputs = {}
    local ok, out = run_compiled([[
nnoremap <buffer> <SID>MapLhs :call <SID>MapRhs()<CR>
nunmap <buffer> <SID>MapLhs
]], "/tmp/sid_map_runtime.vim")
    assert_true("sid map script runs", ok == true, tostring(out))

    assert_true("sid map captured key parsing", #key_inputs >= 3, table.concat(key_inputs, " | "))
    local lhs_entries = {}
    local rhs_entry = nil
    local snr_token_count = 0
    for i = 1, #key_inputs do
        local s = key_inputs[i]
        assert_true("map key text has no literal <SID>", s:find("<SID>", 1, true) == nil, s)
        if s == "<SNR>" then
            snr_token_count = snr_token_count + 1
        end
        if s:find("MapLhs", 1, true) then
            lhs_entries[#lhs_entries + 1] = s
        elseif s:find("MapRhs", 1, true) then
            rhs_entry = s
        end
    end

    assert_true("map lhs seen in map+unmap", #lhs_entries >= 2, table.concat(key_inputs, " | "))
    assert_true("map rhs seen", rhs_entry ~= nil, table.concat(key_inputs, " | "))
    assert_true("map/unmap received <SNR> token", snr_token_count >= 3, table.concat(key_inputs, " | "))

    local rhs_sid = rhs_entry:match("^(%d+)_MapRhs")
    assert_true("map rhs keeps expanded sid suffix", rhs_sid ~= nil, rhs_entry)
    for i = 1, #lhs_entries do
        local lhs_sid = lhs_entries[i]:match("^(%d+)_MapLhs$")
        assert_true("map lhs keeps expanded sid suffix", lhs_sid ~= nil, lhs_entries[i])
        assert_eq("map/unmap <SID> use same sid", lhs_sid, rhs_sid)
    end
end

print("sid script-local runtime tests: OK")
