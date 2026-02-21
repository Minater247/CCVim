local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("vim.lib.options")
_G.options = Options

local Tab = mock.loadModule("vim.lib.tab")
local TexRen = mock.loadModule("vim.lib.texren")

local buf = mock.create_buffer(1, "/tmp/texren-utf8.txt", { "" })
local params = {
    wraplen = 0,
    wordwrap = false,
    tabcfg = Tab.get_tab_config(buf),
}

do
    local lines = TexRen.parse("é", params)
    assert_eq("utf8 latin-1 fallback", lines[1], "?")
end

do
    local lines = TexRen.parse("✓", params)
    assert_eq("utf8 checkmark fallback", lines[1], "v")
end

do
    local lines = TexRen.parse("aé", params)
    assert_eq("mixed ascii/utf8 fallback", lines[1], "a?")
end

do
    local lines, _, pos = TexRen.parse("aé", params, 2)
    assert_eq("bytepos maps to second cell", pos.column, 2)
    assert_eq("bytepos character maps through fallback", pos.ch, "?")
    assert_eq("bytepos line", pos.line, 1)
    assert_eq("rendered line", lines[1], "a?")
end

print("texren utf8 ascii rendering tests: OK")
