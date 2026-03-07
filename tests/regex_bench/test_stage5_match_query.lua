local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.exmsg"] = function() return mock.loadModule("lib.excmd.exmsg") end,
        ["lib.excmd.exmsg"] = {
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
        },
        ["lib.tags"] = { SearchFile = function() return nil end },
        ["lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["lib.pack"] = { add = function() return true end, load_start = function() return true end },
        ["lib.sign"] = { define = function() end, getdefined = function() return {} end },
    },
})

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

local function assert_contains(label, list, needle)
    for i = 1, #list do
        if tostring(list[i]):find(needle, 1, true) then
            return
        end
    end
    error(("FAIL %s: expected to contain %s"):format(label, tostring(needle)))
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Syntax = mock.loadModule("lib.syntax")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Compiler = mock.loadModule("lib.excmd.compiler")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Fn = mock.loadModule("lib.luaapi.fn")
local Highlight = mock.loadModule("lib.highlight")

local durable_by_ctx = {}
local function run_compiled(script, script_ctx)
    local key = script_ctx or "__default"
    local durable = durable_by_ctx[key]
    if not durable then
        durable = Runtime.CaptureDurableScriptState({ script_ctx = script_ctx }) or { s = {}, funcs = {} }
        durable.g = durable.g or Scopes._g
        durable_by_ctx[key] = durable
    end

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

local buf = mock.create_buffer(1, "/tmp/stage5.txt", { "foo bar", "zzz" }, { modified = false })
buf.leave = function() return true end
buf.Load = function() return true end
buf.refcount = 1
local buf2 = mock.create_buffer(2, "/tmp/stage5_b.txt", { "abc" }, { modified = false })
buf2.leave = function() return true end
buf2.Load = function() return true end
buf2.refcount = 0
local win = mock.create_window(1, buf, {})
win.cursorx = 1
win.cursory = 1
win.scrolly = { 1, 0 }
win.scrollx = 1
win.cursorSet = function(_, x, y)
    win.cursorx = x or win.cursorx
    win.cursory = y or win.cursory
end
tabpages[1].windows = { win }
curtp = 1
curwin = 1

-- :2match should set window-local slot #2 and clear with "none"
do
    local ok, err = run_compiled("2match Search /foo/", "/tmp/stage5_match_set.vim")
    assert_true("2match set executes", ok == true)
    if ok ~= true then error(tostring(err)) end

    local state = win.syntax_match_state
    assert_true("match state exists", state ~= nil)
    assert_true("slot 2 set", state.slots[2] ~= nil)
    assert_eq("slot 2 group", state.slots[2].group, "Search")

    ok, err = run_compiled("2match none", "/tmp/stage5_match_clear.vim")
    assert_true("2match clear executes", ok == true)
    if ok ~= true then error(tostring(err)) end
    assert_eq("slot 2 cleared", state.slots[2], nil)
end

-- :match overlay should work even when no syntax items are defined
do
    local ok, emsg = Syntax.MatchCommand(win, 1, "Search /foo/")
    assert_true("match command accepted", ok == true)
    if ok ~= true then error(tostring(emsg)) end

    local blits = Syntax.LinesToBlit(buf, 1, 1, win)
    local blit = blits[1]
    assert_true("match-only line blit exists", blit ~= nil)

    local search_fg = colors.toBlit(Highlight.For("Search")[1])
    assert_eq("match overlay fg at f", blit.fg:sub(1, 1), search_fg)
    assert_eq("match overlay fg at o", blit.fg:sub(2, 2), search_fg)
    assert_eq("match overlay fg at o2", blit.fg:sub(3, 3), search_fg)
end

-- Stage 5 query functions (synID*, synstack, synconcealed, hlID)
do
    Syntax.MatchClear(win, 1)
    Syntax.ExecuteCommand(win, "keyword String foo")

    local syn_id = Fn.fn.synID(1, 1, 0)
    assert_true("synID returns non-zero", syn_id > 0)
    assert_eq("synIDattr(name)", Fn.fn.synIDattr(syn_id, "name"), "String")

    local stack = Fn.fn.synstack(1, 1)
    assert_true("synstack has at least one id", #stack >= 1)
    assert_eq("synstack top id", stack[#stack], syn_id)

    local trans = Fn.fn.synIDtrans(syn_id)
    assert_true("synIDtrans returns id", trans > 0)

    local concealed = Fn.fn.synconcealed(1, 1)
    assert_eq("synconcealed has 3 fields", #concealed, 3)
    assert_eq("synconcealed not concealed", concealed[1], 0)

    local hl_id = Fn.fn.hlID("String")
    assert_true("hlID(String) non-zero", hl_id > 0)
end

-- ownsyntax reset semantics on buffer change
do
    Syntax.OwnSyntax(win, "lua")
    assert_true("ownsyntax creates override", win.syntax_ctx_override ~= nil)
    Syntax.OnWindowBufferChanged(win)
    assert_eq("ownsyntax override cleared on buffer change", win.syntax_ctx_override, nil)
end

-- ownsyntax reset semantics through runtime buffer switch
do
    win.buffer = buf
    local ok, err = run_compiled("ownsyntax lua\nbuffer 2", "/tmp/stage5_ownsyntax_switch.vim")
    assert_true("ownsyntax + buffer executes", ok == true)
    if ok ~= true then error(tostring(err)) end
    assert_eq("window switched to buffer 2", win.buffer, buf2)
    assert_eq("ownsyntax override cleared after :buffer", win.syntax_ctx_override, nil)
    assert_eq("w:current_syntax cleared after :buffer", Scopes.w.current_syntax, nil)
end

-- ownsyntax reset semantics through runtime reload (:edit)
do
    win.buffer = buf
    local ok, err = run_compiled("ownsyntax lua\nedit", "/tmp/stage5_ownsyntax_edit.vim")
    assert_true("ownsyntax + edit executes", ok == true)
    if ok ~= true then error(tostring(err)) end
    assert_eq("ownsyntax override cleared after :edit", win.syntax_ctx_override, nil)
    assert_eq("w:current_syntax cleared after :edit", Scopes.w.current_syntax, nil)
end

-- ownsyntax should isolate syntax commands between windows on same buffer
do
    local shared = mock.create_buffer(3, "/tmp/stage5_shared.txt", { "foo" }, { modified = false })
    shared.leave = function() return true end
    shared.Load = function() return true end
    shared.refcount = 2

    local win_a = mock.create_window(3, shared, {})
    local win_b = mock.create_window(4, shared, {})

    Syntax.ExecuteCommand(win_a, "keyword Comment foo")
    Syntax.OwnSyntax(win_b, "lua")
    Syntax.ExecuteCommand(win_b, "keyword String foo")

    local blit_a = Syntax.LineToBlit(shared, 1, win_a)
    local blit_b = Syntax.LineToBlit(shared, 1, win_b)
    local comment_fg = colors.toBlit(Highlight.For("Comment")[1])
    local string_fg = colors.toBlit(Highlight.For("String")[1])

    assert_eq("shared buffer regular window keeps buffer syntax", blit_a.fg:sub(1, 1), comment_fg)
    assert_eq("shared buffer ownsyntax window uses override syntax", blit_b.fg:sub(1, 1), string_fg)
end

-- :syntime should report real counters (not placeholder lines)
do
    Syntax.ExecuteCommand(win, "match Comment /foo/")
    Syntax.SyntimeClear(win)
    Syntax.SyntimeSet(win, true)
    Syntax.LineToBlit(buf, 1, win)
    local lines = Syntax.SyntimeReport(win)

    assert_true("syntime report has lines", #lines >= 2)
    assert_contains("syntime report total", lines, "total: calls=")
    assert_contains("syntime report header", lines, "TOTAL(ms)")
    assert_contains("syntime report row", lines, "foo")
end

print("Stage 5 match/query tests: OK")
