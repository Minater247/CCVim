local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.highlight"] = {
            For = function() return { colors.white, colors.black } end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local buf = mock.create_buffer(1, "/tmp/test_verbose.vim", { "" })
local win = mock.create_window(1, buf)
tabpages[1].windows = { win }

local Options = mock.loadModule("lib.options")
local Runtime = mock.loadModule("lib.excmd.runtime")

Options.set("verbose", 7, false, win, buf, true)
local rt = Runtime.new()

rt:exec_verbose(2, "let g:inside_count = &verbose")
assert_eq("inside explicit count", rt.state.g.inside_count, 2)
assert_eq("restore explicit count", Options.get("verbose", win, buf, false, true), 7)

rt:exec_verbose(1, "let g:inside_default = &verbose")
assert_eq("inside default count", rt.state.g.inside_default, 1)
assert_eq("restore default count", Options.get("verbose", win, buf, false, true), 7)

rt:exec_verbose(2, "set verbose=9")
assert_eq("restore after inner set", Options.get("verbose", win, buf, false, true), 7)

print("verbose command tests: OK")
