-- Filter OSC terminal probes from test output.
do
    local function is_terminal_probe_chunk(s)
        s = tostring(s or "")
        return s:find("\27]11;?\7", 1, true) ~= nil
            or s:find("\27[0m\27[48;2;", 1, true) ~= nil
    end

    local real_io = io
    local stdout_proxy = setmetatable({}, { __index = real_io.stdout })
    function stdout_proxy:write(...)
        for i = 1, select("#", ...) do
            if is_terminal_probe_chunk(select(i, ...)) then
                return true
            end
        end
        return real_io.stdout:write(...)
    end

    local io_proxy = setmetatable({ stdout = stdout_proxy }, { __index = real_io })
    function io_proxy.write(...)
        for i = 1, select("#", ...) do
            if is_terminal_probe_chunk(select(i, ...)) then
                return true
            end
        end
        return real_io.write(...)
    end

    io = io_proxy -- luacheck: globals io
end

local function dirname(path)
    return (tostring(path or ""):match("^(.*)/[^/]+$")) or "."
end

local function normalize_abs(path)
    path = tostring(path or ""):gsub("\\", "/")
    if path == "" then
        return "/"
    end
    local parts = {}
    for seg in path:gmatch("[^/]+") do
        if seg == ".." then
            if #parts > 0 then
                table.remove(parts)
            end
        elseif seg ~= "." and seg ~= "" then
            parts[#parts + 1] = seg
        end
    end
    return "/" .. table.concat(parts, "/")
end

local function cwd()
    local handle = io.popen("pwd")
    if not handle then
        return "."
    end
    local out = handle:read("*l")
    handle:close()
    return normalize_abs(out or ".")
end

local function make_absolute(path)
    path = tostring(path or "")
    if path:sub(1, 1) == "/" then
        return normalize_abs(path)
    end
    local base = cwd()
    if base:sub(-1) == "/" then
        return normalize_abs(base .. path)
    end
    return normalize_abs(base .. "/" .. path)
end

local function append_lua_path(prefix)
    package.path = prefix .. "/?.lua;" .. prefix .. "/?/init.lua;" .. package.path
end

local function file_exists(path)
    local handle = io.open(path, "rb")
    if not handle then
        return false
    end
    handle:close()
    return true
end

local function package_searchpath(module_name, search_path)
    local module_path = tostring(module_name or ""):gsub("%.", "/")
    local errors = {}

    for template in tostring(search_path or ""):gmatch("[^;]+") do
        local candidate = template:gsub("%?", module_path)
        if file_exists(candidate) then
            return candidate
        end
        errors[#errors + 1] = "\n\tno file '" .. candidate .. "'"
    end

    return nil, table.concat(errors)
end

local function install_test_module_alias()
    local searchers = rawget(package, "searchers") or rawget(package, "loaders")
    if type(searchers) ~= "table" then
        return
    end

    local alias_prefix = "vim.tests."
    local target_prefix = "tests."

    local function alias_searcher(module_name)
        if module_name:sub(1, #alias_prefix) ~= alias_prefix then
            return nil
        end

        local alias_name = target_prefix .. module_name:sub(#alias_prefix + 1)
        local file_path, search_err = package_searchpath(alias_name, package.path)
        if not file_path then
            return nil, search_err
        end

        local chunk, load_err = loadfile(file_path)
        if not chunk then
            error(load_err, 0)
        end
        return chunk, file_path
    end

    table.insert(searchers, 1, alias_searcher)
end

local function split_abs(path)
    local out = {}
    for seg in path:gmatch("[^/]+") do
        out[#out + 1] = seg
    end
    return out
end

local function relpath(from_abs, to_abs)
    from_abs = normalize_abs(from_abs)
    to_abs = normalize_abs(to_abs)
    local from_parts = split_abs(from_abs)
    local to_parts = split_abs(to_abs)
    local i = 1
    while i <= #from_parts and i <= #to_parts and from_parts[i] == to_parts[i] do
        i = i + 1
    end
    local parts = {}
    for _ = i, #from_parts do
        parts[#parts + 1] = ".."
    end
    for j = i, #to_parts do
        parts[#parts + 1] = to_parts[j]
    end
    if #parts == 0 then
        return "."
    end
    return table.concat(parts, "/")
end

local source = debug.getinfo(1, "S").source
local script_path = (arg and arg[0]) or ""
if script_path == "" and type(source) == "string" and source:sub(1, 1) == "@" then
    script_path = source:sub(2)
end

local script_dir = dirname(make_absolute(script_path))
local ccvim_root = dirname(script_dir)
local ccvim_parent = dirname(ccvim_root)

-- Support both `vim.tests.*` and `tests.*` module prefixes from any cwd.
append_lua_path(ccvim_parent)
append_lua_path(ccvim_root)
install_test_module_alias()

_G.__CCVIM_TEST_ROOT = relpath(cwd(), ccvim_root)

local Runner = require("vim.tests.framework.runner")
Runner.run(Runner.discover(ccvim_root .. "/tests/suites"))
