-- Test option value functions
local MockEnv = require("vim.tests.test_mocks")

-- Set up mock with module stubs
local mock = MockEnv.setup({
    module_stubs = {
        ["lib.exmsg"] = function() return mock.loadModule("lib.excmd.exmsg") end,
        ["layout.buffer"] = {},
        ["lib.highlight"] = {
            GroupExists = function() return false end,
            For = function() return { colors.white, colors.black } end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["lib.autocmd"] = {
            Run = function() return 0 end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_match(label, got, pattern)
    if type(got) ~= "string" or not got:match(pattern) then
        error(("FAIL %s: expected pattern %s, got %s"):format(label, tostring(pattern), tostring(got)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Fn = mock.loadModule("lib.luaapi.fn")
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")

local buf = mock.create_buffer(1, "/tmp/test.txt", { "" })
local win = mock.create_window(1, buf)
win.cursorx = 1
win.cursory = 1
win.scrolly = { 1, 0 }
win.scrollx = 0
tabpages[1].windows = { win }
curwin = 1

local opts = {
    { name = "completefunc", alias = "cfu" },
    { name = "findfunc", alias = "ffu" },
    { name = "omnifunc", alias = "ofu" },
    { name = "operatorfunc", alias = "opfunc" },
    { name = "quickfixtextfunc", alias = "qftf" },
    { name = "tagfunc", alias = "tfu" },
    { name = "thesaurusfunc", alias = "tsrfu" },
}

for i = 1, #opts do
    local spec = opts[i]
    local sval = "MyFunc" .. tostring(i)
    Options.set(spec.alias, sval, false, win, buf)
    assert_eq(spec.name .. " string", Options.get(spec.name, win, buf), sval)

    Options.set(spec.name, function() return i end, false, win, buf)
    assert_match(spec.name .. " lua function", Options.get(spec.name, win, buf), "^<lambda>%d+$")

    local ok = Options.exset_token(spec.alias .. "=function('strlen')", "both", win, buf)
    assert_eq(spec.name .. " :set function()", ok, true)
    assert_eq(spec.name .. " function()", Options.get(spec.name, win, buf), "strlen")

    ok = Options.exset_token(spec.alias .. "=funcref('strlen')", "both", win, buf)
    assert_eq(spec.name .. " :set funcref()", ok, true)
    assert_eq(spec.name .. " funcref()", Options.get(spec.name, win, buf), "strlen")

    ok = Options.exset_token(spec.alias .. "={a\\ ->\\ a}", "both", win, buf)
    assert_eq(spec.name .. " :set lambda", ok, true)
    assert_match(spec.name .. " lambda", Options.get(spec.name, win, buf), "^<lambda>%d+$")

    Options.set(spec.name, nil, false, win, buf)
    assert_eq(spec.name .. " nil clears", Options.get(spec.name, win, buf), "")
end

local named = Fn.fn["function"]("strlen")
Options.set("operatorfunc", named, false, win, buf)
assert_eq("operatorfunc named funcref", Options.get("operatorfunc", win, buf), "strlen")

local named2 = Fn.fn.funcref("strlen")
Options.set("quickfixtextfunc", named2, false, win, buf)
assert_eq("quickfixtextfunc named funcref", Options.get("quickfixtextfunc", win, buf), "strlen")

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

local ok_a, err_a = run_compiled([[
function s:LocalScope()
  return 11
endfunction
set operatorfunc=s:LocalScope
set tagfunc=function('s:LocalScope')
]], { script_ctx = "/tmp/script_a.vim" })
assert_eq("script A run", ok_a, true)
local op_a = Options.get("operatorfunc", win, buf, false, true)
assert_match("script A canonical name", op_a, "^<SNR>%d+_LocalScope$")
assert_eq("script A call through canonical name", Fn._call(op_a), 11)
assert_eq("script A function('s:') canonicalization", Options.get("tagfunc", win, buf), op_a)

local ok_b, err_b = run_compiled([[
function s:LocalScope()
  return 22
endfunction
set quickfixtextfunc=s:LocalScope
]], { script_ctx = "/tmp/script_b.vim" })
assert_eq("script B run", ok_b, true)
local qf_b = Options.get("quickfixtextfunc", win, buf, false, true)
assert_match("script B canonical name", qf_b, "^<SNR>%d+_LocalScope$")
if qf_b == op_a then
    error("FAIL script-local canonical names collided across scripts")
end
assert_eq("script A canonical still resolves to A", Fn._call(op_a), 11)
assert_eq("script B canonical resolves to B", Fn._call(qf_b), 22)
assert_eq("plain s: name hidden outside script context", Fn.fn.exists("*s:LocalScope"), 0)

print("option-value-function tests: OK")
