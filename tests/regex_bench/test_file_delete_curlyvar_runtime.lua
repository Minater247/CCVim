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

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s: expected true, got false"):format(label))
    end
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

local function run_compiled(script, opts)
    opts = opts or {}
    local durable = opts.durable or { s = {}, funcs = {}, g = Scopes._g, script_ctx = opts.script_ctx }
    local state = Runtime.MakeRuntimeState(durable)
    state.g = durable.g
    local runtime = Runtime.new(state)

    local code, err = Compiler.compile_script(script, { state = state })
    if not code then return false, err, state end

    local env = setmetatable({ runtime = runtime, _G = _G }, { __index = _G })
    local chunk, lerr = load(code, "excmd_compiled", "t", env)
    if not chunk then return false, lerr, state end

    local fn = chunk()
    local ok, rv = pcall(fn, state, runtime)
    if not ok then return false, rv, state end
    return true, rv, state
end

local function reset_buffer(lines)
    local buf = Buffer(true, false)
    buf.name = "/tmp/original.txt"
    buf.lines = lines
    buf.refcount = 1
    win.buffer = buf
    win.cursorx = 1
    win.cursory = 1
    return buf
end

do
    local buf = reset_buffer({ "alpha", "beta", "gamma" })
    echoed = {}
    local ok, rv = run_compiled("f .", { script_ctx = "/tmp/file_abbrev.vim" })
    assert_true("file abbreviation runs", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("file command renames current buffer", buf.name, ".")
    assert_eq("file command sets alternate file buffer name", win.altbuf.name, "/tmp/original.txt")
    assert_eq("file command creates unlisted alt buffer", win.altbuf.opts.buflisted, false)
end

do
    local buf = reset_buffer({ "line" })
    echoed = {}
    local ok, rv = run_compiled("0file", { script_ctx = "/tmp/zero_file.vim" })
    assert_true("0file executes", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("0file clears current buffer name", buf.name, "")
    assert_eq("0file keeps old name in alternate", win.altbuf.name, "/tmp/original.txt")
end

do
    local longname = "/tmp/" .. string.rep("very_long_segment_", 8) .. ".txt"
    local buf = reset_buffer({ "one" })
    buf.name = longname
    Options.set("shortmess", "t")
    echoed = {}
    local ok, rv = run_compiled("file", { script_ctx = "/tmp/file_status_trunc.vim" })
    assert_true("file status executes", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_true("file status truncates with shortmess t", echoed[#echoed]:find("\"<", 1, true) ~= nil)
    echoed = {}
    ok, rv = run_compiled("file!", { script_ctx = "/tmp/file_status_full.vim" })
    assert_true("file! status executes", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_true("file! shows full name", echoed[#echoed]:find(longname, 1, true) ~= nil)
end

do
    reset_buffer({ "one", "two", "three", "four" })
    registers["unnamed"] = { "linewise", { "kept" } }
    registers[1] = { "linewise", { "old1" } }
    local ok, rv = run_compiled("delete 2", { script_ctx = "/tmp/delete_count.vim" })
    assert_true("delete count runs", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("delete count removes two lines from cursor", win.buffer.lines[1], "three")
    assert_eq("delete count updates unnamed register first line", registers["unnamed"][2][1], "one")
    assert_eq("delete count updates numbered register first line", registers[1][2][1], "one")
end

do
    reset_buffer({ "red", "blue", "green" })
    registers[1] = { "linewise", { "keep-numbered" } }
    local ok, rv = run_compiled("delete a 2", { script_ctx = "/tmp/delete_named_reg.vim" })
    assert_true("delete named register runs", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("delete named register stores text", registers["a"][2][1], "red")
    assert_eq("delete named register does not rotate numbered register", registers[1][2][1], "keep-numbered")
end

do
    reset_buffer({ "one", "two", "three" })
    registers["unnamed"] = { "linewise", { "kept" } }
    local ok, rv = run_compiled("%d _", { script_ctx = "/tmp/delete_percent.vim" })
    assert_true("delete abbreviation runs", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("percent delete leaves one empty line", #win.buffer.lines, 1)
    assert_eq("percent delete line content", win.buffer.lines[1], "")
    assert_eq("blackhole delete preserves unnamed register", registers["unnamed"][2][1], "kept")
end

do
    reset_buffer({ "gone", "\ta" })
    echoed = {}
    local ok, rv = run_compiled("dp", { script_ctx = "/tmp/delete_print.vim" })
    assert_true("dp executes", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("dp prints current line", echoed[#echoed], "\ta")
end

do
    reset_buffer({ "gone", "\ta" })
    echoed = {}
    local ok, rv = run_compiled("dell", { script_ctx = "/tmp/delete_list.vim" })
    assert_true("dell executes", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("dell lists current line", echoed[#echoed], "^Ia$")
end

do
    local buf = reset_buffer({ "x" })
    local key = "netrwmarkfilemtch_" .. tostring(buf.bufnr)
    local durable = {
        s = {
            [key] = "match",
        },
        funcs = {},
        g = Scopes._g,
        script_ctx = "/tmp/curly_var_expr.vim",
    }
    local ok, rv = run_compiled([[
let g:curly_var_probe = exists("s:netrwmarkfilemtch_{bufnr('%')}") && s:netrwmarkfilemtch_{bufnr("%")} != ""
]], { durable = durable, script_ctx = "/tmp/curly_var_expr.vim" })
    assert_true("curly var expression runs", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("curly var expression evaluates true", Scopes._g.curly_var_probe, 1)
end

do
    local buf = reset_buffer({ "one" })
    buf.name = nil
    local target = "/tmp/drop_nil_name_target.txt"
    local ok, rv = run_compiled("drop " .. target, { script_ctx = "/tmp/drop_nil_name_runtime.vim" })
    assert_true("drop handles nil current buffer name", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("drop updates current buffer to target", win.buffer.name, target)
end

do
    reset_buffer({ "one" })
    local target = "/tmp/drop escaped space target.txt"
    local escaped = target:gsub(" ", "\\ ")
    local ok, rv = run_compiled("drop " .. escaped, { script_ctx = "/tmp/drop_escaped_space_runtime.vim" })
    assert_true("drop accepts escaped spaces", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("drop preserves escaped-space target", win.buffer.name, target)
end

do
    reset_buffer({ "one" })
    local target = "/tmp/drop fnameescape target.txt"
    local script = ([[
let g:drop_target = '%s'
execute 'drop ' . fnameescape(g:drop_target)
]]):format(target)
    local ok, rv = run_compiled(script, { script_ctx = "/tmp/drop_fnameescape_runtime.vim" })
    assert_true("drop + fnameescape accepts spaces", ok == true)
    if ok ~= true then error(err_string(rv)) end
    assert_eq("drop + fnameescape preserves full target", win.buffer.name, target)
end

print("file/delete/curlyvar runtime tests: OK")
