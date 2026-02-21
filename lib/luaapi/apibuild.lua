local ApiBuild = {}

local api = loadModule("vim.lib.luaapi.api")
local loop = loadModule("vim.lib.luaapi.loop")
local _jit = rawget(_G, 'jit')
local jit = _jit or loadModule("vim.lib.luaapi.fakejit")
local opts = loadModule("vim.lib.luaapi.opts")
local on_key = loadModule("vim.lib.luaapi.on_key")
local Runtime = loadModule("vim.lib.excmd.runtime")
local fn = loadModule("vim.lib.luaapi.fn")
local defer_fn = loadModule("vim.lib.luaapi.deferfn")
local split = loadModule("vim.lib.luaapi.split")
local require = loadModule("vim.lib.luaapi.require")
local keymap = loadModule("vim.lib.luaapi.keymap")
local package = loadModule("vim.lib.luaapi.package")
local fileload = loadModule("vim.lib.luaapi.fileload")
local opt = loadModule("vim.lib.luaapi.opt")
local tblutils = loadModule("vim.lib.luaapi.tblutils")
local timerutils = loadModule("vim.lib.luaapi.timerutils")
local log = loadModule("vim.lib.luaapi.log")
local notify = loadModule("vim.lib.luaapi.notify")
local scopes = loadModule("vim.lib.luaapi.scopes")
local print = loadModule("vim.lib.luaapi.print")
local diagnostic = loadModule("vim.lib.luaapi.diagnostic")
local env = loadModule("vim.lib.luaapi.env")
local system = loadModule("vim.lib.luaapi.system")
local strutils = loadModule("vim.lib.luaapi.strutils")
local vimfs = loadModule("vim.lib.luaapi.fs")
local F = loadModule("vim.lib.luaapi.F")
local VimRegex = loadModule("vim.lib.excmd.vim_regex")
local treesitter = loadModule("vim.lib.luaapi.treesitter")

local mainapi
-- TODO: what? is this documented? Why 20?
local VIM_CMD_ARG_MAX = 20

-- TODO: we need a print function.
-- functions print as <function>, so this knowledge is kept somewhere

function ApiBuild.Build()
    if mainapi then return mainapi end

    on_key.set_namespace_allocator(api.nvim_create_namespace)

    local function is_callable(v)
        if type(v) == "function" then
            return true
        end
        local mt = getmetatable(v)
        return mt ~= nil and type(mt.__call) == "function"
    end

    local function validate_one(name, value, validator, optional, message)
        if value == nil and optional == true then
            return
        end

        local function type_ok(expected)
            if expected == "callable" then
                return is_callable(value)
            end
            return type(value) == expected
        end

        local ok = false
        if type(validator) == "string" then
            ok = type_ok(validator)
        elseif type(validator) == "table" then
            for i = 1, #validator do
                local v = validator[i]
                if type(v) == "string" and type_ok(v) then
                    ok = true
                    break
                end
            end
        elseif type(validator) == "function" then
            local rv = validator(value)
            ok = rv and true or false
        end

        if not ok then
            local expected = message
            if not expected then
                if type(validator) == "table" then
                    expected = table.concat(validator, "|")
                else
                    expected = tostring(validator)
                end
            end
            error(("%s: expected %s, got %s"):format(tostring(name), tostring(expected), type(value)), 3)
        end
    end

    local function vim_validate(name, value, validator, optional, message)
        if validator ~= nil then
            if type(optional) == "string" and message == nil then
                message = optional
                optional = false
            end
            validate_one(name, value, validator, optional, message)
            return
        end

        -- Minimal legacy form support: vim.validate({ key = {value, validator, optional_or_msg}, ... })
        if type(name) ~= "table" then
            error("invalid arguments", 2)
        end
        for k, spec in pairs(name) do
            if type(spec) ~= "table" then
                error(("invalid validation spec for %s"):format(tostring(k)), 2)
            end
            local v = spec[1]
            local vd = spec[2]
            local opt = spec[3]
            local msg = nil
            if type(opt) == "string" then
                msg = opt
                opt = false
            end
            validate_one(k, v, vd, opt, msg)
        end
    end

    local function vim_pesc(s)
        if type(s) ~= "string" then
            error(("s: expected string, got %s"):format(type(s)), 2)
        end
        return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"))
    end

    local function vim_trim(s)
        vim_validate("s", s, "string")
        return s:match("^%s*(.*%S)") or ""
    end

    local function vim_list_extend(dst, src, start, finish)
        vim_validate("dst", dst, "table")
        vim_validate("src", src, "table")
        vim_validate("start", start, "number", true)
        vim_validate("finish", finish, "number", true)
        for i = start or 1, finish or #src do
            table.insert(dst, src[i])
        end
        return dst
    end

    local function vim_regex(re)
        local compiled, c_err = VimRegex.compile(re)
        if not compiled then
            error(c_err or ("invalid regex: " .. tostring(re)), 2)
        end

        return {
            match_str = function(_, s)
                local ss = tostring(s or "")
                local a, b = VimRegex.find_compiled(ss, compiled, true)
                if a then
                    return a - 1, b - 1
                end
                return nil
            end,
        }
    end

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
            defer_fn = defer_fn,
            split = split,
            keymap = keymap,
            opt = opt,
            tbl_extend = tblutils.extend,
            tbl_deep_extend = tblutils.deep_extend,
            schedule = timerutils.schedule,
            schedule_wrap = timerutils.schedule_wrap,
            log = log,
            notify = notify.notify,
            notify_once = notify.notify_once,
            tbl_contains = tblutils.contains,
            tbl_filter = tblutils.filter,
            tbl_isempty = tblutils.isempty,
            tbl_keys = tblutils.keys,
            tbl_map = tblutils.map,
            tbl_values = tblutils.values,
            deepcopy = tblutils.deepcopy,
            print = print.print,
            inspect = print.inspect,
            diagnostic = diagnostic,
            env = env,
            system = system,
            startswith = strutils.startswith,
            endswith = strutils.endswith,
            fs = vimfs,
            F = F,
            filetype = filetype_proxy,
            iter = iter_proxy,
            treesitter = treesitter,
            validate = vim_validate,
            trim = vim_trim,
            list_extend = vim_list_extend,
            pesc = vim_pesc,
            regex = vim_regex,
            _with = vim_with,
            on_key = on_key.on_key,
            _on_key = on_key.dispatch,
        },
        jit = jit,
        require = require,
        package = package,

        -- DEBUG
        LOG_DEBUG = LOG_DEBUG,
        LOG_ERROR = LOG_ERROR,
        _log_caller = _log_caller,
    }

    setmetatable(mainapi, {
        __index = _G
    })

    local FL = fileload.Bind(mainapi)
    mainapi.loadfile = FL.loadfile
    mainapi.load = FL.load
    mainapi.dofile = FL.dofile
    mainapi.pcall = FL.pcall

    return mainapi
end


return ApiBuild
