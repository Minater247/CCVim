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

_G.screen = { width = 80, height = 24 }
term.setCursorPos = term.setCursorPos or function() end
term.clearLine = term.clearLine or function() end
term.blit = term.blit or function() end
term.write = term.write or function() end
term.getSize = term.getSize or function() return 80, 24 end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local function assert_lines(label, got, want)
    local g = table.concat(got or {}, "\n")
    local w = table.concat(want or {}, "\n")
    if g ~= w then
        error(("FAIL %s: expected\n%s\n--- got\n%s"):format(label, w, g))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Buffer = mock.loadModule("layout.buffer")

local win = mock.create_window(1, mock.create_buffer(0, "/tmp/dummy.txt", {""}), {})
tabpages[1].windows = { win }
curtp = 1
curwin = 1

local function run_compiled(script, script_ctx)
    local durable = { s = {}, funcs = {}, g = Scopes._g, script_ctx = script_ctx }
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

local function reset_buffer(lines, cursory)
    local buf = Buffer(true, false)
    buf.name = "/tmp/sort_vglobal.txt"
    buf.lines = lines
    buf.refcount = 1
    win.buffer = buf
    win.cursorx = 1
    win.cursory = cursory or 1
    return buf
end

do
    reset_buffer({ "hdr", "003 cc", "001 aa", "002 bb" }, 1)
    local ok, rv = run_compiled("2,$sort", "/tmp/sort_range.vim")
    assert_true("range sort runs", ok == true, tostring(rv))
    assert_lines("range sort orders lines", win.buffer.lines, { "hdr", "001 aa", "002 bb", "003 cc" })
end

do
    reset_buffer({ "003 cc", "001 aa", "002 bb" }, 2)
    local ok, rv = run_compiled("sort", "/tmp/sort_default_whole_buffer.vim")
    assert_true("default sort runs", ok == true, tostring(rv))
    assert_lines("default sort uses whole buffer", win.buffer.lines, { "001 aa", "002 bb", "003 cc" })
end

do
    reset_buffer({ "hdr", "001 aa", "002 bb", "003 cc" }, 1)
    local ok, rv = run_compiled("2,$sort!", "/tmp/sort_range_reverse.vim")
    assert_true("range reverse sort runs", ok == true, tostring(rv))
    assert_lines("range reverse sort orders lines", win.buffer.lines, { "hdr", "003 cc", "002 bb", "001 aa" })
end

do
    reset_buffer({ "a/", "b", "c." }, 1)
    local ok, rv = run_compiled("1,$v+[./]+s/^/X/", "/tmp/vglobal_with_substitute.vim")
    assert_true("vglobal command runs", ok == true, tostring(rv))
    assert_lines("vglobal applies command to non-matches", win.buffer.lines, { "a/", "Xb", "c." })
end

print("sort + vglobal runtime tests: OK")
