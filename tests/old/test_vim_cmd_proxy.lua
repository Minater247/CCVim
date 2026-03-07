local MockEnv = require("vim.tests.test_mocks")

local stub_calls = {
    runtime_run = {},
    nvim_cmd = {},
}

local scopes_stub = {
    _v = { errmsg = "" },
    g = {},
    v = {},
    b = {},
    w = {},
    t = {},
}

local modules = {
    ["lib.luaapi.api"] = {
        nvim_cmd = function(cmd, opts)
            stub_calls.nvim_cmd[#stub_calls.nvim_cmd + 1] = {
                cmd = cmd,
                opts = opts,
            }
            return ""
        end,
    },
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
        run = function(line)
            stub_calls.runtime_run[#stub_calls.runtime_run + 1] = line
            return true, ""
        end,
        _FUNCS = {},
    },
    ["lib.luaapi.fn"] = { _proxy = {} },
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
        end,
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

local function assert_true(label, cond)
    if not cond then
        error("FAIL " .. label)
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

assert_eq("vim.cmd is table", type(api.vim.cmd), "table")
assert_true("vim.cmd has __call", type(getmetatable(api.vim.cmd).__call) == "function")

local rv = api.vim.cmd("set number")
assert_eq("vim.cmd string call returns empty string", rv, "")
assert_eq("vim.cmd string call routes to Runtime.run", stub_calls.runtime_run[#stub_calls.runtime_run], "set number")

local vals = api.vim.tbl_values({ a = 1, b = 2 })
assert_eq("vim.tbl_values returns list size", #vals, 2)
assert_true("vim.tbl_values contains 1", api.vim.tbl_contains(vals, 1))
assert_true("vim.tbl_values contains 2", api.vim.tbl_contains(vals, 2))
local keys = api.vim.tbl_keys({ a = 1, b = 2 })
assert_eq("vim.tbl_keys returns list size", #keys, 2)
assert_true("vim.tbl_keys contains 'a'", api.vim.tbl_contains(keys, "a"))
assert_true("vim.tbl_keys contains 'b'", api.vim.tbl_contains(keys, "b"))
local dst = { 1 }
local out = api.vim.list_extend(dst, { 2, 3, 4 }, 2, 3)
assert_true("vim.list_extend returns destination table", out == dst)
assert_eq("vim.list_extend appends selected range", #dst, 3)
assert_eq("vim.list_extend appended first", dst[2], 3)
assert_eq("vim.list_extend appended second", dst[3], 4)
local dict_dst = { a = 1 }
api.vim.list_extend(dict_dst, { 9 })
assert_eq("vim.list_extend allows dict-like dst", dict_dst[1], 9)
assert_eq("vim.list_extend preserves existing dict keys", dict_dst.a, 1)
local dict_src_target = { 1 }
api.vim.list_extend(dict_src_target, { a = 2 })
assert_eq("vim.list_extend with dict-like src is no-op by default range", #dict_src_target, 1)
local ok_dst_type = pcall(function() api.vim.list_extend("x", { 1 }) end)
assert_eq("vim.list_extend validates dst type", ok_dst_type, false)
local ok_src_type = pcall(function() api.vim.list_extend({ 1 }, "x") end)
assert_eq("vim.list_extend validates src type", ok_src_type, false)
local ok_start_type = pcall(function() api.vim.list_extend({ 1 }, { 2 }, "x") end)
assert_eq("vim.list_extend validates start type", ok_start_type, false)
local ok_finish_type = pcall(function() api.vim.list_extend({ 1 }, { 2 }, 1, "x") end)
assert_eq("vim.list_extend validates finish type", ok_finish_type, false)
assert_eq("vim.trim trims outer whitespace", api.vim.trim("  x  "), "x")
assert_eq("vim.trim all-whitespace yields empty", api.vim.trim(" \t\r\n "), "")
local ok_trim_type = pcall(function()
    api.vim.trim(42)
end)
assert_eq("vim.trim validates input type", ok_trim_type, false)

api.vim.cmd.highlight("clear")
local cmd1 = stub_calls.nvim_cmd[#stub_calls.nvim_cmd].cmd
assert_eq("indexed cmd uses command name", cmd1.cmd, "highlight")
assert_eq("indexed cmd passes positional arg", cmd1.args[1], "clear")

api.vim.cmd.highlight({ "clear", bang = true })
local cmd2 = stub_calls.nvim_cmd[#stub_calls.nvim_cmd].cmd
assert_eq("indexed table keeps bang", cmd2.bang, true)
assert_eq("indexed table positional moved to args", cmd2.args[1], "clear")
assert_true("indexed table removes numeric slot", cmd2[1] == nil)

api.vim.cmd({ cmd = "highlight", args = { "clear" } })
local cmd3 = stub_calls.nvim_cmd[#stub_calls.nvim_cmd].cmd
assert_eq("table-form call command", cmd3.cmd, "highlight")
assert_eq("table-form call arg", cmd3.args[1], "clear")

modules["lib.excmd.runtime"].run = function(_)
    return false, {
        toString = function()
            return "E492: Not an editor command"
        end,
    }
end

local ok, _ = pcall(api.vim.cmd, "badcmd")
assert_eq("vim.cmd string errors via pcall", ok, false)
assert_eq("vim.cmd sets v:errmsg", scopes_stub._v.errmsg, "E492: Not an editor command")

print("vim.cmd proxy tests: OK")
