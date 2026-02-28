local ApiBuild = {}

local api = loadModule("lib.luaapi.api")
local loop = loadModule("lib.luaapi.loop")
local _jit = rawget(_G, 'jit')
local jit = _jit or loadModule("lib.luaapi.fakejit")
local on_key = loadModule("lib.luaapi.on_key")
local Runtime = loadModule("lib.excmd.runtime")
local ExMsg = loadModule("lib.excmd.exmsg")
local fn = loadModule("lib.luaapi.fn")
local require = loadModule("lib.luaapi.require")
local package = loadModule("lib.luaapi.package")
local fileload = loadModule("lib.luaapi.fileload")
local timerutils = loadModule("lib.luaapi.timerutils")
local scopes = loadModule("lib.luaapi.scopes")
local print = loadModule("lib.luaapi.print")
local strutils = loadModule("lib.luaapi.strutils")
local envvars = loadModule("lib.envvars")

local mainapi
local VIM_NIL = setmetatable({}, {
    __tostring = function()
        return "vim.NIL"
    end,
})
local VIM_CMD_ARG_MAX = 20

-- TODO: we need a print function.
-- functions print as <function>, so this knowledge is kept somewhere

local function resolve_runtime_module_path(module_name)
    local rel = module_name:gsub("%.", "/")
    local path = ccvim_path .. "/runtime/lua/" .. rel .. ".lua"
    if fs.exists(path) then
        return path
    end
    local init_module_path = ccvim_path .. "/runtime/lua/" .. rel .. "/init.lua"
    if fs.exists(init_module_path) then
        return init_module_path
    end
    return nil
end

local function load_runtime_module_by_path(lua_loader, module_name, ...)
    local path = resolve_runtime_module_path(module_name)
    if not path then
        error("module '" .. tostring(module_name) .. "' not found in runtime", 0)
    end
    local loaded = lua_loader.LoadFile(path, ...)
    if loaded == nil then
        loaded = true
    end
    mainapi.package.loaded[module_name] = loaded
    return loaded
end

local function list_runtime_vim_underscore_modules()
    local dir = ccvim_path .. "/runtime/lua/vim"
    local modules = {}
    for _, name in ipairs(fs.list(dir)) do
        if name:sub(1, 1) == "_" and name:sub(-4) == ".lua" then
            modules[#modules + 1] = "vim." .. name:sub(1, -5)
        end
    end
    table.sort(modules)
    return modules
end

local function load_runtime_vim_init_packages(lua_loader)
    local init_path = ccvim_path .. "/runtime/lua/vim/_init_packages.lua"
    local package_loaded = mainapi.package.loaded
    if type(package_loaded) ~= "table" then
        package_loaded = {}
        mainapi.package.loaded = package_loaded
    end
    if type(mainapi.package.cpath) ~= "string" then
        mainapi.package.cpath = ""
    end
    if type(mainapi.package.path) ~= "string" then
        mainapi.package.path = ""
    end
    if type(mainapi.package.loadlib) ~= "function" then
        mainapi.package.loadlib = function()
            return nil, "package.loadlib is unavailable"
        end
    end
    if type(mainapi.package.loaders) ~= "table" then
        mainapi.package.loaders = { function() end }
    elseif #mainapi.package.loaders == 0 then
        mainapi.package.loaders[1] = function() end
    end

    local original_require = mainapi.require
    local bootstrap_require = function(module_name)
        if type(module_name) == "string" and module_name:sub(1, 4) == "vim." then
            return load_runtime_module_by_path(lua_loader, module_name, module_name)
        end
        return original_require(module_name)
    end

    local runtime_require = function(module_name)
        if type(module_name) == "string" and module_name:sub(1, 4) == "vim." then
            local ok, loaded = pcall(original_require, module_name)
            if ok then
                return loaded
            end
            return load_runtime_module_by_path(lua_loader, module_name, module_name)
        end
        return original_require(module_name)
    end

    mainapi.require = bootstrap_require
    if mainapi.vim.is_thread == nil then
        mainapi.vim.is_thread = function()
            return false
        end
    end

    local ok, load_err = pcall(function()
        local chunk, compile_err = loadfile(init_path, "t", mainapi)
        if not chunk then
            error(compile_err, 0)
        end
        chunk()
        package_loaded["vim._init_packages"] = true
    end)

    mainapi.require = runtime_require
    if not ok then
        error(load_err, 0)
    end
end

local function load_runtime_vim_underscore_modules(lua_loader)
    local unpack_fn = unpack or table.unpack
    local module_args = {
        ["vim._meta"] = { mainapi.vim.uv },
    }
    for _, module_name in ipairs(list_runtime_vim_underscore_modules()) do
        local args = module_args[module_name]
        if args then
            load_runtime_module_by_path(lua_loader, module_name, unpack_fn(args))
        else
            mainapi.require(module_name)
        end
    end
end

function ApiBuild.Build()
    if mainapi then return mainapi end

    on_key.set_namespace_allocator(api.nvim_create_namespace)

    local function vim_with_c(context, f)
        if type(context) ~= "table" then
            error("context: expected table", 2)
        end
        if type(f) ~= "function" then
            error("f: expected function", 2)
        end

        local function _pack(...)
            return { n = select("#", ...), ... }
        end

        local exec = f
        if context.win ~= nil then
            local win = context.win
            exec = function()
                return api.nvim_win_call(win, f)
            end
        elseif context.buf ~= nil then
            local buf = context.buf
            exec = function()
                return api.nvim_buf_call(buf, f)
            end
        end

        local pushed_silent = false
        local pushed_unsilent = false
        local prev_eventignore = nil

        if context.silent == true or context.emsg_silent == true then
            ExMsg.PushSilent({ skip_errors = context.emsg_silent == true })
            pushed_silent = true
        end

        if context.unsilent == true then
            ExMsg.PushUnsilent()
            pushed_unsilent = true
        end

        if context.noautocmd == true then
            prev_eventignore = mainapi.vim.go.eventignore
            mainapi.vim.go.eventignore = "all"
        end

        local rv = _pack(pcall(exec))

        if context.noautocmd == true then
            mainapi.vim.go.eventignore = prev_eventignore
        end
        if pushed_unsilent then
            ExMsg.PopSilent()
        end
        if pushed_silent then
            ExMsg.PopSilent()
        end

        if not rv[1] then
            error(rv[2], 0)
        end
        local unpack_fn = unpack or table.unpack
        return unpack_fn(rv, 2, rv.n)
    end

    local LuaLoader

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

    local function vim_call(func, ...)
        local name = tostring(func)
        if select("#", ...) == 0 then
            return fn._call(name)
        end
        return fn._call(name, ...)
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

    local os_compat = setmetatable({
        getenv = envvars.get,
    }, { __index = os })

    mainapi = {
        vim = {
            api = api,
            loop = loop,
            uv = loop,
            cmd = cmd_proxy,
            g = scopes.g,
            v = scopes.v,
            b = scopes.b,
            w = scopes.w,
            t = scopes.t,
            NIL = VIM_NIL,
            deprecate = function() end,
            schedule = timerutils.schedule,
            wait = timerutils.wait,
            in_fast_event = timerutils.in_fast_event,
            inspect = print.inspect,
            regex = strutils.regex,
            _with_c = vim_with_c,
            call = vim_call,
            on_key = on_key.on_key,
            _on_key = on_key.dispatch,
        },
        jit = jit,
        require = require,
        package = package,
        table = table_compat,
        unpack = unpack or table.unpack,
        os = os_compat,

        -- DEBUG
        LOG_DEBUG = LOG_DEBUG,
        LOG_ERROR = LOG_ERROR,
        _log_caller = _log_caller,
    }

    setmetatable(mainapi, {
        __index = _G
    })
    mainapi._G = mainapi

    mainapi.vim._empty_dict_mt = {}
    mainapi.vim.empty_dict = function()
        return setmetatable({}, mainapi.vim._empty_dict_mt)
    end

    local FL = fileload.Bind(mainapi)
    mainapi.loadfile = FL.loadfile
    mainapi.load = FL.load
    mainapi.dofile = FL.dofile
    mainapi.pcall = FL.pcall

    LuaLoader = loadModule("lib.lualoader")
    mainapi.vim._str_utfindex = strutils._str_utfindex
    mainapi.vim._str_byteindex = strutils._str_byteindex
    load_runtime_vim_init_packages(LuaLoader)
    load_runtime_vim_underscore_modules(LuaLoader)
    mainapi.vim.cmd = cmd_proxy
    mainapi.vim.g = scopes.g
    mainapi.vim.v = scopes.v
    mainapi.vim.b = scopes.b
    mainapi.vim.w = scopes.w
    mainapi.vim.t = scopes.t
    mainapi.vim.schedule = timerutils.schedule
    mainapi.vim.wait = timerutils.wait
    mainapi.vim.in_fast_event = timerutils.in_fast_event
    mainapi.vim.regex = strutils.regex
    mainapi.vim._with_c = vim_with_c
    mainapi.vim.on_key = on_key.on_key
    mainapi.vim._on_key = on_key.dispatch

    return mainapi
end


return ApiBuild
