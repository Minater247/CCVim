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
    ["vim.lib.luaapi.api"] = {
        nvim_cmd = function(cmd, opts)
            stub_calls.nvim_cmd[#stub_calls.nvim_cmd + 1] = {
                cmd = cmd,
                opts = opts,
            }
            return ""
        end,
    },
    ["vim.lib.luaapi.loop"] = {},
    ["vim.lib.luaapi.fakejit"] = {},
    ["vim.lib.luaapi.opts"] = {
        wo = {},
        bo = {},
        go = {},
        o = {},
    },
    ["vim.lib.luaapi.on_key"] = {
        set_namespace_allocator = function(_) end,
        on_key = function() return 0 end,
        dispatch = function() return false end,
    },
    ["vim.lib.excmd.runtime"] = {
        run = function(line)
            stub_calls.runtime_run[#stub_calls.runtime_run + 1] = line
            return true, ""
        end,
        _FUNCS = {},
    },
    ["vim.lib.luaapi.fn"] = { _proxy = {} },
    ["vim.lib.luaapi.deferfn"] = function() end,
    ["vim.lib.luaapi.split"] = function(s) return s end,
    ["vim.lib.luaapi.require"] = function(name) return require(name) end,
    ["vim.lib.luaapi.keymap"] = {},
    ["vim.lib.luaapi.package"] = {},
    ["vim.lib.luaapi.fileload"] = {
        Bind = function(_)
            return {
                loadfile = _G.loadfile,
                load = _G.load,
                dofile = _G.dofile,
                pcall = _G.pcall,
            }
        end,
    },
    ["vim.lib.luaapi.opt"] = {},
    ["vim.lib.luaapi.tblutils"] = {
        extend = function(_, lhs, rhs)
            local out = {}
            for k, v in pairs(lhs or {}) do out[k] = v end
            for k, v in pairs(rhs or {}) do out[k] = v end
            return out
        end,
        deep_extend = function(_, lhs, rhs)
            local out = {}
            for k, v in pairs(lhs or {}) do out[k] = v end
            for k, v in pairs(rhs or {}) do out[k] = v end
            return out
        end,
        contains = function(tbl, value)
            for i = 1, #tbl do
                if tbl[i] == value then return true end
            end
            return false
        end,
        filter = function(f, tbl)
            local out = {}
            for i = 1, #tbl do
                if f(tbl[i]) then out[#out + 1] = tbl[i] end
            end
            return out
        end,
        isempty = function(tbl)
            return next(tbl) == nil
        end,
        map = function(f, tbl)
            local out = {}
            for i = 1, #tbl do
                out[i] = f(tbl[i])
            end
            return out
        end,
        deepcopy = function(v)
            if type(v) ~= "table" then return v end
            local out = {}
            for k, vv in pairs(v) do
                out[k] = vv
            end
            return out
        end,
    },
    ["vim.lib.luaapi.timerutils"] = {
        schedule = function(fn) return fn() end,
        schedule_wrap = function(fn) return fn end,
    },
    ["vim.lib.luaapi.log"] = {},
    ["vim.lib.luaapi.notify"] = {
        notify = function(_) end,
    },
    ["vim.lib.luaapi.scopes"] = scopes_stub,
    ["vim.lib.luaapi.print"] = {
        print = _G.print,
        inspect = function(v) return tostring(v) end,
    },
    ["vim.lib.luaapi.diagnostic"] = {},
    ["vim.lib.luaapi.env"] = {},
    ["vim.lib.luaapi.system"] = {},
    ["vim.lib.luaapi.strutils"] = {
        startswith = function(s, p)
            return tostring(s):sub(1, #p) == p
        end,
    },
    ["vim.lib.luaapi.fs"] = {},
    ["vim.lib.luaapi.F"] = {},
    ["vim.lib.excmd.vim_regex"] = {
        compile = function(_)
            return true
        end,
        find_compiled = function(_, _, _)
            return nil
        end,
    },
    ["vim.lib.luaapi.treesitter"] = {},
}

_G.LOG_DEBUG = function(...) end
_G.LOG_ERROR = function(...) end
_G._log_caller = function(...) end

function _G.loadModule(name)
    local mod = modules[name]
    if not mod then
        error("missing module stub: " .. tostring(name))
    end
    return mod
end

local env = setmetatable({
    _V = {},
    loadModule = _G.loadModule,
    LOG_DEBUG = _G.LOG_DEBUG,
    LOG_ERROR = _G.LOG_ERROR,
    _log_caller = _G._log_caller,
}, { __index = _G })

local chunk = assert(loadfile("vim/lib/luaapi/apibuild.lua", "t", env))
local ApiBuild = chunk()
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

modules["vim.lib.excmd.runtime"].run = function(_)
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
