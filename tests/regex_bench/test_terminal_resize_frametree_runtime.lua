local MockEnv = require("vim.tests.test_mocks")

local autocmd_calls = {}
local autocmd_stub = {
    Run = function(event, ctx)
        autocmd_calls[#autocmd_calls + 1] = { event = event, ctx = ctx or {} }
        return 0
    end,
}

local mock = MockEnv.setup({
    module_stubs = {
        ["layout.window"] = setmetatable({}, {
            __call = function()
                error("unexpected window construction")
            end,
        }),
        ["lib.highlight"] = {
            SetFor = function() end,
        },
        ["lib.statusline"] = {
            Parse = function() return {} end,
        },
        ["lib.command"] = {
            PendingPrintable = function() return "" end,
        },
        ["lib.excmd.cmdread"] = {
            is_active = function() return false end,
        },
        ["lib.autocmd"] = autocmd_stub,
        ["lib.event"] = {
            HaltLoop = function() end,
        },
        ["lib.excmd.exmsg"] = {
            IsMoreActive = function() return false end,
            DrawMoreView = function() end,
            RenderPressEnter = function() end,
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

local function count_event(name)
    local n = 0
    for i = 1, #autocmd_calls do
        if autocmd_calls[i].event == name then
            n = n + 1
        end
    end
    return n
end

local function clear_events()
    for i = #autocmd_calls, 1, -1 do
        autocmd_calls[i] = nil
    end
end

local function make_win(id, minw, minh)
    return {
        winnr = id,
        tabpagenr = 1,
        style = nil,
        floatpos = nil,
        need_redraw = false,
        minwidth = function()
            return minw
        end,
        minheight = function()
            return minh
        end,
        cursorMove = function() end,
        render = function() end,
    }
end

_G.screen = { width = 80, height = 24 }

local Options = mock.loadModule("lib.options")
_G.options = Options
local FrameTree = mock.loadModule("lib.frame")
local Tabpage = mock.loadModule("layout.tabpage")

local win1 = make_win(1, 1, 1)
windows[1] = win1
local tab1 = Tabpage:new(win1)
curtp = tab1.tabnr
curwin = win1.winnr

local win2 = make_win(2, 1, 1)
windows[2] = win2
do
    local ok, new_root = FrameTree.VerticalSplit(tab1.tree, win2, true)
    assert_true("split tab1", ok == true, tostring(ok))
    if new_root then
        tab1.tree = new_root
    end
    tab1.windows[#tab1.windows + 1] = win2
    win2.tabpagenr = tab1.tabnr
end

local win3 = make_win(3, 1, 1)
windows[3] = win3
local tab2 = Tabpage:new(win3)
curtp = tab1.tabnr
curwin = win1.winnr

do
    local ok, changed = FrameTree.ApplyTerminalResize(100, 30, "term_resize")
    assert_true("resize success", ok == true, tostring(ok))
    assert_eq("resize changed flag", changed, true)
    assert_eq("screen width updated", screen.width, 100)
    assert_eq("screen height updated", screen.height, 30)
    assert_eq("columns updated", Options.get("columns"), 100)
    assert_eq("lines updated", Options.get("lines"), 30)
    assert_eq("tab1 width updated", tab1.tree.width, 100)
    assert_eq("tab2 width updated", tab2.tree.width, 100)
    assert_eq("tab1 height updated", tab1.tree.height, 28)
    assert_eq("tab2 height updated", tab2.tree.height, 28)
    assert_eq("VimResized fired once", count_event("VimResized"), 1)
    assert_eq("WinResized fired once", count_event("WinResized"), 1)

    local winresized
    for i = 1, #autocmd_calls do
        if autocmd_calls[i].event == "WinResized" then
            winresized = autocmd_calls[i].ctx
            break
        end
    end
    assert_true("WinResized payload present", type(winresized) == "table", "missing WinResized ctx")
    assert_true("WinResized windows list populated", #(winresized.data.windows or {}) >= 1, "expected changed window ids")
end

do
    clear_events()
    need_redraw = false
    what_redraw = {}
    local ok, changed = FrameTree.ApplyTerminalResize(100, 30, "term_resize")
    assert_true("same-size resize succeeds", ok == true, tostring(ok))
    assert_eq("same-size changed flag false", changed, false)
    assert_eq("same-size emits no events", #autocmd_calls, 0)
    assert_eq("same-size does not mark redraw", need_redraw, false)
end

do
    clear_events()
    need_redraw = false
    what_redraw = {}
    win1.minwidth = function() return 70 end
    win2.minwidth = function() return 70 end

    local ok, err = FrameTree.ApplyTerminalResize(80, 30, "term_resize")
    assert_eq("strict failure returns false", ok, false)
    assert_true("strict failure returns E36", type(err) == "table" and err.code == 36, tostring(err))
    assert_eq("strict failure keeps authoritative screen width", screen.width, 80)
    assert_eq("strict failure keeps authoritative columns", Options.get("columns"), 80)
    assert_eq("strict failure keeps old tree width (no fallback)", tab1.tree.width, 100)
    assert_eq("strict failure still fires VimResized", count_event("VimResized"), 1)
end

print("terminal resize frametree runtime tests: OK")
