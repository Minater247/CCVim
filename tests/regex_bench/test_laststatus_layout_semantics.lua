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

_G.screen = { width = 20, height = 6 }

local Options = mock.loadModule("lib.options")
_G.options = Options
local Tabpage = mock.loadModule("layout.tabpage")

local function make_win(id)
    return {
        winnr = id,
        tabpagenr = 1,
        style = nil,
        floatpos = nil,
        need_redraw = false,
        opts = {},
        minwidth = function() return options.get("winminwidth") end,
        minheight = function() return options.get("winminheight") end,
        cursorMove = function() end,
        render = function() end,
    }
end

Options.set("cmdheight", 1, false, nil, nil, true)
Options.set("showtabline", 1, false, nil, nil, true)
Options.set("winminwidth", 1, false, nil, nil, true)
Options.set("winminheight", 1, false, nil, nil, true)

Options.set("laststatus", 3, false, nil, nil, true)
local win1 = make_win(1)
windows[1] = win1
local tab1 = Tabpage:new(win1)
curtp = tab1.tabnr
curwin = win1.winnr

assert_eq("laststatus=3 reserves one global statusline row", tab1.tree.height, 4)

Options.set("laststatus", 2, false, nil, nil, true)
tab1:updateFrameview()
assert_eq("laststatus=2 uses full non-cmdheight area", tab1.tree.height, 5)

screen.height = 4
Options.set("laststatus", 3, false, nil, nil, true)
tab1:updateFrameview()
assert_eq("laststatus=3 recomputes reduced layout height", tab1.tree.height, 2)

do
    local before_calls = #autocmd_calls
    local probe = tab1:MakeSplitProbe(win1)
    local ok = tab1:WinSplit(0, probe, false, { dry_run = true })
    assert_eq("split dry-run fails with global statusline when separator would consume text row", ok, false)
    assert_eq("dry-run emits no autocmd for ls=3", #autocmd_calls, before_calls)
end

Options.set("laststatus", 2, false, nil, nil, true)
tab1:updateFrameview()
assert_eq("laststatus=2 recomputes larger frame height", tab1.tree.height, 3)

do
    local before_calls = #autocmd_calls
    local probe = tab1:MakeSplitProbe(win1)
    local ok = tab1:WinSplit(0, probe, false, { dry_run = true })
    assert_eq("split dry-run fails when local statuslines leave no text row", ok, false)
    assert_eq("dry-run emits no autocmd for ls=2", #autocmd_calls, before_calls)
end

print("laststatus layout semantics tests: OK")
