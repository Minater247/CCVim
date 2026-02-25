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

local function reset_buffer(lines, name, cursory)
    local buf = Buffer(true, false)
    buf.name = name or "/tmp/put.txt"
    buf.lines = lines
    buf.refcount = 1
    win.buffer = buf
    win.cursorx = 1
    win.cursory = cursory or 1
    return buf
end

do
    reset_buffer({ "one", "two" }, nil, 1)
    registers["unnamed"] = { "linewise", { "u1", "u2" } }
    local ok, rv = run_compiled("put", "/tmp/put_default.vim")
    assert_true("put default register runs", ok == true, err_string(rv))
    assert_lines("put default inserts below current line", win.buffer.lines, { "one", "u1", "u2", "two" })
    assert_eq("put moves cursor to last inserted line", win.cursory, 3)
end

do
    reset_buffer({ "one", "two" }, nil, 2)
    registers["unnamed"] = { "linewise", { "b1", "b2" } }
    local ok, rv = run_compiled("put!", "/tmp/put_bang.vim")
    assert_true("put! runs", ok == true, err_string(rv))
    assert_lines("put! inserts before current line", win.buffer.lines, { "one", "b1", "b2", "two" })
    assert_eq("put! moves cursor to last inserted line", win.cursory, 3)
end

do
    reset_buffer({ "base" }, nil, 1)
    local ok, rv = run_compiled([[
put ='first'
put ='second'
]], "/tmp/put_order_sequential.vim")
    assert_true("sequential put runs", ok == true, err_string(rv))
    assert_lines("sequential put preserves insertion order", win.buffer.lines, { "base", "first", "second" })
end

do
    reset_buffer({ "one", "two" }, nil, 1)
    registers["a"] = { "linewise", { "A" } }
    local ok, rv = run_compiled("1pu a", "/tmp/put_abbrev_reg.vim")
    assert_true("put abbreviation with register runs", ok == true, err_string(rv))
    assert_lines("line address inserts after addressed line", win.buffer.lines, { "one", "A", "two" })
end

do
    reset_buffer({ "one", "two" }, nil, 1)
    registers["a"] = { "linewise", { "TOP" } }
    local ok, rv = run_compiled("0put a", "/tmp/put_zero.vim")
    assert_true("0put runs", ok == true, err_string(rv))
    assert_lines("0put inserts before first line", win.buffer.lines, { "TOP", "one", "two" })
end

do
    reset_buffer({ "one" }, nil, 1)
    local ok, rv = run_compiled([[put ='x' .. 'y']], "/tmp/put_expr.vim")
    assert_true("put expression register runs", ok == true, err_string(rv))
    assert_lines("put expression inserts evaluated result", win.buffer.lines, { "one", "xy" })
end

do
    reset_buffer({ "one" }, nil, 1)
    local ok, rv = run_compiled([[
put ='keep'
$put =
]], "/tmp/put_expr_reuse.vim")
    assert_true("put expression reuse runs", ok == true, err_string(rv))
    assert_lines("put = reuses previous expression", win.buffer.lines, { "one", "keep", "keep" })
end

do
    reset_buffer({ "one" }, nil, 1)
    registers["a"] = { "inline", { "i1", "i2" } }
    local ok, rv = run_compiled("put a", "/tmp/put_inline.vim")
    assert_true("put inline register runs", ok == true, err_string(rv))
    assert_lines("inline register put is linewise", win.buffer.lines, { "one", "i1", "i2" })
end

do
    reset_buffer({ "one" }, nil, 1)
    registers["a"] = { "charwise", "c1\nc2" }
    local ok, rv = run_compiled("put a", "/tmp/put_charwise.vim")
    assert_true("put charwise register runs", ok == true, err_string(rv))
    assert_lines("charwise register put splits newlines", win.buffer.lines, { "one", "c1", "c2" })
end

do
    reset_buffer({ "one" }, "/tmp/current_name.txt", 1)
    local ok, rv = run_compiled("put %", "/tmp/put_percent.vim")
    assert_true("put % runs", ok == true, err_string(rv))
    assert_lines("put % inserts current buffer name", win.buffer.lines, { "one", "/tmp/current_name.txt" })
end

do
    reset_buffer({ "one", "two", "three" }, nil, 1)
    local ok, rv = run_compiled([[
3
put ='tail'
]], "/tmp/put_address_only.vim")
    assert_true("address-only command before put runs", ok == true, err_string(rv))
    assert_lines("address-only command moves cursor for put", win.buffer.lines, { "one", "two", "three", "tail" })
end

do
    reset_buffer({ "one", "two", "three" }, nil, 1)
    local ok, rv = run_compiled([[
keepj 2
put ='after-two'
]], "/tmp/put_keepj_address.vim")
    assert_true("keepj address command before put runs", ok == true, err_string(rv))
    assert_lines("keepj address command moves cursor for put", win.buffer.lines, { "one", "two", "after-two", "three" })
end

do
    reset_buffer({ "one" }, nil, 1)
    local ok, rv = run_compiled([[put ='\" header']], "/tmp/put_single_quote_backslash_quote.vim")
    assert_true("single-quoted backslash-doublequote expression runs", ok == true, err_string(rv))
    assert_lines("single-quoted backslash-doublequote yields literal quote", win.buffer.lines, { "one", "\" header" })
end

do
    reset_buffer({ "one" }, nil, 1)
    registers["z"] = nil
    local ok, rv = run_compiled("put z", "/tmp/put_missing_reg.vim")
    assert_true("put missing register fails with E353", ok == false and err_string(rv):find("E353", 1, true) ~= nil, err_string(rv))
end

do
    reset_buffer({ "one" }, nil, 1)
    local ok, rv = run_compiled("put aa", "/tmp/put_bad_arg.vim")
    assert_true("put invalid arg fails with E474", ok == false and err_string(rv):find("E474", 1, true) ~= nil, err_string(rv))
end

print("put runtime tests: OK")
