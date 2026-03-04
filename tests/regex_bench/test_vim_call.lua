local MockEnv = require("vim.tests.test_mocks")

local calls = {}

local scopes_stub = {
    _v = { errmsg = "" },
    g = {},
    v = {},
    b = {},
    w = {},
    t = {},
}

local modules = {
    ["lib.luaapi.api"] = {},
    ["lib.luaapi.loop"] = {},
    ["lib.luaapi.fakejit"] = {},
    ["lib.luaapi.opts"] = {
        wo = {},
        bo = {},
        go = {},
        o = {},
    },
    ["lib.luaapi.on_key"] = {
        set_namespace_allocator = function(_) end,
        on_key = function() return 0 end,
        dispatch = function() return false end,
    },
    ["lib.excmd.runtime"] = {
        run = function(_)
            return true, ""
        end,
        _FUNCS = {},
    },
    ["lib.luaapi.fn"] = {
        _call = function(name, ...)
            local packed = { n = select("#", ...), ... }
            calls[#calls + 1] = {
                name = name,
                args = packed,
            }
            return packed.n
        end,
    },
    ["lib.luaapi.deferfn"] = function() end,
    ["lib.luaapi.require"] = function(name) return require(name) end,
    ["lib.luaapi.keymap"] = {},
    ["lib.luaapi.package"] = {},
    ["lib.luaapi.fileload"] = {
        Bind = function(_)
            return {
                loadfile = _G.loadfile,
                load = _G.load,
                dofile = _G.dofile,
                pcall = _G.pcall,
            }
        end
    },
    ["lib.luaapi.opt"] = {},
    ["lib.luaapi.timerutils"] = {
        schedule = function(fn) return fn() end,
        schedule_wrap = function(fn) return fn end,
    },
    ["lib.luaapi.log"] = {},
    ["lib.luaapi.notify"] = {
        notify = function(_) end,
    },
    ["lib.luaapi.scopes"] = scopes_stub,
    ["lib.luaapi.print"] = {
        print = _G.print,
        inspect = function(v) return tostring(v) end,
    },
    ["lib.luaapi.diagnostic"] = {},
    ["lib.luaapi.env"] = {},
    ["lib.luaapi.system"] = {},
    ["lib.luaapi.strutils"] = {
        str_utfindex = function(s)
            return #tostring(s or "")
        end,
        str_byteindex = function(_, _, idx)
            return idx or 0
        end,
        regex = function()
            return {
                match_str = function()
                    return nil
                end,
            }
        end,
    },
    ["lib.luaapi.fs"] = {},
    ["lib.excmd.vim_regex"] = {
        compile = function(_)
            return true
        end,
        find_compiled = function(_, _, _)
            return nil
        end,
    },
    ["lib.luaapi.treesitter"] = {},
}

local mock = MockEnv.setup({
    ccvim_path = "vim",
    _V = {},
    module_stubs = modules,
})

_G._log_caller = function() end

local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local api = ApiBuild.Build()

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

assert_eq("vim.call is function", type(api.vim.call), "function")

local rv = api.vim.call("len", { 1, 2, 3 })
assert_eq("vim.call returns stub result", rv, 1)
local c1 = calls[#calls]
assert_eq("vim.call function name", c1.name, "len")
assert_eq("vim.call passes one argument", c1.args.n, 1)
assert_eq("vim.call argument preserved as table", type(c1.args[1]), "table")
assert_eq("vim.call argument table length", #c1.args[1], 3)

rv = api.vim.call("getpid")
assert_eq("vim.call without args", rv, 0)
local c2 = calls[#calls]
assert_eq("vim.call no-args name", c2.name, "getpid")
assert_eq("vim.call no-args count", c2.args.n, 0)

rv = api.vim.call("getpid", nil)
assert_eq("vim.call explicit nil arg", rv, 1)
local c3 = calls[#calls]
assert_eq("vim.call explicit nil count", c3.args.n, 1)
assert_eq("vim.call explicit nil value", c3.args[1], nil)

rv = api.vim.call(123)
assert_eq("vim.call coerces function name", rv, 0)
local c4 = calls[#calls]
assert_eq("vim.call coerced name", c4.name, "123")

print("vim.call tests: OK")
