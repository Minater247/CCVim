local MockEnv = require("vim.tests.test_mocks")

local mock_term = {}
do
    local active = nil

    function mock_term.current()
        return active or mock_term
    end

    function mock_term.redirect(target)
        local prev = active or mock_term
        active = target or mock_term
        return prev
    end

    function mock_term.setCursorPos() end
    function mock_term.write() end
    function mock_term.clearLine() end
    function mock_term.setTextColor() end
    function mock_term.setBackgroundColor() end
    function mock_term.getPaletteColor()
        return 0, 0, 0
    end
end

_G.window = {
    create = function(parent, x, y, w, h, visible)
        local win = {}
        function win.setVisible() end
        function win.reposition() end
        function win.setCursorPos() end
        function win.write() end
        function win.clearLine() end
        return win
    end,
}

local mock = MockEnv.setup({
    term = mock_term,
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
            Parse = function()
                return { { "status", "StatusLine" } }
            end,
        },
        ["lib.command"] = {
            PendingPrintable = function() return "" end,
        },
        ["lib.excmd.cmdread"] = {
            is_active = function() return false end,
            drawCmdline = function() end,
        },
        ["lib.autocmd"] = {
            Run = function() return 0 end,
        },
        ["lib.event"] = {
            HaltLoop = function() end,
        },
        ["lib.excmd.exmsg"] = {
            IsOverlayActive = function() return false end,
            IsMoreActive = function() return false end,
            DrawMoreView = function() end,
            RenderPressEnter = function() end,
            Redraw = function() end,
            DrawOneShot = function() end,
        },
    },
})

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail or "assertion failed")))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Tabpage = mock.loadModule("layout.tabpage")

_G.screen = { width = 20, height = 8 }

Options.set("cmdheight", 1, false, nil, nil, true)
Options.set("showtabline", 0, false, nil, nil, true)
Options.set("laststatus", 3, false, nil, nil, true)
Options.set("statusline", "GLOBAL", false, nil, nil, true)

local win1 = {
    winnr = 1,
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
windows[1] = win1
curwin = 1

local tab1 = Tabpage:new(win1)
curtp = tab1.tabnr

local ok, err = pcall(function()
    tab1:render()
end)

assert_true("laststatus=3 render does not crash", ok == true, err)

print("laststatus global render statusline test: OK")
