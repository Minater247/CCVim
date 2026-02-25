local MockEnv = require("vim.tests.test_mocks")

local current_hl = "Normal"
local cursor_writes = 0
local cmdline_active = false

local mock = MockEnv.setup({
    module_stubs = {
        ["layout.buffer"] = setmetatable({}, {
            __call = function()
                error("unexpected buffer construction")
            end,
        }),
        ["lib.highlight"] = {
            SetFor = function(group)
                current_hl = group
            end,
        },
        ["lib.frame"] = {
            IsLeftChild = function()
                return false
            end,
            GetXY = function(frame)
                return frame.x or 1, frame.y or 1
            end,
        },
        ["lib.statusline"] = {
            Parse = function()
                return {}
            end,
        },
        ["lib.texren"] = {
            parse = function(line, _opts, bytepos)
                local cursor = nil
                if bytepos then
                    -- Force the deferred virtual-wrap cursor draw path.
                    cursor = { line = 2, column = 1, ch = " " }
                end
                return { line }, nil, cursor
            end,
        },
        ["lib.syntax"] = {
            LinesToBlit = function()
                return {}
            end,
        },
        ["lib.tab"] = {
            get_tab_config = function()
                return {}
            end,
        },
        ["lib.listchars"] = {
            get = function()
                return {}
            end,
        },
        ["lib.excmd.cmdread"] = {
            is_active = function()
                return cmdline_active
            end,
        },
    },
})

term.setCursorPos = function() end
term.write = function(text)
    if current_hl == "Cursor" then
        cursor_writes = cursor_writes + #text
    end
end
term.blit = function(text)
    if current_hl == "Cursor" then
        cursor_writes = cursor_writes + #text
    end
end
term.setTextColor = term.setTextColor or function() end
term.setBackgroundColor = term.setBackgroundColor or function() end
term.getPaletteColor = term.getPaletteColor or function()
    return 0, 0, 0
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s"):format(label))
    end
end

_G.screen = { width = 20, height = 6 }

local Options = mock.loadModule("lib.options")
_G.options = Options
local Window = mock.loadModule("layout.window")

Options.set("laststatus", 0, false, nil, nil, true)
Options.set("number", false, false, nil, nil, true)
Options.set("relativenumber", false, false, nil, nil, true)
Options.set("linebreak", false, false, nil, nil, true)

local buf = mock.create_buffer(1, "/tmp/a", { "abc" })
buf.refcount = 0

local win1 = Window:new(buf)
local win2 = Window:new(buf)
win1.frame = { x = 1, y = 1, width = 8, height = 2 }
win2.frame = { x = 1, y = 1, width = 8, height = 2 }
win1.cursory = 1
win1.cursorx = 2
win2.cursory = 1
win2.cursorx = 2

tabpages[1] = {
    tabnr = 1,
    windows = { win1, win2 },
    tree = { width = 8, height = 2 },
}
curtp = 1

local function render_count(win)
    cursor_writes = 0
    win:render(1, 1)
    return cursor_writes
end

curwin = win1.winnr
cmdline_active = false
assert_true("current window draws cursor when cmdline inactive", render_count(win1) > 0)

curwin = win1.winnr
cmdline_active = false
assert_eq("non-current window does not draw cursor", render_count(win2), 0)

curwin = win1.winnr
cmdline_active = true
assert_eq("no cursor is drawn in current window while cmdline active", render_count(win1), 0)

print("window cursor render semantics tests: OK")
