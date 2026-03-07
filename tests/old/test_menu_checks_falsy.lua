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
        ["lib.autocmd"] = { Run = function() return 0 end },
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
        ["lib.tags"] = { SearchFile = function() return nil end },
        ["lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["lib.pack"] = { add = function() return true end, load_start = function() return true end },
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

local function err_code(err)
    if type(err) == "table" and err.code then
        return err.code
    end
    local s = tostring(err or "")
    local c = tonumber(s:match("E(%d+):"))
    return c
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")

local test_buf = mock.create_buffer(1, "/tmp/test_menu_checks_falsy.vim", { "" }, {})
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

local function run(cmd)
    return Runtime.run(cmd, {
        state = state,
        script_ctx = "/tmp/test_menu_checks_falsy.vim",
    })
end

do
    local ok, err = run("amenu One.Two :let g:v=1<CR>")
    assert_true("define menu succeeds", ok == true, err)
end

do
    local ok, err = run("amenu disable One.*")
    assert_true("disable existing wildcard succeeds", ok == true, err)
end

do
    local ok, err = run("amenu disable Missing.*")
    assert_true("disable missing wildcard errors", ok ~= true, err)
    assert_eq("disable missing wildcard code", err_code(err), 329)
end

do
    local ok, err = run("amenu disable .")
    assert_true("disable invalid path errors", ok ~= true, err)
    assert_eq("disable invalid path code", err_code(err), 475)
end

do
    local ok, err = run("aunmenu Missing")
    assert_true("unmenu missing errors", ok ~= true, err)
    assert_eq("unmenu missing code", err_code(err), 329)
end

do
    local ok, err = run("aunmenu .")
    assert_true("unmenu invalid path errors", ok ~= true, err)
    assert_eq("unmenu invalid path code", err_code(err), 475)
end

do
    local ok, err = run("tmenu One.Two.Three Tip")
    assert_true("tooltip define succeeds", ok == true, err)
end

do
    local ok, err = run("tunmenu One.*")
    assert_true("tooltip wildcard segment errors", ok ~= true, err)
    assert_eq("tooltip wildcard segment code", err_code(err), 329)
end

do
    local ok, err = run("tunmenu *")
    assert_true("tooltip clear all succeeds", ok == true, err)
end

do
    local ok, err = run("tunmenu .")
    assert_true("tooltip invalid path errors", ok ~= true, err)
    assert_eq("tooltip invalid path code", err_code(err), 475)
end

do
    local ok, err = run("emenu Missing.Menu")
    assert_true("emenu missing errors", ok ~= true, err)
    assert_eq("emenu missing code", err_code(err), 334)
end

do
    local ok, err = run("amenu <unique> Unique.Menu :let g:u=1<CR>")
    assert_true("unique first define succeeds", ok == true, err)
end

do
    local ok, err = run("amenu <unique> Unique.Menu :let g:u=2<CR>")
    assert_true("unique duplicate errors", ok ~= true, err)
    assert_eq("unique duplicate code", err_code(err), 474)
end

do
    local ok, err = run("amenu Unique.Menu :let g:u=3<CR>")
    assert_true("non-unique overwrite succeeds", ok == true, err)
end

print("menu falsy-check regression tests: OK")
