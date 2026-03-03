local MockEnv = require("tests.test_mocks")

local exmsg_stub = {
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
}

local mock = MockEnv.setup({
    module_root = ".",
    module_stubs = {
        ["lib.exmsg"] = function() return exmsg_stub end,
        ["lib.excmd.exmsg"] = exmsg_stub,
        ["lib.sign"] = {
            on_lines_changed = function() end,
            define = function() end,
            getdefined = function() return {} end,
        },
        ["lib.syntax"] = {
            ParseLinetypes = function() end,
            OwnSyntax = function() end,
            ExecuteCommand = function() return true end,
            SyntimeReport = function() return {} end,
            SyntimeSet = function() end,
            SyntimeClear = function() end,
        },
        ["lib.autocmd"] = {
            Run = function() return 0 end,
        },
    },
})

_G.screen = { width = 80, height = 24 }
term.setCursorPos = term.setCursorPos or function() end
term.clearLine = term.clearLine or function() end
term.blit = term.blit or function() end
term.write = term.write or function() end
term.getSize = term.getSize or function() return 80, 24 end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Buffer = mock.loadModule("layout.buffer")
local BufAttach = mock.loadModule("lib.bufattach")

local win = {
    winnr = 1,
    opts = {},
    cursorx = 1,
    cursory = 1,
    cursorSet = function(self, x, y)
        self.cursorx = x
        self.cursory = y
    end,
}

windows[1] = win
tabpages[1].windows = { win }
curtp = 1
curwin = 1
vimmode = "normal"

local function make_lines(count)
    local lines = {}
    for i = 1, count do
        lines[i] = "line " .. i
    end
    return lines
end

local function make_buffer(line_count)
    local buf = Buffer(true, false)
    buf.name = "/tmp/bench_undo.txt"
    buf.lines = make_lines(line_count)
    buf.refcount = 1
    buf.opts.modified = false
    buf:undo_clear()
    win.buffer = buf
    return buf
end

local function timed(fn)
    collectgarbage("collect")
    local t0 = os.clock()
    fn()
    return os.clock() - t0
end

local line_count = tonumber(arg and arg[1]) or 12000
local edits = tonumber(arg and arg[2]) or 600
local mode = tostring(arg and arg[3] or "none")

local buf = make_buffer(line_count)

if mode == "listener" then
    BufAttach.attach(buf.bufnr, {
        on_lines = function() end,
    })
elseif mode == "listener_utf" then
    BufAttach.attach(buf.bufnr, {
        on_lines = function() end,
        utf_sizes = true,
    })
end

local t_edit = timed(function()
    for i = 1, edits do
        buf:set_line(math.floor(line_count / 2), "edit " .. i, true, true)
    end
end)

local t_undo = timed(function()
    for _ = 1, edits do
        buf:undo(win, 1, true)
    end
end)

local t_redo = timed(function()
    for _ = 1, edits do
        buf:redo(win, 1, true)
    end
end)

print("Undo benchmark")
print(string.format("lines=%d edits=%d mode=%s", line_count, edits, mode))
print(string.format("edit_total=%.6fs", t_edit))
print(string.format("undo_total=%.6fs", t_undo))
print(string.format("redo_total=%.6fs", t_redo))
print(string.format("edit_ms_per_op=%.3f", (t_edit * 1000) / edits))
print(string.format("undo_ms_per_op=%.3f", (t_undo * 1000) / edits))
print(string.format("redo_ms_per_op=%.3f", (t_redo * 1000) / edits))
