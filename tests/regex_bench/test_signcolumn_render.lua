local MockEnv = require("vim.tests.test_mocks")

local current_hl = "Normal"
local cursor_x, cursor_y = 1, 1
local grid = {}

local function clear_grid(width, height)
    grid = {}
    for y = 1, height do
        grid[y] = {}
        for x = 1, width do
            grid[y][x] = " "
        end
    end
end

local function write_grid(text)
    for i = 1, #text do
        local ch = text:sub(i, i)
        if grid[cursor_y] and grid[cursor_y][cursor_x] then
            grid[cursor_y][cursor_x] = ch
        end
        cursor_x = cursor_x + 1
    end
end

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
            For = function(_group)
                return { colors.white, colors.black }
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
            parse = function(line)
                return { line }, nil, nil
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
                return false
            end,
        },
    },
})

term.setCursorPos = function(x, y)
    cursor_x, cursor_y = x, y
end
term.write = function(text)
    write_grid(text)
end
term.blit = function(text)
    write_grid(text)
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

_G.screen = { width = 20, height = 6 }

local Options = mock.loadModule("lib.options")
_G.options = Options
local Window = mock.loadModule("layout.window")
local Sign = mock.loadModule("lib.sign")

Options.set("laststatus", 0, false, nil, nil, true)
Options.set("number", false, false, nil, nil, true)
Options.set("relativenumber", false, false, nil, nil, true)
Options.set("linebreak", false, false, nil, nil, true)
Options.set("wrap", false, false, nil, nil, true)
Options.set("signcolumn", "auto", false, nil, nil, true)

local buf = mock.create_buffer(1, "/tmp/signcolumn.txt", { "abc", "def" })
buf.refcount = 0

local win = Window:new(buf)
win.frame = { x = 1, y = 1, width = 8, height = 3 }
win.cursory = 1
win.cursorx = 1

tabpages[1] = {
    tabnr = 1,
    windows = { win },
    tree = { width = 8, height = 3 },
}
curtp = 1
curwin = win.winnr

assert_eq("define sign", Sign.define("WarnSign", { text = "!!" }), 0)
assert_eq("place sign", Sign.place(1, "", "WarnSign", 1, { lnum = 1 }), 1)

local _, text_x_before, _, _, _, sign_w_before = win:textwidth()
assert_eq("auto signcolumn reserves 2 cells when sign exists", sign_w_before, 2)
assert_eq("text starts after signcolumn", text_x_before, 3)

clear_grid(8, 3)
win:render(1, 1)
assert_eq("sign text appears in signcolumn cell 1", grid[1][1], "!")
assert_eq("sign text appears in signcolumn cell 2", grid[1][2], "!")
assert_eq("text shifts right when signcolumn is shown", grid[1][3], "a")

assert_eq("unplace signs", Sign.unplace("*", { buffer = 1 }), 0)
local _, text_x_after, _, _, _, sign_w_after = win:textwidth()
assert_eq("auto signcolumn collapses after last sign removed", sign_w_after, 0)
assert_eq("text starts at first column when signcolumn hidden", text_x_after, 1)

clear_grid(8, 3)
win:render(1, 1)
assert_eq("buffer text now starts at first column", grid[1][1], "a")

print("signcolumn render tests: OK")
