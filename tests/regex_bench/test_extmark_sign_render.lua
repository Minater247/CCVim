local MockEnv = require("vim.tests.test_mocks")

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
        ["vim.layout.buffer"] = setmetatable({}, {
            __call = function()
                error("unexpected buffer construction")
            end,
        }),
        ["vim.lib.highlight"] = {
            SetFor = function() end,
            For = function()
                return { colors.white, colors.black }
            end,
        },
        ["vim.lib.frame"] = {
            IsLeftChild = function()
                return false
            end,
            GetXY = function(frame)
                return frame.x or 1, frame.y or 1
            end,
        },
        ["vim.lib.statusline"] = {
            Parse = function()
                return {}
            end,
        },
        ["vim.lib.texren"] = {
            parse = function(line)
                return { line }, nil, nil
            end,
        },
        ["vim.lib.syntax"] = {
            LinesToBlit = function()
                return {}
            end,
        },
        ["vim.lib.tab"] = {
            get_tab_config = function()
                return {}
            end,
        },
        ["vim.lib.listchars"] = {
            get = function()
                return {}
            end,
        },
        ["vim.lib.excmd.cmdread"] = {
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
local api = mock.loadModule("lib.luaapi.api")

Options.set("laststatus", 0, false, nil, nil, true)
Options.set("number", false, false, nil, nil, true)
Options.set("relativenumber", false, false, nil, nil, true)
Options.set("linebreak", false, false, nil, nil, true)
Options.set("wrap", false, false, nil, nil, true)
Options.set("signcolumn", "auto", false, nil, nil, true)

local buf = mock.create_buffer(1, "/tmp/extmark-sign.txt", { "abc", "def" })
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

local ns = api.nvim_create_namespace("extmark.sign.test")
local mark_id = api.nvim_buf_set_extmark(1, ns, 0, 0, {})
api.nvim_buf_set_extmark(1, ns, 0, 0, {
    id = mark_id,
    sign_text = "!!",
    sign_hl_group = "ErrorMsg",
    line_hl_group = "Search",
    invalidate = true,
})

local marks = api.nvim_buf_get_extmarks(1, ns, { 0, 0 }, { 0, -1 }, { details = true })
assert_eq("one extmark returned", #marks, 1)
assert_eq("extmark id preserved", marks[1][1], mark_id)
assert_eq("extmark sign text in details", marks[1][4].sign_text, "!!")

local _, text_x, _, _, _, sign_w = win:textwidth()
assert_eq("signcolumn visible for extmark signs", sign_w, 2)
assert_eq("text starts after extmark signcolumn", text_x, 3)

clear_grid(8, 3)
win:render(1, 1)
assert_eq("extmark sign first cell", grid[1][1], "!")
assert_eq("extmark sign second cell", grid[1][2], "!")

api.nvim_buf_set_extmark(1, ns, 0, 0, {
    id = mark_id,
    sign_text = "✓",
    sign_hl_group = "ErrorMsg",
    line_hl_group = "Search",
    invalidate = true,
})

clear_grid(8, 3)
win:render(1, 1)
assert_eq("unicode check sign maps to ascii fallback", grid[1][1], "v")
assert_eq("unicode check sign keeps padding", grid[1][2], " ")

api.nvim_buf_set_extmark(1, ns, 0, 0, {
    id = mark_id,
    sign_text = "✗",
    sign_hl_group = "ErrorMsg",
    line_hl_group = "Search",
    invalidate = true,
})

clear_grid(8, 3)
win:render(1, 1)
assert_eq("unicode cross sign maps to ascii fallback", grid[1][1], "x")
assert_eq("unicode cross sign keeps padding", grid[1][2], " ")

print("extmark sign render tests: OK")
