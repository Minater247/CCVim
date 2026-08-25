local Completion = {}

local Commands = loadModule("lib.excmd.commands")
local Filesystem = loadModule("lib.filesystem")
local VimFs = loadModule("lib.luaapi.fs")
local Options = loadModule("lib.options")
local RuntimePath = loadModule("lib.runtimepath")

local function matches(values, prefix)
    local out, low = {}, prefix:lower()
    for i = 1, #values do
        local value = tostring(values[i])
        if value:lower():sub(1, #low) == low then out[#out + 1] = { word = value } end
    end
    return out
end

local function command_names(prefix, user_commands)
    if next(user_commands) == nil then return matches(Commands.names, prefix) end
    local names, seen = {}, {}
    for i = 1, #Commands.names do
        local name = Commands.names[i]
        names[#names + 1], seen[name:lower()] = name, true
    end
    for name, def in pairs(user_commands) do
        name = def.name or name
        if not seen[name:lower()] then names[#names + 1] = name end
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    return matches(names, prefix)
end

local function relative_path(path)
    local cwd = VimFs.editor_cwd()
    if path:sub(1, #cwd + 1) == cwd .. "/" then return path:sub(#cwd + 2) end
    return path
end

local function file_names(prefix)
    local expanded = Filesystem.ExpandWildcards(prefix .. "*")
    local out = {}
    for i = 1, #expanded do
        local path = relative_path(expanded[i])
        if fs.isDir(expanded[i]) then path = path .. "/" end
        out[#out + 1] = { word = path:gsub("([\\ ])", "\\%1") }
    end
    return out
end

local function runtime_names(dir, prefix, extensions)
    local names, seen = {}, {}
    for _, root in ipairs(RuntimePath.get_search_list()) do
        for _, path in ipairs(Filesystem.ExpandWildcards(root .. "/" .. dir .. "/*")) do
            local name, ext = path:match("([^/]+)%.([^.]+)$")
            if name and extensions[ext] and not seen[name] then
                names[#names + 1], seen[name] = name, true
            end
        end
    end
    table.sort(names)
    return matches(names, prefix)
end

local function package_names(prefix)
    local names = {}
    for _, path in ipairs(RuntimePath.list_packages("opt")) do
        names[#names + 1] = path:match("([^/]+)$")
    end
    table.sort(names)
    return matches(names, prefix)
end

local RUNTIME_EXTENSIONS = { lua = true, vim = true }
local COMPLETERS = {
    color = function(prefix)
        return runtime_names("colors", prefix, { ccvim = true, lua = true, vim = true })
    end,
    file = file_names,
    filetype = function(prefix) return runtime_names("syntax", prefix, RUNTIME_EXTENSIONS) end,
    option = function(prefix) return matches(Options.names, prefix) end,
    package = package_names,
    runtime = function(prefix)
        local out = {}
        for _, root in ipairs(RuntimePath.get_search_list()) do
            for _, path in ipairs(Filesystem.ExpandWildcards(root .. "/" .. prefix .. "*")) do
                out[#out + 1] = { word = path:sub(#root + 2) }
            end
        end
        return out
    end,
}

function Completion.get(line, user_commands)
    line = tostring(line or "")
    local body = line:sub(1, 1) == ":" and line:sub(2) or line
    local command, gap, arg = body:match("^%s*(%S*)(%s*)(.*)$")
    command, gap, arg = command or "", gap or "", arg or ""
    if gap == "" then
        return command_names(command, user_commands or {}), 2
    end

    local token = arg:match("([^%s]*)$") or ""
    local start = #line - #token + 1
    local canonical = Commands.resolve_dispatch_name(command) or command:lower()
    local spec = Commands.get_spec(canonical)
    local complete = spec and COMPLETERS[spec.complete]
    return complete and complete(token) or {}, start
end

return Completion
