local MockEnv = require("vim.tests.test_mocks")

local echoed = {}
local exmsg_stub = {
    messages = {},
    echo = function(message)
        echoed[#echoed + 1] = tostring(message or "")
    end,
    echon = function(message)
        echoed[#echoed + 1] = tostring(message or "")
    end,
    echomsg = function(message)
        echoed[#echoed + 1] = tostring(message or "")
    end,
    echoerr = function(message)
        echoed[#echoed + 1] = tostring(message or "")
    end,
    echohl = function() end,
    PushSilent = function() end,
    PushUnsilent = function() end,
    PopSilent = function() end,
    _writeWithHL = function() end,
    StartRedir = function() end,
    EndRedir = function() return true end,
}

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.exmsg"] = function() return exmsg_stub end,
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
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
            MatchCommand = function() return true end,
            OnWindowBufferChanged = function() end,
        },
        ["vim.lib.autocmd"] = {
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
    local g = table.concat(got, "\n")
    local w = table.concat(want, "\n")
    assert_eq(label, g, w)
end

local function err_string(err)
    if type(err) == "table" and type(err.toString) == "function" then
        return err:toString()
    end
    return tostring(err)
end

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
local Compiler = mock.loadModule("vim.lib.excmd.compiler")
local Runtime = mock.loadModule("vim.lib.excmd.runtime")
local Scopes = mock.loadModule("vim.lib.luaapi.scopes")
local Buffer = mock.loadModule("vim.layout.buffer")
local Fn = mock.loadModule("vim.lib.luaapi.fn")

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

local function reset_buffer(lines, cursor)
    local buf = Buffer(true, false)
    buf.name = "/tmp/sub_global.txt"
    buf.lines = lines
    buf.refcount = 1
    win.buffer = buf
    win.cursorx = 1
    win.cursory = cursor or 1
    return buf
end

do
    reset_buffer({ "foo foo", "bar" }, 1)
    local ok, rv = run_compiled("s/foo/baz/", "/tmp/sub_basic.vim")
    assert_true("substitute basic executes", ok == true, err_string(rv))
    assert_lines("substitute basic line update", win.buffer.lines, { "baz foo", "bar" })
end

do
    Options.set("gdefault", false)
    reset_buffer({ "aaaa" }, 1)
    local ok, rv = run_compiled("s/a/x/g", "/tmp/sub_set_last_flags.vim")
    assert_true("substitute set g flag executes", ok == true, err_string(rv))
    assert_lines("substitute set g flag result", win.buffer.lines, { "xxxx" })

    reset_buffer({ "aaaa" }, 1)
    ok, rv = run_compiled("s", "/tmp/sub_repeat_without_flags.vim")
    assert_true("substitute repeat executes", ok == true, err_string(rv))
    assert_lines("substitute repeat drops previous g flag", win.buffer.lines, { "xaaa" })

    reset_buffer({ "aaaa" }, 1)
    ok, rv = run_compiled("s&", "/tmp/sub_delim_ampersand.vim")
    assert_true("substitute ampersand delimiter executes", ok == true, err_string(rv))
    assert_lines("substitute ampersand delimiter removes first match", win.buffer.lines, { "aaa" })
end

do
    reset_buffer({ "a1", "a2", "b3" }, 1)
    local ok, rv = run_compiled("%s/a/x/g", "/tmp/sub_range_global.vim")
    assert_true("substitute range + g executes", ok == true, err_string(rv))
    assert_lines("substitute range + g result", win.buffer.lines, { "x1", "x2", "b3" })
end

do
    reset_buffer({ "abc" }, 1)
    local ok, rv = run_compiled("s/z/y/", "/tmp/sub_not_found.vim")
    local msg = err_string(rv)
    assert_true("substitute missing pattern fails with E486", ok == false and msg:find("E486", 1, true) ~= nil, msg)
end

do
    reset_buffer({ "abc" }, 1)
    local ok, rv = run_compiled("s/z/y/e", "/tmp/sub_not_found_e.vim")
    assert_true("substitute e flag suppresses no-match", ok == true, err_string(rv))
    assert_lines("substitute e keeps text", win.buffer.lines, { "abc" })
end

do
    reset_buffer({ "abc 123" }, 1)
    local ok, rv = run_compiled([[s/[0-9]\+/[\0]/]], "/tmp/sub_match_ref.vim")
    assert_true("substitute \\0 executes", ok == true, err_string(rv))
    assert_lines("substitute \\0 result", win.buffer.lines, { "abc [123]" })
end

do
    reset_buffer({ "abc 123" }, 1)
    local ok, rv = run_compiled([[s/[a-z]\+/<&>/]], "/tmp/sub_ampersand_ref.vim")
    assert_true("substitute & executes", ok == true, err_string(rv))
    assert_lines("substitute & result", win.buffer.lines, { "<abc> 123" })
end

do
    reset_buffer({ "aa", "bb", "aa" }, 1)
    local ok, rv = run_compiled("g/aa/s/a/x/g", "/tmp/global_substitute.vim")
    assert_true("global with inner substitute executes", ok == true, err_string(rv))
    assert_lines("global with inner substitute result", win.buffer.lines, { "xx", "bb", "xx" })
end

do
    reset_buffer({ "foo foo", "bar" }, 1)
    local ok, rv = run_compiled("g/foo/s//baz/g", "/tmp/global_sets_subpat.vim")
    assert_true("global sets substitute pattern for s//", ok == true, err_string(rv))
    assert_lines("global + s// uses global pattern", win.buffer.lines, { "baz baz", "bar" })
end

do
    reset_buffer({ "keep", "drop", "keep" }, 1)
    local ok, rv = run_compiled("g!/keep/d", "/tmp/global_bang_delete.vim")
    assert_true("global! delete executes", ok == true, err_string(rv))
    assert_lines("global! delete keeps only matching lines", win.buffer.lines, { "keep", "keep" })
end

do
    reset_buffer({ "one", "two", "one" }, 1)
    echoed = {}
    local ok, rv = run_compiled("g/one/", "/tmp/global_default_print.vim")
    assert_true("global default command executes", ok == true, err_string(rv))
    assert_eq("global default print first", echoed[1], "one")
    assert_eq("global default print second", echoed[2], "one")
end

do
    reset_buffer({ "ok", "bad", "ok" }, 1)
    local ok, rv = run_compiled(
        "g/./if getline('.') == 'bad'|call does_not_exist()|endif|s/ok/OK/",
        "/tmp/global_continue_on_error.vim")
    assert_true("global continues after per-line command error", ok == true, err_string(rv))
    assert_lines("global continue keeps processing later lines", win.buffer.lines, { "OK", "bad", "OK" })
end

do
    assert_eq("histdel slash index stub success", Fn.histdel("/", -1), 1)
    assert_eq("histdel cmd stub success", Fn.histdel("cmd"), 1)
end

print("global/substitute/histdel runtime tests: OK")
