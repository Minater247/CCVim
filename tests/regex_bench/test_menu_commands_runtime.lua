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
    PopSilent = function() end,
    _writeWithHL = function() end,
}

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.exmsg"] = function() return exmsg_stub end,
        ["lib.excmd.exmsg"] = exmsg_stub,
        ["lib.autocmd"] = {
            Run = function() return 0 end,
        },
        ["lib.sign"] = {
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
        ["lib.tags"] = {
            SearchFile = function() return nil end,
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
        ["lib.key"] = {
            strtoseq = function() return {} end,
        },
        ["layout.buffer"] = {},
        ["layout.window"] = {},
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

local Options = mock.loadModule("lib.options")
_G.options = Options

local Runtime = mock.loadModule("lib.excmd.runtime")
local Commands = mock.loadModule("lib.excmd.commands")
local Scopes = mock.loadModule("lib.luaapi.scopes")

local test_buf = mock.create_buffer(1, "/tmp/test_menu_commands_runtime.vim", { "" }, {})
local test_win = mock.create_window(1, test_buf, {})
mock.create_tabpage(1, { test_win }, {})
curtp = 1
curwin = 1

local state = {
    g = Scopes._g,
    s = {},
    v = Scopes._v,
    funcs = Runtime._FUNCS,
    frames = {},
    commands = {},
}

local ok, rv = Runtime.run([[
menut clear
menutrans Foo Baz
amenu Foo.Action :let g:menu_exec = 42<CR>
amenu disable Baz.*
amenu enable Foo.Action
tmenu ToolBar.Open Open\ file
tunmenu ToolBar
an 10.10 PopUp.Test let g:from_an = 1
emenu Foo.Action
]], {
    state = state,
    script_ctx = "/tmp/test_menu_commands_runtime.vim",
})

assert_true("runtime run succeeds", ok == true, rv)
assert_eq("menu action executed via emenu", Scopes._g.menu_exec, 42)

local menus = state.menus
assert_true("menu state exists", type(menus) == "table", type(menus))

local all_modes = menus.items and menus.items.a
assert_true("all-modes bucket exists", type(all_modes) == "table", type(all_modes))

local item = all_modes["Foo.Action"]
assert_true("menu item stored", type(item) == "table", type(item))
assert_eq("translated menu path stored", item.translated, "Baz.Action")
assert_eq("menu item enabled after enable", item.enabled, true)

assert_true("tooltips removed by tunmenu", next(menus.tooltips or {}) == nil, tostring(next(menus.tooltips or {})))
local abbrev_cases = {
    { "an", "anoremenu" },
    { "me", "menu" },
    { "noreme", "noremenu" },
    { "unme", "unmenu" },
    { "cme", "cmenu" },
    { "cnoreme", "cnoremenu" },
    { "ime", "imenu" },
    { "inoreme", "inoremenu" },
    { "nme", "nmenu" },
    { "nnoreme", "nnoremenu" },
    { "onoreme", "onoremenu" },
    { "snoreme", "snoremenu" },
    { "vme", "vmenu" },
    { "vnoreme", "vnoremenu" },
    { "xme", "xmenu" },
    { "xnoreme", "xnoremenu" },
    { "tm", "tmenu" },
    { "tu", "tunmenu" },
    { "tln", "tlnoremenu" },
    { "tlu", "tlunmenu" },
    { "menut", "menutranslate" },
    { "menutrans", "menutranslate" },
}
for i = 1, #abbrev_cases do
    local abbr = abbrev_cases[i][1]
    local want = abbrev_cases[i][2]
    assert_eq("menu abbrev " .. abbr, Commands.resolve_dispatch_name(abbr), want)
end

print("menu command runtime tests: OK")
