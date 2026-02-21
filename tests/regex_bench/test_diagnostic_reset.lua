local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function count_keys(t)
    local n = 0
    if type(t) ~= "table" then
        return 0
    end
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local Buffer = mock.loadModule("layout.buffer")
local Api = mock.loadModule("lib.luaapi.api")
local Diagnostic = mock.loadModule("lib.luaapi.diagnostic")

local b1 = Buffer(true, false)
b1.name = "/tmp/diag1"
b1.lines = { "one" }
b1.refcount = 1

local b2 = Buffer(true, false)
b2.name = "/tmp/diag2"
b2.lines = { "two" }
b2.refcount = 1

local win = {
    winnr = 1,
    buffer = b1,
    opts = {},
    cursorx = 1,
    cursory = 1,
    scrolly = { 1, 0 },
    scrollx = 0,
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

local ns = Api.nvim_create_namespace("diag-reset-test")
local ns_other = Api.nvim_create_namespace("diag-reset-other")

Api.nvim_buf_set_extmark(b1.bufnr, ns, 0, 0, { virt_text = { { "a", "ErrorMsg" } } })
Api.nvim_buf_set_extmark(b2.bufnr, ns, 0, 0, { virt_text = { { "b", "ErrorMsg" } } })
Api.nvim_buf_set_extmark(b1.bufnr, ns_other, 0, 0, { virt_text = { { "c", "ErrorMsg" } } })

Diagnostic.reset(ns, b1.bufnr)
assert_eq("reset(ns, bufnr) clears target buffer namespace", count_keys(buffers[b1.bufnr]._extmarks[ns]), 0)
assert_eq("reset(ns, bufnr) leaves other buffer namespace", count_keys(buffers[b2.bufnr]._extmarks[ns]), 1)
assert_eq("reset(ns, bufnr) leaves other namespaces", count_keys(buffers[b1.bufnr]._extmarks[ns_other]), 1)

Api.nvim_buf_set_extmark(b1.bufnr, ns, 0, 0, { virt_text = { { "a2", "ErrorMsg" } } })
Diagnostic.reset(ns, 0)
assert_eq("reset(ns, 0) uses current buffer", count_keys(buffers[b1.bufnr]._extmarks[ns]), 0)
assert_eq("reset(ns, 0) does not clear other buffers", count_keys(buffers[b2.bufnr]._extmarks[ns]), 1)

Diagnostic.reset(ns)
assert_eq("reset(ns) clears all buffers", count_keys(buffers[b2.bufnr]._extmarks[ns]), 0)
assert_eq("reset(ns) leaves other namespaces", count_keys(buffers[b1.bufnr]._extmarks[ns_other]), 1)

print("diagnostic reset tests: OK")
