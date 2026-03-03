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
        ["lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["lib.sign"] = {
            on_lines_changed = function() end,
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

local function assert_lines(label, got, want)
    local joined_got = table.concat(got, "\n")
    local joined_want = table.concat(want, "\n")
    assert_eq(label, joined_got, joined_want)
end

local function err_string(err)
    if type(err) == "table" and type(err.toString) == "function" then
        return err:toString()
    end
    return tostring(err)
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Buffer = mock.loadModule("layout.buffer")
mock.loadModule("lib.command")
mock.loadModule("lib.mappings")

local win = {
    winnr = 1,
    opts = {},
    cursorx = 1,
    cursory = 1,
    cursorSet = function(self, x, y)
        self.cursorx = x
        self.cursory = y
    end,
    cursorSetX = function(self, x)
        self.cursorx = x
    end,
    cursorSetY = function(self, y)
        self.cursory = y
    end,
    cursorMove = function(self, dx, dy)
        self.cursorx = self.cursorx + dx
        self.cursory = self.cursory + dy
    end,
}

windows[1] = win
tabpages[1].windows = { win }
curtp = 1
curwin = 1
vimmode = "normal"

local function reset_buffer(lines)
    local buf = Buffer(true, false)
    buf.name = "/tmp/undo_runtime.txt"
    buf.lines = lines
    buf.refcount = 1
    buf.opts.modified = false
    buf:undo_clear()
    win.buffer = buf
    win.cursorx = 1
    win.cursory = 1
    return buf
end

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
    local chunk, lerr = load(code, "undo_runtime_compiled", "t", env)
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

local function run_runtime(script, script_ctx)
    return Runtime.run(script, { script_ctx = script_ctx })
end

do
    local buf = reset_buffer({ "one", "two" })
    buf:set_line(1, "ONE", true)
    assert_eq("direct edit changed line", buf.lines[1], "ONE")

    assert_true("undo returns true", buf:undo(win, 1), "undo failed")
    assert_lines("undo restores previous text", buf.lines, { "one", "two" })

    assert_true("redo returns true", buf:redo(win, 1), "redo failed")
    assert_lines("redo reapplies change", buf.lines, { "ONE", "two" })
end

do
    local buf = reset_buffer({ "root" })
    buf:set_line(1, "a", true)
    buf:set_line(1, "b", true)
    assert_true("undo branch step", buf:undo(win, 1), "undo failed")
    assert_lines("branch baseline after undo", buf.lines, { "a" })

    buf:set_line(1, "c", true)
    assert_lines("new branch text", buf.lines, { "c" })
    assert_eq("redo unavailable after branching", buf:redo(win, 1), false)
end

do
    local buf = reset_buffer({ "x", "y" })
    buf:undo_begin(win)
    buf:set_line(1, "X", true)
    buf:set_line(2, "Y", true)
    buf:undo_end(win)

    assert_lines("grouped change applied", buf.lines, { "X", "Y" })
    assert_true("grouped undo succeeds", buf:undo(win, 1), "group undo failed")
    assert_lines("grouped undo restores both lines", buf.lines, { "x", "y" })
end

do
    local buf = reset_buffer({ "persist" })
    Options.set("undolevels", -1, true, win, buf)
    buf:set_line(1, "nohistory", true)
    assert_eq("undo disabled when undolevels=-1", buf:undo(win, 1), false)

    Options.set("undolevels", 1000, true, win, buf)
    buf:set_line(1, "history", true)
    assert_true("undo re-enabled", buf:undo(win, 1), "undo did not resume")
    assert_lines("undo after re-enable", buf.lines, { "nohistory" })
end

do
    local buf = reset_buffer({ "one" })
    buf:set_line(1, "two", true)

    local ok, rv = run_compiled("undo", "/tmp/undo_cmd.vim")
    assert_true("ex undo command runs", ok == true, err_string(rv))
    assert_lines("ex undo restores line", buf.lines, { "one" })

    ok, rv = run_compiled("redo", "/tmp/redo_cmd.vim")
    assert_true("ex redo command runs", ok == true, err_string(rv))
    assert_lines("ex redo reapplies line", buf.lines, { "two" })
end

do
    local buf = reset_buffer({ "one" })
    buf:set_line(1, "two", true)
    buf:set_line(1, "three", true)
    buf:set_line(1, "four", true)

    local ok, rv = run_compiled("undo 2", "/tmp/undo_jump_cmd.vim")
    assert_true("ex undo change-id jump runs", ok == true, err_string(rv))
    assert_lines("ex undo change-id jumps to target state", buf.lines, { "three" })

    ok, rv = run_compiled("redo 1", "/tmp/redo_count_cmd.vim")
    assert_true("ex redo count runs", ok == true, err_string(rv))
    assert_lines("ex redo count reapplies one", buf.lines, { "four" })
end

do
    reset_buffer({ "one" })
    local ok, rv = run_compiled("undo nope", "/tmp/undo_bad_arg.vim")
    assert_true("ex undo invalid arg fails E474", ok == false and err_string(rv):find("E474", 1, true) ~= nil, err_string(rv))
end

do
    local buf = reset_buffer({ "abc" })
    local ok, rv = run_runtime([[
normal! x
normal! u
normal! <C-r>
]], "/tmp/undo_normal_angle_ctrlr.vim")
    assert_true("normal angle ctrl-r script runs", ok == true, err_string(rv))
    assert_lines("normal angle ctrl-r is literal (no redo)", buf.lines, { "abc" })
    assert_eq("normal angle ctrl-r keeps clean modified", buf.opts.modified, false)
end

do
    local buf = reset_buffer({ "abc" })
    local ok, rv = run_runtime([[
normal! x
normal! u
execute "normal! \x12"
]], "/tmp/undo_normal_raw_ctrlr.vim")
    assert_true("normal raw ctrl-r script runs", ok == true, err_string(rv))
    assert_lines("normal raw ctrl-r redoes", buf.lines, { "bc" })
    assert_eq("normal raw ctrl-r marks modified", buf.opts.modified, true)
end

do
    local buf = reset_buffer({ "abc" })
    local ok, rv = run_runtime([[
normal! x
normal! x
normal! U
normal! u
]], "/tmp/undo_normal_u_contiguous.vim")
    assert_true("normal U contiguous script runs", ok == true, err_string(rv))
    assert_lines("normal U contiguous parity", buf.lines, { "abc" })
    assert_eq("normal U contiguous modified parity", buf.opts.modified, false)
end

do
    local buf = reset_buffer({ "abc", "def" })
    local ok, rv = run_runtime([[
normal! x
normal! jx
normal! kx
normal! U
]], "/tmp/undo_normal_u_noncontiguous.vim")
    assert_true("normal U noncontiguous script runs", ok == true, err_string(rv))
    assert_lines("normal U noncontiguous parity", buf.lines, { "bc", "ef" })
    assert_eq("normal U noncontiguous modified parity", buf.opts.modified, true)
end

print("undo runtime tests: OK")
