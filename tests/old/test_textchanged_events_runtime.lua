local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.exmsg"] = function() return mock.loadModule("lib.excmd.exmsg") end,
        ["lib.excmd.exmsg"] = {
            messages = {},
            echo = function() end,
            echon = function() end,
            echomsg = function() end,
            echoerr = function() end,
            echohl = function() end,
            PushSilent = function() end,
            PushUnsilent = function() end,
            PopSilent = function() end,
            _writeWithHL = function() end,
        },
        ["lib.syntax"] = {
            ParseLinetypes = function() end,
            LineToBlit = function() return nil end,
            LinesToBlit = function() return {} end,
            OnWindowBufferChanged = function() end,
        },
        ["lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["lib.sign"] = {
            on_lines_changed = function() end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options

local Autocmd = mock.loadModule("lib.autocmd")
local Buffer = mock.loadModule("layout.buffer")

local buf = Buffer:new(true, false, true)
buf.name = "/tmp/textchanged.txt"
buf.lines = { "x" }
buf.opts.modified = false
local win = mock.create_window(1, buf, {})
win.cursorx = 1
win.cursory = 1
function win:cursorMove(dx, dy)
    self.cursorx = (self.cursorx or 1) + (dx or 0)
    self.cursory = (self.cursory or 1) + (dy or 0)
end

_G.windows = { [1] = win }
_G.curwin = 1
_G.tabpages = { { tabnr = 1, windows = { win }, opts = {} } }
_G.curtp = 1

local normal_count, insert_count = 0, 0
local normal_buf, insert_buf = nil, nil

Autocmd.CreateAutocommand({ "TextChanged" }, { "*" }, function(info)
    normal_count = normal_count + 1
    normal_buf = info.bufnr
end, nil, 1, false, false, nil, nil)

Autocmd.CreateAutocommand({ "TextChangedI" }, { "*" }, function(info)
    insert_count = insert_count + 1
    insert_buf = info.bufnr
end, nil, 1, false, false, nil, nil)

_G.vimmode = "normal"
buf:set_line(1, "normal-change")

_G.vimmode = "insert"
buf:set_line(1, "insert-change")

assert_eq("TextChanged fired once", normal_count, 1)
assert_eq("TextChangedI fired once", insert_count, 1)
assert_eq("TextChanged bufnr", normal_buf, 1)
assert_eq("TextChangedI bufnr", insert_buf, 1)

print("TextChanged/TextChangedI dispatch tests: OK")
