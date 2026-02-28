local ApiBuild = {}

local api = loadModule("lib.luaapi.api")
local loop = loadModule("lib.luaapi.loop")
local _jit = rawget(_G, 'jit')
local jit = _jit or loadModule("lib.luaapi.fakejit")
local opts = loadModule("lib.luaapi.opts")
local on_key = loadModule("lib.luaapi.on_key")
local Runtime = loadModule("lib.excmd.runtime")
local fn = loadModule("lib.luaapi.fn")
local defer_fn = loadModule("lib.luaapi.deferfn")
local require = loadModule("lib.luaapi.require")
local keymap = loadModule("lib.luaapi.keymap")
local package = loadModule("lib.luaapi.package")
local fileload = loadModule("lib.luaapi.fileload")
local opt = loadModule("lib.luaapi.opt")
local timerutils = loadModule("lib.luaapi.timerutils")
local log = loadModule("lib.luaapi.log")
local notify = loadModule("lib.luaapi.notify")
local scopes = loadModule("lib.luaapi.scopes")
local print = loadModule("lib.luaapi.print")
local diagnostic = loadModule("lib.luaapi.diagnostic")
local env = loadModule("lib.luaapi.env")
local system = loadModule("lib.luaapi.system")
local strutils = loadModule("lib.luaapi.strutils")
local vimfs = loadModule("lib.luaapi.fs")
local treesitter = loadModule("lib.luaapi.treesitter")

local mainapi
local VIM_NIL = setmetatable({}, {
    __tostring = function()
        return "vim.NIL"
    end,
})
-- TODO: what? is this documented? Why 20?
local VIM_CMD_ARG_MAX = 20
local SHARED_VIM_EXPORTS = {
    "deepcopy",
    "gsplit",
    "split",
    "tbl_keys",
    "tbl_values",
    "tbl_map",
    "tbl_filter",
    "tbl_contains",
    "list_contains",
    "tbl_isempty",
    "tbl_extend",
    "tbl_deep_extend",
    "deep_equal",
    "tbl_add_reverse_lookup",
    "tbl_get",
    "list_extend",
    "tbl_flatten",
    "spairs",
    "isarray",
    "tbl_islist",
    "islist",
    "tbl_count",
    "list_slice",
    "_list_insert",
    "_list_remove",
    "trim",
    "pesc",
    "startswith",
    "endswith",
    "validate",
    "is_callable",
    "defaulttable",
    "ringbuf",
    "_defer_require",
    "_defer_deprecated_module",
    "_resolve_bufnr",
    "_ensure_list",
}

-- TODO: we need a print function.
-- functions print as <function>, so this knowledge is kept somewhere

local function load_shared_vim_functions(vim_table, require_fn, table_compat)
    local shared_path = ccvim_path .. "/runtime/lua/vim/shared.lua"

    local shared_vim = setmetatable({}, {
        __index = vim_table,
    })

    local shared_env = {
        assert = assert,
        error = error,
        getmetatable = getmetatable,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        pcall = pcall,
        rawequal = rawequal,
        rawget = rawget,
        rawset = rawset,
        select = select,
        setmetatable = setmetatable,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = unpack or table.unpack,
        math = math,
        string = string,
        table = table_compat,
        require = require_fn,
        vim = shared_vim,
    }
    shared_env._G = shared_env

    local chunk, chunk_err = loadfile(shared_path, "t", shared_env)
    if not chunk then
        error(chunk_err)
    end

    local ok, exec_err = pcall(chunk)
    if not ok then
        error(exec_err)
    end

    for i = 1, #SHARED_VIM_EXPORTS do
        local name = SHARED_VIM_EXPORTS[i]
        local fn = shared_vim[name]
        if type(fn) == "function" then
            vim_table[name] = fn
        end
    end
end

local function load_runtime_vim_F(table_compat)
    local path = ccvim_path .. "/runtime/lua/vim/F.lua"
    local env = {
        assert = assert,
        error = error,
        pcall = pcall,
        select = select,
        unpack = unpack or table.unpack,
        type = type,
        table = table_compat,
    }
    env._G = env

    local chunk, chunk_err = loadfile(path, "t", env)
    if not chunk then
        error(chunk_err)
    end

    local ok, mod = pcall(chunk)
    if not ok then
        error(mod)
    end
    return mod
end

function ApiBuild.Build()
    if mainapi then return mainapi end

    on_key.set_namespace_allocator(api.nvim_create_namespace)

    local function vim_with(context, f)
        if type(context) ~= "table" then
            error("context: expected table", 2)
        end
        if type(f) ~= "function" then
            error("f: expected function", 2)
        end

        if context.buf ~= nil then
            return api.nvim_buf_call(context.buf, f)
        end

        return f()
    end

    local filetype_proxy = setmetatable({}, {
        __index = function(_, key)
            local mod = require("vim.filetype")
            mainapi.vim.filetype = mod
            return mod[key]
        end,
    })

    local iter_mod
    local function load_iter_mod()
        if iter_mod == nil then
            local path = ccvim_path .. "/runtime/lua/vim/iter.lua"
            local table_shim = setmetatable({
                maxn = function(t)
                    local maxk = 0
                    for k, _ in pairs(t) do
                        if type(k) == "number" and k > maxk then
                            maxk = k
                        end
                    end
                    return maxk
                end,
            }, { __index = table })
            local iter_env = setmetatable({ table = table_shim }, { __index = mainapi })
            local chunk, err = loadfile(path, "t", iter_env)
            if not chunk then
                error(err)
            end
            iter_mod = chunk()
        end
        return iter_mod
    end

    local iter_proxy = setmetatable({}, {
        __call = function(_, ...)
            local mod = load_iter_mod()
            mainapi.vim.iter = mod
            return mod(...)
        end,
        __index = function(_, key)
            local mod = load_iter_mod()
            mainapi.vim.iter = mod
            return mod[key]
        end,
    })

    local function run_cmdline(line)
        local ok, rv = Runtime.run(line, {
            state = {
                g = scopes._g,
                s = {},
                v = scopes._v,
                funcs = Runtime._FUNCS,
                frames = {},
                commands = {},
            },
            origin = {
                kind = "lua-inline",
                api = "vim.cmd",
            },
        })
        if not ok then
            local msg = rv:toString()
            scopes._v.errmsg = msg
            error(msg)
        end
        return rv
    end

    local cmd_proxy = setmetatable({}, {
        __call = function(_, command)
            if type(command) == "table" then
                return api.nvim_cmd(command, {})
            end
            run_cmdline(command)
            return ""
        end,
        __index = function(t, command)
            t[command] = function(...)
                local opts
                if select("#", ...) == 1 and type(select(1, ...)) == "table" then
                    opts = select(1, ...)
                    if opts[1] and not opts.args then
                        opts.args = {}
                        for i = 1, VIM_CMD_ARG_MAX do
                            if not opts[i] then
                                break
                            end
                            opts.args[i] = opts[i]
                            opts[i] = nil
                        end
                    end
                else
                    opts = { args = { ... } }
                end
                opts.cmd = command
                return api.nvim_cmd(opts, {})
            end
            return t[command]
        end,
    })

    local function table_maxn(t)
        local maxk = 0
        for k, _ in pairs(t) do
            if type(k) == "number" and k > maxk then
                maxk = k
            end
        end
        return maxk
    end

    local table_compat = setmetatable({
        maxn = table_maxn,
    }, { __index = table })

    local lsp_proxy = setmetatable({}, {
        __index = function(t, key)
            local mod = require("vim.lsp")
            mainapi.vim.lsp = mod
            t = mod
            return t[key]
        end,
    })

    mainapi = {
        vim = {
            api = api,
            loop = loop,
            uv = loop,
            wo = opts.wo,
            bo = opts.bo,
            go = opts.go,
            o = opts.o,
            cmd = cmd_proxy,
            fn = fn._proxy,
            g = scopes.g,
            v = scopes.v,
            b = scopes.b,
            w = scopes.w,
            t = scopes.t,
            NIL = VIM_NIL,
            deprecate = function() end,
            defer_fn = defer_fn,
            keymap = keymap,
            opt = opt,
            schedule = timerutils.schedule,
            schedule_wrap = timerutils.schedule_wrap,
            wait = timerutils.wait,
            in_fast_event = timerutils.in_fast_event,
            log = log,
            notify = notify.notify,
            notify_once = notify.notify_once,
            print = print.print,
            inspect = print.inspect,
            diagnostic = diagnostic,
            env = env,
            system = system,
            fs = vimfs,
            filetype = filetype_proxy,
            iter = iter_proxy,
            treesitter = treesitter,
            lsp = lsp_proxy,
            str_utfindex = strutils.str_utfindex,
            str_byteindex = strutils.str_byteindex,
            regex = strutils.regex,
            _with = vim_with,
            on_key = on_key.on_key,
            _on_key = on_key.dispatch,
        },
        jit = jit,
        require = require,
        package = package,
        table = table_compat,

        -- DEBUG
        LOG_DEBUG = LOG_DEBUG,
        LOG_ERROR = LOG_ERROR,
        _log_caller = _log_caller,
    }

    setmetatable(mainapi, {
        __index = _G
    })

    mainapi.vim._empty_dict_mt = {}
    mainapi.vim.empty_dict = function()
        return setmetatable({}, mainapi.vim._empty_dict_mt)
    end

    local FL = fileload.Bind(mainapi)
    mainapi.loadfile = FL.loadfile
    mainapi.load = FL.load
    mainapi.dofile = FL.dofile
    mainapi.pcall = FL.pcall

    load_shared_vim_functions(mainapi.vim, require, table_compat)
    mainapi.vim.F = load_runtime_vim_F(table_compat)
    -- Keep the local implementation until vim._with_c exists.
    mainapi.vim._with = vim_with

    return mainapi
end


return ApiBuild
