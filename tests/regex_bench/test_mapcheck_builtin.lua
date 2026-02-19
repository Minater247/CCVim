local MockEnv = require("vim.tests.test_mocks")

local function install_keys()
    local next_code = 1
    local keymap = {}
    setmetatable(keymap, {
        __index = function(t, k)
            local v = next_code
            next_code = next_code + 1
            rawset(t, k, v)
            return v
        end,
    })

    _G.keys = keymap
end

local mock = MockEnv.setup({
    module_stubs = {
        ["vim.lib.event"] = {
            StartTimer = function() return 1 end,
            CancelTimer = function() end,
        },
        ["vim.lib.excmd.exmsg"] = {
            echo = function() end,
            echon = function() end,
            echomsg = function() end,
            echoerr = function() end,
        },
    },
})

install_keys()

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: expected true, got false (%s)"):format(label, tostring(detail)))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local buf = mock.create_buffer(1, "/tmp/test_mapcheck.vim", { "" }, {})
local win = mock.create_window(1, buf, {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

local Fn = mock.loadModule("vim.lib.luaapi.fn")
local Command = mock.loadModule("vim.lib.command")
local Key = mock.loadModule("vim.lib.key")

Command.clear_mappings({
    "normal",
    "visual",
    "select",
    "operator",
    "insert",
    "lang",
    "cmdline",
    "terminal",
})

Command.remap_keys("normal", Key.strtoseq("abc"), Key.strtoseq("rhsabc"))
assert_eq("mapping starts with name", Fn.mapcheck("a", "n"), "rhsabc")
assert_eq("mapping is prefix of name", Fn.mapcheck("abcd", "n"), "rhsabc")
assert_eq("no mapping returns empty", Fn.mapcheck("zzz", "n"), "")

Command.remap_keys("insert", Key.strtoseq("ii"), Key.strtoseq("insrhs"))
assert_eq("default mode excludes insert", Fn.mapcheck("ii"), "")
assert_eq("insert mode finds insert mapping", Fn.mapcheck("ii", "i"), "insrhs")

Command.remap_keys("select", Key.strtoseq("ss"), Key.strtoseq("selrhs"))
assert_eq("v mode includes select", Fn.mapcheck("ss", "v"), "selrhs")
assert_eq("x mode excludes select-only", Fn.mapcheck("ss", "x"), "")

Command.remap_keys("", Key.strtoseq("mm"), Key.strtoseq("emptymap"))
assert_eq("empty mode maps in normal", Fn.mapcheck("mm", "n"), "emptymap")
assert_eq("empty mode maps in visual", Fn.mapcheck("mm", "x"), "emptymap")
assert_eq("empty mode maps in select", Fn.mapcheck("mm", "s"), "emptymap")
assert_eq("empty mode maps in operator-pending", Fn.mapcheck("mm", "o"), "emptymap")
assert_eq("empty mode does not map in insert", Fn.mapcheck("mm", "i"), "")

Command.remap_keys("normal", Key.strtoseq("xx"), Key.strtoseq("globalrhs"))
Command.remap_keys("normal", Key.strtoseq("xx"), Key.strtoseq("localrhs"), { buffer_local = true })
assert_eq("buffer-local checked before global", Fn.mapcheck("xx", "n"), "localrhs")

Command.remap_keys("normal", Key.strtoseq("<S-Up>"), Key.strtoseq("shiftup"))
assert_eq("special key names are supported", Fn.mapcheck("<S-Up>", "n"), "shiftup")

assert_eq("abbr mode unsupported returns empty", Fn.mapcheck("xx", "n", 1), "")

local ok, err = pcall(function()
    Fn.mapcheck("xx", "n", 0, 1)
end)
assert_true("too many args keeps E118", (not ok) and tostring(err):find("E118", 1, true), tostring(err))

print("mapcheck builtin tests: OK")
