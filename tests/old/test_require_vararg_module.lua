local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local fixture_rel = "tests/regex_bench/fixtures"
local fixture_lua = fixture_rel .. "/lua/varargmod.lua"
local fixture_root = "vim/" .. fixture_rel
local cwd = os.getenv("PWD") or "."

local mock = MockEnv.setup({
    shell = {
        dir = function()
            return cwd
        end,
    },
    fs = {
        exists = function(path)
            local p = tostring(path or ""):gsub("//+", "/")
            return p:sub(-#fixture_lua) == fixture_lua
        end,
        isDir = function(path)
            local p = tostring(path or ""):gsub("//+", "/")
            return p:sub(-#fixture_rel) == fixture_rel or p:sub(-#(fixture_rel .. "/lua")) == (fixture_rel .. "/lua")
        end,
        list = function()
            return {}
        end,
        open = function()
            return nil
        end,
        isReadOnly = function()
            return false
        end,
        getSize = function()
            return 0
        end,
    },
})

local options_mod = mock.loadModule("lib.options")
_G.options = options_mod

options_mod.set("runtimepath", fixture_root, false, nil, nil, true)

local req = mock.loadModule("lib.luaapi.require")
local got = req("varargmod")
assert_eq("require passes module name via vararg", got, "varargmod")

print("require vararg module tests: OK")
