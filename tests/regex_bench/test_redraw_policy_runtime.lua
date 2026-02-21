local MockEnv = require("vim.tests.test_mocks")

local exmsg_stub = {
    messages = {},
    echo = function() end,
    echon = function() end,
    echomsg = function() end,
    echoerr = function() end,
    echohl = function() end,
    PushSilent = function() end,
    PushUnsilent = function() end,
    PushUISuppress = function() end,
    PopUISuppress = function() end,
    StartCapture = function() return {} end,
    EndCapture = function() return "", nil end,
    PopSilent = function() end,
    _writeWithHL = function() end,
}

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.exmsg"] = function() return exmsg_stub end,
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
        ["vim.lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
            emit_raw = function() end,
        },
        ["vim.lib.key"] = {
            strtoseq = function(s)
                local out = {}
                for i = 1, #s do
                    out[#out + 1] = s:sub(i, i)
                end
                return out
            end,
        },
        ["vim.lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["vim.lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["vim.lib.syntax"] = {
            ParseLinetypes = function() end,
            OnWindowBufferChanged = function() end,
            OnSyntaxOptionSet = function() end,
            OnSynmaxcolOptionSet = function() end,
        },
        ["vim.lib.autocmd"] = {
            Run = function() return 0 end,
            CreateAutocommand = function() return 1 end,
            RemoveAutocommands = function() return 0 end,
            GetAutocommands = function() return {} end,
            DeleteAutocommand = function() return false end,
            NormalizeEvent = function(ev) return ev end,
        },
        ["vim.lib.tags"] = {
            SearchFile = function() return nil end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Buffer = mock.loadModule("layout.buffer")
local Api = mock.loadModule("lib.luaapi.api")

local buf = Buffer(true, false)
buf.name = "/tmp/redraw_policy"
buf.lines = { "a" }
buf.refcount = 1

local win = {
    winnr = 1,
    buffer = buf,
    opts = {},
    cursorx = 1,
    cursory = 1,
    scrolly = { 1, 0 },
    scrollx = 1,
    need_redraw = false,
    cursorSet = function(self, x, y)
        self.cursorx = x
        self.cursory = y
    end,
}
windows[1] = win
tabpages[1].windows = { win }
curtp = 1
curwin = 1

local function reset_redraw()
    need_redraw = false
    what_redraw = {}
    win.need_redraw = false
end

do
    reset_redraw()
    Options.set("showcmd", false, false, win, buf, true)
    assert_eq("global option change triggers full redraw", what_redraw.all, true)
end

do
    reset_redraw()
    Options.set("number", false, true, win, buf)
    assert_eq("window-local option marks current window", win.need_redraw, true)
    assert_true("window-local option does not force full redraw", what_redraw.all ~= true, tostring(what_redraw.all))
end

do
    reset_redraw()
    Options.set("number", true, false, win, buf, true)
    assert_eq("setglobal on window-local option triggers full redraw", what_redraw.all, true)
end

do
    reset_redraw()
    Options.exset_token("number", "local", win, buf)
    assert_eq(":setlocal option marks current window", win.need_redraw, true)
    assert_true(":setlocal option does not force full redraw", what_redraw.all ~= true, tostring(what_redraw.all))
end

do
    reset_redraw()
    buf:set_lines(0, 1, false, { "b" })
    assert_eq("buffer mutation triggers full redraw", what_redraw.all, true)
end

do
    reset_redraw()
    Api.nvim_buf_set_lines(buf.bufnr, 0, 1, false, { "c" })
    assert_eq("nvim_buf_set_lines triggers full redraw", what_redraw.all, true)
    assert_eq("nvim_buf_set_lines marks window redraw", win.need_redraw, true)
end

print("redraw policy runtime tests: OK")
