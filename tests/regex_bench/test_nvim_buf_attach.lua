local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local mock = MockEnv.setup({
    ccvim_path = "vim",
    module_stubs = {
        ["lib.autocmd"] = {
            Run = function()
                return 0
            end,
        },
    },
})
local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local api = ApiBuild.Build().vim.api

local bufnr = api.nvim_create_buf(true, false)
mock.create_window(1, _G.buffers[bufnr], {})
_G.curwin = 1

local events = {}
local ok = api.nvim_buf_attach(bufnr, false, {
    on_lines = function(...)
        events[#events + 1] = { ... }
    end,
})
assert_eq("attach returns true", ok, true)
assert_eq("changedtick starts at zero", api.nvim_buf_get_changedtick(bufnr), 0)

api.nvim_buf_set_lines(bufnr, 0, 1, false, { "hello" })
assert_eq("on_lines fired once", #events, 1)
assert_eq("event kind", events[1][1], "lines")
assert_eq("event bufnr", events[1][2], bufnr)
assert_eq("event firstline", events[1][4], 0)
assert_eq("event old_lastline", events[1][5], 1)
assert_eq("event new_lastline", events[1][6], 1)
assert_eq("changedtick increments", api.nvim_buf_get_changedtick(bufnr), 1)

local auto_detach_calls = 0
ok = api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
        auto_detach_calls = auto_detach_calls + 1
        return true
    end,
})
assert_eq("attach with detach-once callback", ok, true)
api.nvim_buf_set_lines(bufnr, 0, 1, false, { "hello2" })
api.nvim_buf_set_lines(bufnr, 0, 1, false, { "hello3" })
assert_eq("truthy return detaches callback", auto_detach_calls, 1)

local detached = 0
ok = api.nvim_buf_attach(bufnr, false, {
    on_detach = function()
        detached = detached + 1
    end,
})
assert_eq("attach for on_detach", ok, true)
assert_eq("nvim_buf_detach returns true", api.nvim_buf_detach(bufnr), true)
assert_eq("on_detach called", detached, 1)
assert_eq("second nvim_buf_detach returns false", api.nvim_buf_detach(bufnr), false)

print("nvim_buf_attach tests: OK")
