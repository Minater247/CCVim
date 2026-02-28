local VimFs = {}

local EnvVars = loadModule("lib.envvars")

local function _startswith(s, prefix)
    return s:sub(1, #prefix) == prefix
end

local function _resolve_dot(path)
    local is_abs = _startswith(path, "/")
    local out = {}

    for component in path:gmatch("[^/]+") do
        if component == "." then
            -- Ignore.
        elseif component == ".." then
            if #out > 0 and out[#out] ~= ".." then
                table.remove(out)
            elseif not is_abs then
                out[#out + 1] = component
            end
        else
            out[#out + 1] = component
        end
    end

    return (is_abs and "/" or "") .. table.concat(out, "/")
end

local function _expand_home(path)
    if not _startswith(path, "~") then
        return path
    end

    local home = EnvVars.get("HOME")

    if home:sub(-1) == "/" then
        home = home:sub(1, -2)
    end

    local tail = path:sub(2)
    if home == "" then
        if tail == "" then
            return "/"
        end
        if _startswith(tail, "/") then
            return tail
        end
        return "/" .. tail
    end
    return home .. tail
end

local function _dirname(path)
    if not path:match("/") then
        return "."
    end
    if path == "/" or path:match("^/[^/]+$") then
        return "/"
    end
    if path:sub(-1) == "/" then
        return path:sub(1, #path - 1)
    end
    return path:match("^(/?.+)/")
end

--- Normalize a path per :help vim.fs.normalize() (POSIX behavior only).
--- - Expands leading "~" to $HOME.
--- - Expands "$VARS" when opts.expand_env is not false.
--- - Resolves "." and ".." path components.
--- - Preserves leading "//" (but not "///...").
---
--- @param path string
--- @param opts table|nil
--- @return string
function VimFs.normalize(path, opts)
    if type(path) ~= "string" then
        error(("path: expected string, got %s"):format(type(path)))
    end
    if opts ~= nil and type(opts) ~= "table" then
        error(("opts: expected table, got %s"):format(type(opts)))
    end
    opts = opts or {}

    if path == "" then
        return ""
    end

    path = _expand_home(path)

    if opts.expand_env == nil or opts.expand_env then
        path = path:gsub("%$([%w_]+)", function(name)
            if EnvVars.exists(name) then
                return EnvVars.get(name)
            end
            return nil
        end)
    end

    local keep_double_slash = _startswith(path, "//") and not _startswith(path, "///")

    if not opts._fast then
        path = _resolve_dot(path)
    end

    path = (keep_double_slash and "/" or "") .. path

    if path == "" then
        path = "."
    end

    return path
end

--- Concatenate path fragments into a single normalized path.
--- The first fragment may be absolute or relative, later fragments are treated
--- as relative (leading slashes are ignored).
---
--- @param ... string
--- @return string
function VimFs.joinpath(...)
    local argc = select("#", ...)
    if argc == 0 then
        return ""
    end

    local first = select(1, ...)
    if type(first) ~= "string" then
        error(("path: expected string, got %s"):format(type(first)))
    end

    first = first:gsub("\\", "/")
    local absolute = _startswith(first, "/")
    local parts = {}

    for component in first:gmatch("[^/]+") do
        parts[#parts + 1] = component
    end

    for i = 2, argc do
        local path = select(i, ...)
        if type(path) ~= "string" then
            error(("path: expected string, got %s"):format(type(path)))
        end
        path = path:gsub("\\", "/")
        path = path:gsub("^/+", "")
        for component in path:gmatch("[^/]+") do
            parts[#parts + 1] = component
        end
    end

    local joined = table.concat(parts, "/")
    if absolute then
        return "/" .. joined
    end
    return joined
end

--- Make a path absolute against the current shell directory.
--- This helper is used internally by modules that need absolute paths.
---
--- @param path string
--- @return string
function VimFs.abspath(path)
    if type(path) ~= "string" then
        error(("path: expected string, got %s"):format(type(path)))
    end

    local normalized = VimFs.normalize(path)
    if normalized == "" then
        normalized = "."
    end

    if _startswith(normalized, "/") then
        return normalized
    end

    local cwd = tostring(shell.dir() or "")
    if cwd == "" then
        cwd = "/"
    end

    if not _startswith(cwd, "/") then
        cwd = "/" .. cwd
    end
    cwd = VimFs.normalize(cwd, { expand_env = false, _fast = true })

    if normalized == "." then
        return cwd
    end
    if cwd == "/" then
        return VimFs.normalize("/" .. normalized, { expand_env = false })
    end
    return VimFs.normalize(cwd .. "/" .. normalized, { expand_env = false })
end

--- Iterate parent directories for a given path.
--- The initial value yielded is dirname(start).
---
--- @param start string
--- @return fun(_, dir: string): string?
--- @return nil
--- @return string
function VimFs.parents(start)
    if type(start) ~= "string" then
        error(("start: expected string, got %s"):format(type(start)))
    end
    return function(_, dir)
        local parent = _dirname(dir)
        if parent == dir then
            return nil
        end
        return parent
    end, nil, start
end

return VimFs
