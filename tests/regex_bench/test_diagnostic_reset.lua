local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Buffer = mock.loadModule("layout.buffer")
local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local vimapi = ApiBuild.Build().vim
local Api = vimapi.api
local Diagnostic = vimapi.diagnostic

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

local function put_diag(namespace, bufnr, msg)
    Diagnostic.set(namespace, bufnr, {
        {
            lnum = 0,
            col = 0,
            end_lnum = 0,
            end_col = 1,
            severity = Diagnostic.severity.ERROR,
            message = msg,
            source = "test",
        },
    }, {
        underline = false,
        virtual_text = false,
        signs = false,
    })
end

local function diag_count(bufnr, namespace)
    return #Diagnostic.get(bufnr, { namespace = namespace })
end

put_diag(ns, b1.bufnr, "a")
put_diag(ns, b2.bufnr, "b")
put_diag(ns_other, b1.bufnr, "c")

Diagnostic.reset(ns, b1.bufnr)
assert_eq("reset(ns, bufnr) clears target buffer namespace", diag_count(b1.bufnr, ns), 0)
assert_eq("reset(ns, bufnr) leaves other buffer namespace", diag_count(b2.bufnr, ns), 1)
assert_eq("reset(ns, bufnr) leaves other namespaces", diag_count(b1.bufnr, ns_other), 1)

put_diag(ns, b1.bufnr, "a2")
Diagnostic.reset(ns, 0)
assert_eq("reset(ns, 0) uses current buffer", diag_count(b1.bufnr, ns), 0)
assert_eq("reset(ns, 0) does not clear other buffers", diag_count(b2.bufnr, ns), 1)

Diagnostic.reset(ns)
assert_eq("reset(ns) clears all buffers", diag_count(b2.bufnr, ns), 0)
assert_eq("reset(ns) leaves other namespaces", diag_count(b1.bufnr, ns_other), 1)

print("diagnostic reset tests: OK")
