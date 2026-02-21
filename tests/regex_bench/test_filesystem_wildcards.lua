local function norm(path)
    path = tostring(path or ""):gsub("//+", "/")
    if path == "" then return "/" end
    if path:sub(-1) == "/" and #path > 1 then
        path = path:sub(1, -2)
    end
    return path
end

local function mk_fs_tree()
    local dirs = {
        ["/"] = { "vim" },
        ["/vim"] = { "runtime" },
        ["/vim/runtime"] = { "syntax", "ftdetect" },
        ["/vim/runtime/syntax"] = { "lua.vim", "lua.lua", "python.vim", "lua" },
        ["/vim/runtime/syntax/lua"] = { "extra.vim", "more.lua" },
        ["/vim/runtime/ftdetect"] = { "a.vim", "b.lua" },
    }

    local files = {
        ["/vim/runtime/syntax/lua.vim"] = true,
        ["/vim/runtime/syntax/lua.lua"] = true,
        ["/vim/runtime/syntax/python.vim"] = true,
        ["/vim/runtime/syntax/lua/extra.vim"] = true,
        ["/vim/runtime/syntax/lua/more.lua"] = true,
        ["/vim/runtime/ftdetect/a.vim"] = true,
        ["/vim/runtime/ftdetect/b.lua"] = true,
    }

    local fs = {}
    function fs.exists(path)
        path = norm(path)
        return dirs[path] ~= nil or files[path] == true
    end
    function fs.isDir(path)
        path = norm(path)
        return dirs[path] ~= nil
    end
    function fs.list(path)
        path = norm(path)
        local entries = dirs[path]
        if not entries then return {} end
        local out = {}
        for i = 1, #entries do
            out[i] = entries[i]
        end
        return out
    end
    return fs
end

_G.fs = mk_fs_tree()

_G.LOG_DEBUG = function(...) end
_G.LOG_ERROR = function(...) end
_G.LOG_INTERNAL = function(...) end

local MODULE_CACHE = {}
function _G.loadModule(name)
    if MODULE_CACHE[name] then
        return MODULE_CACHE[name]
    end

    if name == "vim.lib.luaapi.fs" then
        local mod = {
            abspath = function(path)
                path = tostring(path or "")
                if path:sub(1, 1) ~= "/" then
                    path = "/" .. path
                end
                return norm(path)
            end,
        }
        MODULE_CACHE[name] = mod
        return mod
    end

    local path = name:gsub("%.", "/") .. ".lua"
    local env = setmetatable({
        _V = nil,
        loadModule = _G.loadModule,
    }, { __index = _G })

    local chunk, err = loadfile(path, "t", env)
    if not chunk then
        error(("loadModule failed for %s (%s)"):format(name, tostring(err)))
    end
    local mod = chunk()
    MODULE_CACHE[name] = mod
    return mod
end

local Filesystem = loadModule("lib.filesystem")

local function sort_copy(list)
    local out = {}
    for i = 1, #list do out[i] = list[i] end
    table.sort(out)
    return out
end

local function assert_list_eq(label, actual, expected)
    local a = sort_copy(actual)
    local b = sort_copy(expected)
    if #a ~= #b then
        error(("FAIL %s: length %d ~= %d"):format(label, #a, #b))
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            error(("FAIL %s: item %d mismatch (%s ~= %s)"):format(label, i, tostring(a[i]), tostring(b[i])))
        end
    end
end

assert_list_eq(
    "synload file pattern",
    Filesystem.ExpandWildcards("/vim/runtime/syntax/lua[.]{vim,lua}"),
    {
        "/vim/runtime/syntax/lua.lua",
        "/vim/runtime/syntax/lua.vim",
    }
)

assert_list_eq(
    "synload dir pattern",
    Filesystem.ExpandWildcards("/vim/runtime/syntax/lua/*.{vim,lua}"),
    {
        "/vim/runtime/syntax/lua/extra.vim",
        "/vim/runtime/syntax/lua/more.lua",
    }
)

assert_list_eq(
    "ftdetect brace pattern",
    Filesystem.ExpandWildcards("/vim/runtime/ftdetect/*.{vim,lua}"),
    {
        "/vim/runtime/ftdetect/a.vim",
        "/vim/runtime/ftdetect/b.lua",
    }
)

assert_list_eq(
    "character class pattern",
    Filesystem.ExpandWildcards("/vim/runtime/syntax/[lp]*[.]vim"),
    {
        "/vim/runtime/syntax/lua.vim",
        "/vim/runtime/syntax/python.vim",
    }
)

print("Filesystem wildcard tests: OK")
