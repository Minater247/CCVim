local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    vimmode = "insert",
    term = {
        getPaletteColor = function() return 0, 0, 0 end,
        setTextColor = function() end,
        setBackgroundColor = function() end,
        setCursorPos = function() end,
        write = function() end,
        blit = function() end,
    },
    module_stubs = {
        ["vim.lib.highlight"] = {
            SetFor = function() end,
            For = function() return { colors.white, colors.black } end,
            HasGroup = function() return false end,
            Link = function() return true end,
            Clear = function() end,
            SetGroupColor = function() end,
        },
        ["vim.lib.frame"] = {
            IsLeftChild = function() return false end,
        },
        ["vim.lib.statusline"] = {
            Parse = function() return { { "", "Normal" } } end,
        },
        ["vim.lib.texren"] = {
            parse = function(line, _opts, cursor)
                local c = nil
                if cursor then
                    local ch = line:sub(cursor, cursor)
                    if ch == "" then ch = " " end
                    c = { line = 1, column = cursor, ch = ch }
                end
                return { line }, nil, c
            end,
        },
        ["vim.lib.syntax"] = {
            ParseLinetypes = function() end,
            LineToBlit = function() return nil end,
        },
        ["vim.lib.listchars"] = {
            get = function() return {} end,
        },
        ["vim.lib.autocmd"] = {
            Run = function() return 0 end,
        },
    },
})

local Options = mock.loadModule("lib.options")
_G.options = Options
local Buffer = mock.loadModule("layout.buffer")
local Window = mock.loadModule("layout.window")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local buf = Buffer(true, false)
buf.name = "/tmp/test.lua"
buf.lines = { "if true then" }
buf.refcount = 0

local win = Window:new(buf)
windows[win.winnr] = win
curwin = win.winnr
tabpages[1].windows = { win }
win.floatpos = { reltype = "editor", x = 1, y = 1, w = 80, h = 24 }

Options.set("indentexpr", "2", true, win, buf)
Options.set("indentkeys", "o,0=end", true, win, buf)
Options.set("autoindent", false, true, win, buf)

win.cursory = 1
win.cursorx = #buf.lines[1] + 1
win:insertText("\n")
assert_eq("newline creates line", buf.lines[2], "  ")

buf.lines = { "    en" }
win.cursory = 1
win.cursorx = #buf.lines[1] + 1
Options.set("indentexpr", "0", true, win, buf)
Options.set("indentkeys", "0=end", true, win, buf)
win:insertText("d")
assert_eq("typed word trigger reindents", buf.lines[1], "end")

print("indentexpr/indentkeys tests: OK")
