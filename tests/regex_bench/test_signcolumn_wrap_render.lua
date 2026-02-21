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

local function simple_wrap(line, wraplen)
    line = tostring(line or "")
    if not wraplen or wraplen <= 0 then
        return { line }
    end
    local out = {}
    local i = 1
    while i <= #line do
        out[#out + 1] = line:sub(i, i + wraplen - 1)
        i = i + wraplen
    end
    if #out == 0 then
        out[1] = ""
    end
    return out
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
            parse = function(line, opts)
                return simple_wrap(line, opts and opts.wraplen or 0), nil, nil
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
local Sign = mock.loadModule("lib.sign")

Options.set("laststatus", 0, false, nil, nil, true)
Options.set("number", true, false, nil, nil, true)
Options.set("relativenumber", false, false, nil, nil, true)
Options.set("numberwidth", 4, false, nil, nil, true)
Options.set("linebreak", false, false, nil, nil, true)
Options.set("wrap", true, false, nil, nil, true)
Options.set("signcolumn", "auto", false, nil, nil, true)

local buf = mock.create_buffer(1, "/tmp/signcolumn-wrap.txt", { "abcdefghi" })
buf.refcount = 0

local win = Window:new(buf)
win.frame = { x = 1, y = 1, width = 10, height = 4 }
win.cursory = 1
win.cursorx = 1
win.opts.wrap = true
win.opts.number = true
win.opts.relativenumber = false
win.opts.numberwidth = 4

tabpages[1] = {
    tabnr = 1,
    windows = { win },
    tree = { width = 10, height = 4 },
}
curtp = 1
curwin = win.winnr

assert_eq("define sign", Sign.define("WrapSign", { text = "!!" }), 0)
assert_eq("place sign", Sign.place(1, "", "WrapSign", 1, { lnum = 1 }), 1)

local text_w, text_x, _, _, _, sign_w = win:textwidth()
assert_eq("signcolumn width", sign_w, 2)
assert_eq("text starts after sign+number columns", text_x, 7)
assert_eq("wrap width reduced by reserved columns", text_w, 4)

clear_grid(10, 4)
win:render(1, 1)

assert_eq("row1 sign column cell 1", grid[1][1], "!")
assert_eq("row1 sign column cell 2", grid[1][2], "!")
assert_eq("row1 wrapped text starts at shifted column", grid[1][7], "a")
assert_eq("row1 wrapped text chunk end", grid[1][10], "d")

assert_eq("row2 continuation keeps sign column blank cell 1", grid[2][1], " ")
assert_eq("row2 continuation keeps sign column blank cell 2", grid[2][2], " ")
assert_eq("row2 wrapped continuation starts at shifted column", grid[2][7], "e")
assert_eq("row2 wrapped continuation chunk end", grid[2][10], "h")

assert_eq("row3 final wrapped part starts at shifted column", grid[3][7], "i")

print("signcolumn wrap render tests: OK")
