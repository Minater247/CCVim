local ApiBuild = {}

local api = loadModule("lib.luaapi.api")
local loop = loadModule("lib.luaapi.loop")
local _jit = rawget(_G, 'jit')
local jit = _jit or loadModule("lib.luaapi.fakejit")
local fakeffi = loadModule("lib.luaapi.fakeffi")
local on_key = loadModule("lib.luaapi.on_key")
local Runtime = loadModule("lib.excmd.runtime")
local ExMsg = loadModule("lib.excmd.exmsg")
local fn = loadModule("lib.luaapi.fn")
local require = loadModule("lib.luaapi.require")
local package = loadModule("lib.luaapi.package")
local fileload = loadModule("lib.luaapi.fileload")
local fakeuserdata = loadModule("lib.luaapi.fakeuserdata")
local timerutils = loadModule("lib.luaapi.timerutils")
local scopes = loadModule("lib.luaapi.scopes")
local print = loadModule("lib.luaapi.print")
local strutils = loadModule("lib.luaapi.strutils")
local envvars = loadModule("lib.envvars")
local lpeg = loadModule("lib.luaapi.lpeg")
local treesitter = loadModule("lib.luaapi.treesitter")
local Json = loadModule("lib.luaapi.json")
local Error = loadModule("lib.error")

local bit = rawget(_G, "bit")
if not bit then
    local bit32lib = rawget(_G, "bit32")
    if bit32lib then
        local function tobit(x)
            x = tonumber(x) or 0
            x = x % 0x100000000
            if x >= 0x80000000 then
                return x - 0x100000000
            end
            return x
        end

        local function tohex(x, n)
            local width = math.abs(tonumber(n) or 8)
            if width < 1 then
                width = 1
            end
            local modulus = 16 ^ width
            local value = (tonumber(x) or 0) % modulus
            local s = string.format("%0" .. tostring(width) .. "x", value)
            if (tonumber(n) or 8) < 0 then
                s = string.upper(s)
            end
            return s
        end

        bit = {
            band = bit32lib.band,
            bor = bit32lib.bor,
            bxor = bit32lib.bxor,
            bnot = bit32lib.bnot,
            lshift = bit32lib.lshift,
            rshift = bit32lib.rshift,
            arshift = bit32lib.arshift or bit32lib.rshift,
            rol = bit32lib.lrotate,
            ror = bit32lib.rrotate,
            tobit = tobit,
            tohex = tohex,
        }
    end
end

local mainapi
local VIM_NIL = setmetatable({}, {
    __tostring = function()
        return "vim.NIL"
    end,
})
local VIM_CMD_ARG_MAX = 20
local LIB_RUNTIME_MODULES = {
    ["vim.lsp.lua"] = "lib/luaapi/lsp_lua.lua",
}

local function user_call(callable, ...)
    local result = { n = 0 }
    local function capture(...)
        result.n = select("#", ...)
        for i = 1, result.n do
            result[i] = select(i, ...)
        end
    end
    capture(pcall(callable, ...))
    if not result[1] then
        local err = result[2]
        if Error.IsError(err) then err = err:toString() end
        error(err, 0)
    end
    for i = 2, result.n do
        if Error.IsError(result[i]) then
            error(result[i]:toString(), 0)
        end
    end
    return table.unpack(result, 2, result.n)
end

local api_proxy = setmetatable({}, {
    __index = function(proxy, name)
        local value = api[name]
        if type(value) == "function" then
            value = function(...)
                return user_call(api[name], ...)
            end
        end
        rawset(proxy, name, value)
        return value
    end,
})

-- TODO: we need a print function.
-- functions print as <function>, so this knowledge is kept somewhere

local function resolve_runtime_module_path(module_name)
    local lib_path = LIB_RUNTIME_MODULES[module_name]
    if lib_path then return ccvim_path .. "/" .. lib_path end
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

local function extend_runtime_module(module_name, loaded)
    if module_name == "vim.lsp" then loaded._submodules.lua = true end
    return loaded
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
    loaded = extend_runtime_module(module_name, loaded)
    mainapi.package.loaded[module_name] = loaded
    return loaded
end

local function list_runtime_vim_underscore_modules()
    local dir = ccvim_path .. "/runtime/lua/vim"
    local modules = {}
    for _, name in ipairs(fs.list(dir)) do
        if name ~= "_meta.lua" and name:sub(1, 1) == "_" and name:sub(-4) == ".lua" then
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
                return extend_runtime_module(module_name, loaded)
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

    scopes._v.exiting = VIM_NIL
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
            state = Runtime.PrepareApiState(),
            origin = {
                kind = "lua-inline",
                api = "vim.cmd",
            },
        })
        if not ok then
            local msg = rv:toString()
            error(msg)
        end
        return rv
    end

    local function vim_call(func, ...)
        local name = tostring(func)
        if select("#", ...) == 0 then
            return user_call(fn._call, name)
        end
        return user_call(fn._call, name, ...)
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

    local function get_scoped_var(scope, handle, key)
        local h = handle or 0
        if h == 0 then
            h = (scope == "b" and windows[curwin].buffer.bufnr)
                or (scope == "w" and curwin)
                or (scope == "t" and curtp)
                or 0
        end

        if scope == "g" then
            return scopes._g[key]
        elseif scope == "v" then
            return scopes._v[key]
        elseif scope == "b" then
            return scopes.b[h][key]
        elseif scope == "w" then
            return scopes.w[h][key]
        elseif scope == "t" then
            return scopes.t[h][key]
        end
    end

    local function set_scoped_var(scope, handle, key, value)
        if value == VIM_NIL then
            value = nil
        end

        local h = handle or 0
        if h == 0 then
            h = (scope == "b" and windows[curwin].buffer.bufnr)
                or (scope == "w" and curwin)
                or (scope == "t" and curtp)
                or 0
        end

        if scope == "g" then
            scopes._g[key] = value
            return
        elseif scope == "v" then
            scopes._v[key] = value
            return
        elseif scope == "b" then
            scopes.b[h][key] = value
            return
        elseif scope == "w" then
            scopes.w[h][key] = value
            return
        elseif scope == "t" then
            scopes.t[h][key] = value
            return
        end
    end

    local os_compat = setmetatable({
        getenv = envvars.get,
    }, { __index = os })

    mainapi = {
        vim = {
            api = api_proxy,
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
            wait = function(...)
                return user_call(timerutils.wait, ...)
            end,
            in_fast_event = timerutils.in_fast_event,
            inspect = print.inspect,
            regex = strutils.regex,
            stricmp = strutils.stricmp,
            lpeg = lpeg,
            _ts_get_language_version = treesitter._ts_get_language_version,
            _ts_get_minimum_language_version = treesitter._ts_get_minimum_language_version,
            _with_c = vim_with_c,
            call = vim_call,
            on_key = on_key.on_key,
            _on_key = on_key.dispatch,
            _getvar = get_scoped_var,
            _setvar = set_scoped_var,
        },
        jit = jit,
        require = function(...)
            return user_call(require, ...)
        end,
        package = package,
        table = table_compat,
        unpack = unpack or table.unpack,
        os = os_compat,
        print = print.lua_print,
        type = fakeuserdata.type,
        next = fakeuserdata.next,
        pairs = fakeuserdata.pairs,
        ipairs = fakeuserdata.ipairs,
        rawget = fakeuserdata.rawget,
        rawset = fakeuserdata.rawset,
        setmetatable = fakeuserdata.setmetatable,

        -- DEBUG
        LOG_DEBUG = LOG_DEBUG,
        LOG_ERROR = LOG_ERROR,
        _log_caller = _log_caller,
    }

    setmetatable(mainapi, {
        __index = _G
    })
    mainapi._G = mainapi
    mainapi.bit = bit

    mainapi.vim._empty_dict_mt = {}
    mainapi.vim.empty_dict = function()
        return setmetatable({}, mainapi.vim._empty_dict_mt)
    end
    mainapi.vim.json = {
        decode = function(source, opts)
            opts = opts or {}
            opts.empty_dict_mt = mainapi.vim._empty_dict_mt
            opts.null_value = VIM_NIL
            local value, err = Json.decode(source, opts)
            if err then error(err, 2) end
            return value
        end,
        encode = function(value, opts)
            opts = opts or {}
            opts.empty_dict_mt = mainapi.vim._empty_dict_mt
            opts.null_value = VIM_NIL
            return Json.encode(value, opts)
        end,
    }

    local FL = fileload.Bind(mainapi)
    mainapi.loadfile = FL.loadfile
    mainapi.load = FL.load
    mainapi.dofile = FL.dofile
    mainapi.pcall = FL.pcall

    if type(mainapi.package.loaded) ~= "table" then
        mainapi.package.loaded = {}
    end

    mainapi.package.loaded.bit = bit
    mainapi.package.loaded.lpeg = lpeg
    if not _jit then
        mainapi.package.loaded.ffi = fakeffi
    end

    LuaLoader = loadModule("lib.lualoader")
    mainapi.vim._str_utfindex = strutils._str_utfindex
    mainapi.vim._str_byteindex = strutils._str_byteindex
    load_runtime_vim_init_packages(LuaLoader)
    load_runtime_vim_underscore_modules(LuaLoader)
    if not _jit then
        local runtime_loader = mainapi.vim.loader
        if type(runtime_loader) == "table" and type(runtime_loader.enable) == "function" then
            local upstream_enable = runtime_loader.enable
            runtime_loader.enable = function(enable)
                if enable == false then
                    return upstream_enable(false)
                end
                return nil
            end
        end
    end
    mainapi.vim.cmd = cmd_proxy
    mainapi.vim.g = scopes.g
    mainapi.vim.v = scopes.v
    mainapi.vim.b = scopes.b
    mainapi.vim.w = scopes.w
    mainapi.vim.t = scopes.t
    mainapi.vim.schedule = timerutils.schedule
    mainapi.vim.wait = function(...)
        return user_call(timerutils.wait, ...)
    end
    mainapi.vim.in_fast_event = timerutils.in_fast_event
    mainapi.vim.regex = strutils.regex
    mainapi.vim.lpeg = lpeg
    mainapi.vim._with_c = vim_with_c
    mainapi.vim.on_key = on_key.on_key
    mainapi.vim._on_key = on_key.dispatch

    return mainapi
end


return ApiBuild
