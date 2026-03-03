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
        ["layout.buffer"] = setmetatable({}, {
            __call = function()
                error("unexpected buffer construction")
            end,
        }),
        ["lib.highlight"] = {
            SetFor = function() end,
            For = function()
                return { colors.white, colors.black }
            end,
            NameById = function()
                return nil
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
        ["lib.texren"] = nil,
        ["lib.syntax"] = {
            LinesToBlit = function()
                return {}
            end,
        },
        ["lib.tab"] = {
            get_tab_config = function()
                return {}
            end,
            next_display_tabstop = function(col)
                return col + 1
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

local function row_text(y, width)
    local t = {}
    for x = 1, width do
        t[#t + 1] = grid[y][x]
    end
    return table.concat(t)
end

_G.screen = { width = 24, height = 8 }

local Options = mock.loadModule("lib.options")
_G.options = Options
local Window = mock.loadModule("layout.window")
local api = mock.loadModule("lib.luaapi.api")

Options.set("laststatus", 0, false, nil, nil, true)
Options.set("number", false, false, nil, nil, true)
Options.set("relativenumber", false, false, nil, nil, true)
Options.set("linebreak", false, false, nil, nil, true)
Options.set("wrap", false, false, nil, nil, true)
Options.set("signcolumn", "no", false, nil, nil, true)

local buf = mock.create_buffer(1, "/tmp/extmark-text.txt", { "abc", "xyz" })
buf.refcount = 0

local win = Window:new(buf)
win.frame = { x = 1, y = 1, width = 12, height = 4 }
win.cursory = 1
win.cursorx = 1

tabpages[1] = {
    tabnr = 1,
    windows = { win },
    tree = { width = 12, height = 4 },
}
curtp = 1
curwin = win.winnr

local ns = api.nvim_create_namespace("extmark.text.render")

clear_grid(12, 4)
win:render(1, 1)
assert_eq("baseline text", row_text(1, 6), "abc   ")

api.nvim_buf_set_extmark(1, ns, 0, 1, {
    virt_text = { { "X", "ErrorMsg" } },
    virt_text_pos = "overlay",
})
clear_grid(12, 4)
win:render(1, 1)
assert_eq("overlay virt_text", row_text(1, 6), "aXc   ")

api.nvim_buf_clear_namespace(1, ns, 0, -1)
api.nvim_buf_set_extmark(1, ns, 0, 1, {
    virt_text = { { "ZZ", "ErrorMsg" } },
    virt_text_pos = "inline",
})
clear_grid(12, 4)
win:render(1, 1)
assert_eq("inline virt_text", row_text(1, 8), "aZZbc   ")

api.nvim_buf_clear_namespace(1, ns, 0, -1)
api.nvim_buf_set_extmark(1, ns, 0, 3, {
    virt_text = { { "_H", "Comment" } },
    virt_text_pos = "eol",
})
clear_grid(12, 4)
win:render(1, 1)
assert_eq("eol virt_text", row_text(1, 8), "abc_H   ")

api.nvim_buf_clear_namespace(1, ns, 0, -1)
api.nvim_buf_set_extmark(1, ns, 0, 0, {
    virt_lines = {
        { { "vv", "Comment" } },
    },
})
clear_grid(12, 4)
win:render(1, 1)
assert_eq("virt_lines draws below line", row_text(2, 6), "vv    ")

api.nvim_buf_clear_namespace(1, ns, 0, -1)
api.nvim_buf_set_extmark(1, ns, 0, 0, {
    hl_group = "Search",
    end_line = 0,
    end_col = 2,
})
clear_grid(12, 4)
win:render(1, 1)
assert_eq("hl_group extmark keeps text", row_text(1, 6), "abc   ")

print("extmark text render tests: OK")
