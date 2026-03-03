local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local mock = MockEnv.setup({
    ccvim_path = "vim",
})

local sentinel_bit = {
    band = function(a, b)
        return a & b
    end,
    bor = function(a, b)
        return a | b
    end,
    tohex = function(n)
        return string.format("%x", n)
    end,
}

_G.bit = sentinel_bit

local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local api = ApiBuild.Build()

assert_eq("bit preloaded in package.loaded", api.package.loaded.bit, sentinel_bit)
assert_eq("require('bit') resolves global bit table", api.require("bit"), sentinel_bit)
assert_eq("second require('bit') returns same table", api.require("bit"), sentinel_bit)

print("require('bit') preload test: OK")
