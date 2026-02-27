local MockEnv = require("vim.tests.test_mocks")

local require_calls = {}
local fake_lsp = {
    util = {
        apply_text_edits = function()
            return true
        end,
    },
    get_clients = function()
        return {}
    end,
}

local function fake_require(name)
    require_calls[#require_calls + 1] = tostring(name)
    if name == "vim.lsp" then
        return fake_lsp
    end
    return {}
end

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.luaapi.require"] = fake_require,
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local env = ApiBuild.Build()

assert_eq("vim.lsp proxy exists", type(env.vim.lsp), "table")
assert_eq("vim._defer_require exists", type(env.vim._defer_require), "function")
assert_eq("lsp not required eagerly", #require_calls, 0)

local util = env.vim.lsp.util
assert_eq("lsp required lazily", require_calls[1], "vim.lsp")
assert_eq("util provided via vim.lsp", util, fake_lsp.util)
assert_eq("apply_text_edits is callable", util.apply_text_edits(), true)

print("vim lsp proxy tests: OK")
