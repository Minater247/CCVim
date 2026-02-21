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
        ["vim.layout.window"] = setmetatable({}, {
            __call = function()
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
        },
        ["vim.lib.excmd.cmdread"] = {
            is_active = function() return false end,
        },
        ["vim.lib.autocmd"] = autocmd_stub,
        ["vim.lib.event"] = {
            HaltLoop = function() end,
        },
        ["vim.lib.excmd.exmsg"] = {
            IsMoreActive = function() return false end,
            DrawMoreView = function() end,
            RenderPressEnter = function() end,
            Redraw = function() end,
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

local function make_win(id)
    return {
        winnr = id,
        tabpagenr = 1,
        style = nil,
        floatpos = nil,
        need_redraw = false,
        opts = {},
        minwidth = function()
            return options.get("winminwidth")
        end,
        minheight = function()
            return options.get("winminheight")
        end,
        cursorMove = function() end,
        render = function() end,
    }
end

_G.screen = { width = 20, height = 8 }

local Options = mock.loadModule("lib.options")
_G.options = Options
local Tabpage = mock.loadModule("layout.tabpage")

local win1 = make_win(1)
windows[1] = win1
local tab1 = Tabpage:new(win1)
curtp = tab1.tabnr
curwin = win1.winnr

Options.set("winminwidth", 1, false, nil, nil, true)
Options.set("winminheight", 1, false, nil, nil, true)

do
    local before_calls = #autocmd_calls
    local before_root = tab1.tree
    local before_children = #tab1.windows
    local before_winnr = curwin

    local probe = tab1:MakeSplitProbe(win1)
    local ok = tab1:WinSplit(0, probe, true, { dry_run = true })
    assert_eq("feasible dry-run succeeds", ok, true)
    assert_eq("dry-run emits no autocmd", #autocmd_calls, before_calls)
    assert_eq("dry-run keeps same root", tab1.tree, before_root)
    assert_eq("dry-run keeps same window count", #tab1.windows, before_children)
    assert_eq("dry-run keeps current window", curwin, before_winnr)
end

do
    local before_calls = #autocmd_calls
    local before_root = tab1.tree
    local before_children = #tab1.windows
    local before_winnr = curwin

    Options.set("winminwidth", 20, false, nil, nil, true)
    local probe = tab1:MakeSplitProbe(win1)
    local ok = tab1:WinSplit(0, probe, true, { dry_run = true })
    assert_eq("infeasible dry-run fails", ok, false)
    assert_eq("failed dry-run emits no autocmd", #autocmd_calls, before_calls)
    assert_eq("failed dry-run keeps same root", tab1.tree, before_root)
    assert_eq("failed dry-run keeps same window count", #tab1.windows, before_children)
    assert_eq("failed dry-run keeps current window", curwin, before_winnr)
    assert_true("original window still framed", win1.frame == tab1.tree, "frame detached unexpectedly")
end

print("tabpage winsplit dry-run autocmd tests: OK")
