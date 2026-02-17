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

local normal_calls = {}

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.exmsg"] = function() return exmsg_stub end,
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
        ["vim.lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
            execute_normal_keys = function(seq, opts)
                local text = {}
                for i = 1, #seq do
                    text[#text + 1] = tostring(seq[i])
                end
                normal_calls[#normal_calls + 1] = {
                    text = table.concat(text),
                    remap = not not (opts and opts.remap),
                    line = windows[curwin] and windows[curwin].cursory or -1,
                }
                return true
            end,
        },
        ["vim.lib.key"] = {
            strtoseq = function(s)
                local out = {}
                for i = 1, #s do
                    out[#out + 1] = s:sub(i, i)
                end
                return out
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
    local Compiler = mock.loadModule("vim.lib.excmd.compiler")
    local Runtime = mock.loadModule("vim.lib.excmd.runtime")
    local Scopes = mock.loadModule("vim.lib.luaapi.scopes")

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

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
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

do
    normal_calls = {}
    local buf = Buffer(true, false)
    buf.name = "/tmp/normal_buf.txt"
    buf.lines = { "aa", "bb", "cc" }
    buf.refcount = 1
    win.buffer = buf
    win.cursorx = 1
    win.cursory = 1

    local ok, out = run_compiled([[
normal abc
normal! def
2,3normal! z
normal! gg|let g:normal_bar_split = 1
]], "/tmp/normal_runtime.vim")
    assert_true("normal script runs", ok == true, tostring(out))
    assert_eq("normal call count", #normal_calls, 5)

    assert_eq("normal uses remap", normal_calls[1].remap, true)
    assert_eq("normal arg text", normal_calls[1].text, "abc")

    assert_eq("normal! uses noremap", normal_calls[2].remap, false)
    assert_eq("normal! arg text", normal_calls[2].text, "def")

    assert_eq("range normal first line", normal_calls[3].line, 2)
    assert_eq("range normal second line", normal_calls[4].line, 3)
    assert_eq("range normal command text", normal_calls[3].text, "z")
    assert_eq("range normal command text 2", normal_calls[4].text, "z")

    assert_eq("normal no-bar-split keeps full tail", normal_calls[5].text, "gg|let g:normal_bar_split = 1")
    assert_true("normal no-bar-split does not execute following let", out.state.g.normal_bar_split == nil, tostring(out.state.g.normal_bar_split))
end

do
    local bufdel = Buffer(true, false)
    bufdel.name = "/tmp/bufhidden_delete.txt"
    bufdel.lines = { "x" }
    bufdel.refcount = 1
    win.buffer = bufdel
    Options.set("bufhidden", "delete", true, win, bufdel)
    local rv_del = bufdel:leave(false, nil, nil)
    assert_true("bufhidden=delete leave succeeds", rv_del == true, tostring(rv_del))
    assert_true("bufhidden=delete removes buffer when hidden", buffers[bufdel.bufnr] == nil, tostring(buffers[bufdel.bufnr]))

    local bufhide = Buffer(true, false)
    bufhide.name = "/tmp/bufhidden_hide.txt"
    bufhide.lines = { "x" }
    bufhide.refcount = 1
    bufhide.opts.modified = true
    win.buffer = bufhide
    Options.set("hidden", false, false, win, bufhide)
    Options.set("bufhidden", "hide", true, win, bufhide)
    local rv_hide = bufhide:leave(false, nil, nil)
    assert_true("bufhidden=hide bypasses hidden/mod warning", rv_hide == true, tostring(rv_hide))

    local bufunload = Buffer(true, false)
    bufunload.name = "/tmp/bufhidden_unload.txt"
    bufunload.lines = { "x" }
    bufunload.refcount = 1
    win.buffer = bufunload
    Options.set("bufhidden", "unload", true, win, bufunload)
    local rv_unload = bufunload:leave(false, nil, nil)
    assert_true("bufhidden=unload leave succeeds", rv_unload == true, tostring(rv_unload))
end

print("normal + bufhidden runtime tests: OK")
