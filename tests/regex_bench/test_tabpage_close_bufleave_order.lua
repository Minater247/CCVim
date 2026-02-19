local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.command"] = {
            PendingPrintable = function() return "" end,
        },
        ["vim.lib.excmd.cmdread"] = {
            drawCmdline = function() end,
        },
        ["vim.lib.excmd.exmsg"] = {
            Redraw = function() end,
            DrawOneShot = function() end,
        },
        ["vim.lib.highlight"] = {
            SetFor = function() end,
        },
        ["vim.lib.statusline"] = {
            Parse = function() return {} end,
        },
        ["vim.lib.frame"] = {
            Close = function()
                return true, nil
            end,
            Equalize = function() end,
            GetXY = function() return 1, 1 end,
            GetFrameAt = function() return nil end,
        },
        ["vim.lib.event"] = {
            HaltLoop = function() end,
        },
        ["vim.layout.window"] = function()
            return {}
        end,
        ["vim.lib.syntax"] = {
            ParseLinetypes = function() end,
            OnWindowBufferChanged = function() end,
            OnSyntaxOptionSet = function() end,
            OnSynmaxcolOptionSet = function() end,
        },
    },
})

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
local Buffer = mock.loadModule("vim.layout.buffer")
local Tabpage = mock.loadModule("vim.layout.tabpage")
local Autocmd = mock.loadModule("vim.lib.autocmd")

local function make_win(winnr, bufnr_obj, tabnr)
    return {
        winnr = winnr,
        tabpagenr = tabnr,
        buffer = bufnr_obj,
        frame = nil,
        opts = {},
        cursorx = 1,
        cursory = 1,
        close = function(self, force, mustabandon, autowrite_kind)
            return self.buffer:leave(force, mustabandon, autowrite_kind)
        end,
        cursorSet = function(self, x, y)
            self.cursorx = x
            self.cursory = y
        end,
    }
end

local function fire_enter_window(winnr)
    if winnr == curwin then
        return
    end
    local oldbuf = windows[curwin] and windows[curwin].buffer or nil
    local newbuf = windows[winnr] and windows[winnr].buffer or nil
    local buf_changed = oldbuf and newbuf and oldbuf ~= newbuf

    if buf_changed then
        Autocmd.Run("BufLeave", { bufnr = oldbuf.bufnr, bufname = oldbuf.name })
    end
    Autocmd.Run("WinLeave")
    curwin = winnr
    Autocmd.Run("WinEnter")
    if buf_changed then
        Autocmd.Run("BufEnter", { bufnr = newbuf.bufnr, bufname = newbuf.name })
    end
end

_G.enterWindow = fire_enter_window

local buf1 = Buffer(true, false)
buf1.name = "/tmp/tabclose_a"
buf1.lines = { "a" }
buf1.refcount = 1

local buf2 = Buffer(true, false)
buf2.name = "/tmp/tabclose_b"
buf2.lines = { "b" }
buf2.refcount = 1

local win1 = make_win(1, buf1, 1)
local win2 = make_win(2, buf2, 1)
windows[1] = win1
windows[2] = win2

local tp = setmetatable({
    tabnr = 1,
    windows = { win1, win2 },
    tree = {},
    opts = {},
}, Tabpage)
tabpages[1] = tp
curtp = 1
curwin = 2

Options.set("bufhidden", "wipe", true, win2, buf2)
Options.set("hidden", true, false, win2, buf2)

local bufl_leave_count = 0
local saw_invalid_current = false

Autocmd.CreateAutocommand({ "BufLeave" }, { "*" }, function()
    bufl_leave_count = bufl_leave_count + 1
    local cur = windows[curwin] and windows[curwin].buffer
    local still_registered = cur and buffers[cur.bufnr] ~= nil
    if not still_registered then
        saw_invalid_current = true
    end
end, nil, nil, false, false, "tabclose-order-probe", nil)

local close_ok = tp:close(win2, true, false, nil)
assert_eq("tabpage close returns true", close_ok, true)
assert_true("BufLeave fired during close", bufl_leave_count >= 1, bufl_leave_count)
assert_eq("BufLeave sees a registered current buffer", saw_invalid_current, false)
assert_eq("closed window removed from registry", windows[2], nil)
assert_eq("current window switched to survivor", curwin, 1)

print("tabpage close BufLeave ordering test: OK")
