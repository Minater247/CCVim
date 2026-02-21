local MockEnv = require("vim.tests.test_mocks")

local autocmd_calls = {}
local window_ctor_calls = 0

local autocmd_stub = {
    Run = function(event, ctx)
        autocmd_calls[#autocmd_calls + 1] = { event = event, ctx = ctx or {} }
        return 0
    end,
}

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.exmsg"] = function() return mock.loadModule("vim.lib.excmd.exmsg") end,
        ["vim.lib.excmd.exmsg"] = {
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
            IsMoreActive = function() return false end,
            DrawMoreView = function() end,
            RenderPressEnter = function() end,
            Redraw = function() end,
        },
        ["vim.layout.buffer"] = setmetatable({}, {
            __call = function()
                error("unexpected buffer construction")
            end,
        }),
        ["vim.layout.window"] = setmetatable({}, {
            __call = function()
                window_ctor_calls = window_ctor_calls + 1
                error("unexpected window construction")
            end,
        }),
        ["vim.lib.highlight"] = {
            SetFor = function() end,
        },
        ["vim.lib.statusline"] = {
            Parse = function() return {} end,
        },
        ["vim.lib.command"] = {
            PendingPrintable = function() return "" end,
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["vim.lib.key"] = {
            strtoseq = function() return {} end,
        },
        ["vim.lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["vim.lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["vim.lib.tags"] = {
            SearchFile = function() return nil end,
        },
        ["vim.lib.excmd.cmdread"] = {
            is_active = function() return false end,
        },
        ["vim.lib.autocmd"] = autocmd_stub,
        ["vim.lib.event"] = {
            HaltLoop = function() end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail or "assertion failed")))
    end
end

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
local Compiler = mock.loadModule("vim.lib.excmd.compiler")
local Runtime = mock.loadModule("vim.lib.excmd.runtime")
local Scopes = mock.loadModule("vim.lib.luaapi.scopes")
local Tabpage = mock.loadModule("vim.layout.tabpage")

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

local function make_win(id)
    return {
        winnr = id,
        tabpagenr = 1,
        buffer = {
            name = "/tmp/split_preflight_runtime.txt",
            line_count = function() return 1 end,
            get_line = function() return "" end,
        },
        style = nil,
        floatpos = nil,
        need_redraw = false,
        opts = {},
        minwidth = function() return options.get("winminwidth") end,
        minheight = function() return options.get("winminheight") end,
        cursorx = 1,
        cursory = 1,
        scrolly = { 1, 0 },
        scrollx = 0,
        cursorMove = function() end,
        cursorSet = function() end,
        render = function() end,
    }
end

_G.screen = { width = 10, height = 6 }

local win1 = make_win(1)
windows[1] = win1
local tab1 = Tabpage:new(win1)
curtp = tab1.tabnr
curwin = win1.winnr

Options.set("winminwidth", 10, false, nil, nil, true)
Options.set("winwidth", 10, false, nil, nil, true)
Options.set("winminheight", 1, false, nil, nil, true)
Options.set("winheight", 1, false, nil, nil, true)

local function assert_split_fails(script, ctx, setup_opts)
    if setup_opts then
        setup_opts()
    end

    local before_calls = #autocmd_calls
    local before_curwin = curwin
    local before_wins = #tab1.windows
    local before_tree = tab1.tree
    local before_ctors = window_ctor_calls

    local ok, err = run_compiled(script, { script_ctx = ctx })
    assert_eq(script .. " command fails", ok, false)
    if type(err) == "table" and err.code then
        assert_eq(script .. " error code is E36", err.code, 36)
    else
        assert_true(script .. " error text contains E36", tostring(err):find("E36", 1, true) ~= nil, tostring(err))
    end

    assert_eq(script .. " preflight avoided window construction", window_ctor_calls, before_ctors)
    assert_eq(script .. " failed split fires no autocmd", #autocmd_calls, before_calls)
    assert_eq(script .. " failed split keeps current window", curwin, before_curwin)
    assert_eq(script .. " failed split keeps tab window count", #tab1.windows, before_wins)
    assert_true(script .. " failed split keeps same frame root", tab1.tree == before_tree, "tree root changed")
end

assert_split_fails("vsplit", "/tmp/split_failure_preflight_runtime_vsplit.vim", function()
    Options.set("winminwidth", 10, false, nil, nil, true)
    Options.set("winwidth", 10, false, nil, nil, true)
    Options.set("winminheight", 1, false, nil, nil, true)
    Options.set("winheight", 1, false, nil, nil, true)
end)

assert_split_fails("split", "/tmp/split_failure_preflight_runtime_split.vim", function()
    Options.set("winminwidth", 1, false, nil, nil, true)
    Options.set("winwidth", 1, false, nil, nil, true)
    Options.set("winminheight", 6, false, nil, nil, true)
    Options.set("winheight", 6, false, nil, nil, true)
end)

print("split failure preflight runtime tests: OK")
