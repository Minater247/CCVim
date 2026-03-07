local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, ok)
    if not ok then
        error("FAIL " .. label)
    end
end

local mock = MockEnv.setup({
    ccvim_path = "vim",
})

local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local api = ApiBuild.Build()

assert_eq("_ts_get_language_version type", type(api.vim._ts_get_language_version), "function")
assert_eq(
    "_ts_get_minimum_language_version type",
    type(api.vim._ts_get_minimum_language_version),
    "function"
)

local max_version = api.vim._ts_get_language_version()
local min_version = api.vim._ts_get_minimum_language_version()

assert_eq("language version type", type(max_version), "number")
assert_eq("minimum language version type", type(min_version), "number")
assert_true("minimum <= maximum", min_version <= max_version)

local ts = api.require("vim.treesitter")
assert_eq("vim.treesitter.language_version", ts.language_version, max_version)
assert_eq(
    "vim.treesitter.minimum_language_version",
    ts.minimum_language_version,
    min_version
)

print("treesitter language version getter tests: OK")
