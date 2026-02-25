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

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: expected true, got false (%s)"):format(label, tostring(detail)))
    end
end

local function err_string(err)
    if type(err) == "table" and type(err.toString) == "function" then
        return err:toString()
    end
    return tostring(err)
end

local function assert_lines(label, got, want)
    local g = table.concat(got, "\n")
    local w = table.concat(want, "\n")
    assert_eq(label, g, w)
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Buffer = mock.loadModule("layout.buffer")

local win = {
    winnr = 1,
    opts = {},
    cursorx = 1,
    cursory = 1,
    cursorSet = function(self, x, y)
        self.cursorx = x
        self.cursory = y
    end,
}

windows[1] = win
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
    buf.name = "/tmp/copy_move.txt"
    buf.lines = lines
    buf.refcount = 1
    win.buffer = buf
    win.cursorx = 1
    win.cursory = cursory or 1
    return buf
end

do
    reset_buffer({ "1", "2", "3", "4", "5", "6" }, 1)
    local ok, rv = run_compiled("2,3copy 5", "/tmp/copy_basic.vim")
    assert_true("copy range runs", ok == true, err_string(rv))
    assert_lines("copy range inserts below destination", win.buffer.lines, { "1", "2", "3", "4", "5", "2", "3", "6" })
    assert_eq("copy moves cursor to last copied line", win.cursory, 7)
end

do
    reset_buffer({ "1", "2", "3", "4", "5", "6" }, 1)
    local ok, rv = run_compiled("2,3t 5", "/tmp/t_alias.vim")
    assert_true("t alias runs", ok == true, err_string(rv))
    assert_lines("t alias matches copy behavior", win.buffer.lines, { "1", "2", "3", "4", "5", "2", "3", "6" })
    assert_eq("t alias moves cursor to last copied line", win.cursory, 7)
end

do
    reset_buffer({ "1", "2", "3" }, 2)
    local ok, rv = run_compiled("copy 0", "/tmp/copy_default_range.vim")
    assert_true("copy default range uses current line", ok == true, err_string(rv))
    assert_lines("copy default current line to top", win.buffer.lines, { "2", "1", "2", "3" })
    assert_eq("copy default updates cursor to inserted line", win.cursory, 1)
end

do
    reset_buffer({ "1", "2", "3", "4", "5", "6" }, 1)
    local ok, rv = run_compiled("2,3move 5", "/tmp/move_down.vim")
    assert_true("move down runs", ok == true, err_string(rv))
    assert_lines("move down inserts block below destination", win.buffer.lines, { "1", "4", "5", "2", "3", "6" })
    assert_eq("move down puts cursor on last moved line", win.cursory, 5)
end

do
    reset_buffer({ "1", "2", "3", "4", "5", "6" }, 1)
    local ok, rv = run_compiled("4,5move 1", "/tmp/move_up.vim")
    assert_true("move up runs", ok == true, err_string(rv))
    assert_lines("move up inserts block near top", win.buffer.lines, { "1", "4", "5", "2", "3", "6" })
    assert_eq("move up puts cursor on last moved line", win.cursory, 3)
end

do
    reset_buffer({ "1", "2", "3", "4", "5", "6" }, 1)
    local ok, rv = run_compiled("2,4move 1", "/tmp/move_noop_before.vim")
    assert_true("move to range start-1 runs", ok == true, err_string(rv))
    assert_lines("move to range start-1 is no-op", win.buffer.lines, { "1", "2", "3", "4", "5", "6" })
    assert_eq("move to range start-1 leaves cursor on range end", win.cursory, 4)
end

do
    reset_buffer({ "1", "2", "3", "4", "5", "6" }, 1)
    local ok, rv = run_compiled("2,4move 4", "/tmp/move_noop_end.vim")
    assert_true("move to range end runs", ok == true, err_string(rv))
    assert_lines("move to range end is no-op", win.buffer.lines, { "1", "2", "3", "4", "5", "6" })
    assert_eq("move to range end leaves cursor on range end", win.cursory, 4)
end

do
    reset_buffer({ "1", "2", "3", "4", "5", "6" }, 1)
    local ok, rv = run_compiled("2,4move 3", "/tmp/move_inside_range.vim")
    local msg = err_string(rv)
    assert_true("move inside range fails with E134", ok == false and msg:find("E134", 1, true) ~= nil, msg)
    assert_lines("move inside range keeps buffer unchanged", win.buffer.lines, { "1", "2", "3", "4", "5", "6" })
    assert_eq("move inside range keeps cursor", win.cursory, 1)
end

do
    reset_buffer({ "1", "2", "3" }, 1)
    local ok, rv = run_compiled("copy", "/tmp/copy_missing_dest.vim")
    local msg = err_string(rv)
    assert_true("copy missing destination fails with E16", ok == false and msg:find("E16", 1, true) ~= nil, msg)
end

do
    reset_buffer({ "1", "2", "3" }, 1)
    local ok, rv = run_compiled("move", "/tmp/move_missing_dest.vim")
    local msg = err_string(rv)
    assert_true("move missing destination fails with E16", ok == false and msg:find("E16", 1, true) ~= nil, msg)
end

do
    reset_buffer({ "1", "2", "3" }, 1)
    local ok, rv = run_compiled("2copy 99", "/tmp/copy_bad_dest.vim")
    local msg = err_string(rv)
    assert_true("copy out-of-range destination fails with E16", ok == false and msg:find("E16", 1, true) ~= nil, msg)
end

print("copy/move runtime tests: OK")
