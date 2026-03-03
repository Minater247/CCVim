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
        ["lib.key"] = {
            strtoseq = function(s)
                local out = {}
                for i = 1, #s do
                    out[#out + 1] = s:sub(i, i)
                end
                return out
            end,
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

local Options = mock.loadModule("lib.options")
_G.options = Options
local Buffer = mock.loadModule("layout.buffer")

local function new_win(winnr, buf)
    return {
        winnr = winnr,
        buffer = buf,
        opts = {},
        cursorx = 1,
        cursory = 1,
        need_redraw = false,
        cursorSet = function(self, x, y)
            self.cursorx = x
            self.cursory = y
        end,
    }
end

local buf1 = Buffer(true, false)
buf1.name = "/tmp/redrawstatus_a"
buf1.lines = { "a" }
buf1.refcount = 1

local buf2 = Buffer(true, false)
buf2.name = "/tmp/redrawstatus_b"
buf2.lines = { "b" }
buf2.refcount = 1

local win1 = new_win(1, buf1)
local win2 = new_win(2, buf2)

windows[1] = win1
windows[2] = win2
tabpages[1].windows = { win1, win2 }
curtp = 1
curwin = 1

do
    need_redraw = false
    what_redraw = {}
    win1.need_redraw = false
    win2.need_redraw = false

    local ok, out = run_compiled("redrawstatus", "/tmp/redrawstatus_runtime.vim")
    assert_true("redrawstatus runs", ok == true, tostring(out))
    assert_eq("redrawstatus marks current window", win1.need_redraw, true)
    assert_eq("redrawstatus does not mark other window", win2.need_redraw, false)
    assert_eq("redrawstatus marks commandline redraw", what_redraw.commandline, true)
end

do
    need_redraw = false
    what_redraw = {}
    win1.need_redraw = false
    win2.need_redraw = false

    local ok, out = run_compiled("redrawstatus!", "/tmp/redrawstatus_bang_runtime.vim")
    assert_true("redrawstatus! runs", ok == true, tostring(out))
    assert_eq("redrawstatus! marks first window", win1.need_redraw, true)
    assert_eq("redrawstatus! marks second window", win2.need_redraw, true)
    assert_eq("redrawstatus! marks windows redraw", what_redraw.windows, true)
    assert_eq("redrawstatus! marks commandline redraw", what_redraw.commandline, true)
end

do
    need_redraw = false
    what_redraw = {}
    win1.need_redraw = false
    win2.need_redraw = false

    local ok, out = run_compiled("redraws", "/tmp/redrawstatus_abbrev_runtime.vim")
    assert_true("redrawstatus abbreviation runs", ok == true, tostring(out))
    assert_eq("redraws marks current window", win1.need_redraw, true)
    assert_eq("redraws sets commandline redraw", what_redraw.commandline, true)
end

do
    need_redraw = false
    what_redraw = {}
    local ok, out = run_compiled("redrawtabline", "/tmp/redrawtabline_runtime.vim")
    assert_true("redrawtabline runs", ok == true, tostring(out))
    assert_eq("redrawtabline requests tabline redraw", what_redraw.tabline, true)
end

print("redrawstatus runtime tests: OK")
