local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.excmd.exmsg"] = {
            echo = function() end,
        },
        ["vim.lib.autocmd"] = {
            Run = function()
                return 0
            end,
        },
        ["vim.lib.luaapi.fs"] = {
            abspath = function(path)
                return tostring(path or "")
            end,
        },
        ["vim.lib.syntax"] = {
            ParseLinetypes = function() end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s"):format(label))
    end
end

_G.screen = { width = 40, height = 10 }

local Options = mock.loadModule("lib.options")
_G.options = Options
local Buffer = mock.loadModule("layout.buffer")
local Sign = mock.loadModule("lib.sign")

local buf = Buffer(true, false, true)
buf.name = "/tmp/sign_runtime.lua"
buf.lines = { "one", "two", "three", "four" }
buf.refcount = 0

local win = mock.create_window(1, buf)
win.cursorx = 1
win.cursory = 1
tabpages[1].windows = { win }
curwin = 1
curtp = 1

assert_eq("define sign", Sign.define("WarnSign", { text = "!!", priority = 30 }), 0)
assert_eq("define sign in numeric-name form", Sign.define("001", { text = "??", priority = 10 }), 0)

local id_global = Sign.place(0, "", "WarnSign", buf.bufnr, { lnum = 2 })
local id_group = Sign.place(0, "g1", "WarnSign", buf.bufnr, { lnum = 3 })
assert_eq("first auto id in global group", id_global, 1)
assert_eq("first auto id in named group", id_group, 1)

local placed_all = Sign.getplaced(buf.bufnr, { group = "*" })
assert_eq("placed result has one buffer entry", #placed_all, 1)
assert_eq("placed signs count", #placed_all[1].signs, 2)
assert_eq("first placed lnum ordering", placed_all[1].signs[1].lnum, 2)
assert_eq("second placed lnum ordering", placed_all[1].signs[2].lnum, 3)

assert_eq("move existing id by placing same id", Sign.place(id_global, "", "WarnSign", buf.bufnr, { lnum = 3 }), id_global)
local moved = Sign.getplaced(buf.bufnr, { group = "", id = id_global })
assert_eq("moved sign now on line 3", moved[1].signs[1].lnum, 3)

buf:set_lines(0, 1, false, {})
local shifted = Sign.getplaced(buf.bufnr, { group = "*", lnum = 2 })
assert_eq("both signs shifted up after deleting first line", #shifted[1].signs, 2)

buf:set_lines(1, 2, false, {})
local after_delete = Sign.getplaced(buf.bufnr, { group = "*" })
assert_eq("signs on deleted line are removed", #after_delete[1].signs, 0)

local g0 = Sign.place(0, "", "WarnSign", buf.bufnr, { lnum = 1 })
local g1 = Sign.place(0, "g1", "WarnSign", buf.bufnr, { lnum = 1 })
assert_true("placed signs for unplace test", g0 > 0 and g1 > 0)
assert_eq("unplace one id from global group", Sign.unplace("", { buffer = buf.bufnr, id = g0 }), 0)

local grouped = Sign.getplaced(buf.bufnr, { group = "*" })
assert_eq("group sign remains after removing global id", #grouped[1].signs, 1)
assert_eq("remaining sign group is g1", grouped[1].signs[1].group, "g1")

assert_eq("unplace all groups from buffer", Sign.unplace("*", { buffer = buf.bufnr }), 0)
local empty = Sign.getplaced(buf.bufnr, { group = "*" })
assert_eq("all signs removed", #empty[1].signs, 0)

print("sign runtime tests: OK")
