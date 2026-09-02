local Completion = {}

local Commands = loadModule("lib.excmd.commands")
local Filesystem = loadModule("lib.filesystem")
local VimFs = loadModule("lib.luaapi.fs")
local Options = loadModule("lib.options")
local RuntimePath = loadModule("lib.runtimepath")
local command_names, file_names, runtime_names, package_names
local RUNTIME_EXTENSIONS, COMPLETERS

local VALID_TYPES = {
    arglist = true,
    augroup = true,
    buffer = true,
    breakpoint = true,
    cmdline = true,
    color = true,
    command = true,
    compiler = true,
    diff_buffer = true,
    dir = true,
    dir_in_path = true,
    environment = true,
    event = true,
    expression = true,
    file = true,
    file_in_path = true,
    filetype = true,
    ["function"] = true,
    help = true,
    highlight = true,
    history = true,
    keymap = true,
    locale = true,
    mapclear = true,
    mapping = true,
    menu = true,
    messages = true,
    option = true,
    packadd = true,
    runtime = true,
    scriptnames = true,
    shellcmd = true,
    shellcmdline = true,
    sign = true,
    syntax = true,
    syntime = true,
    tag = true,
    tag_listfiles = true,
    user = true,
    var = true,
}

local STATIC_COMPLETIONS = {
    breakpoint = { "expr", "file", "func", "here" },
    history = { "/", ":", "=", ">", "?", "@", "all", "cmd", "debug", "expr", "input", "search" },
    mapclear = { "<buffer>" },
    mapping = { "<buffer>", "<expr>", "<nowait>", "<script>", "<silent>", "<special>", "<unique>" },
    messages = { "clear" },
    sign = { "define", "jump", "list", "place", "undefine", "unplace" },
    syntime = { "clear", "off", "on", "report" },
}

local function copy_values(values)
    local out = {}
    for i = 1, #values do out[i] = tostring(values[i]) end
    return out
end

local function sorted_keys(tbl, prefix, suffix)
    local out = {}
    for key in pairs(tbl or {}) do
        if type(key) == "string" then
            out[#out + 1] = (prefix or "") .. key .. (suffix or "")
        end
    end
    table.sort(out)
    return out
end

local function unique_sorted(values)
    local out, seen = {}, {}
    for i = 1, #values do
        local value = tostring(values[i])
        if value ~= "" and not seen[value] then
            seen[value] = true
            out[#out + 1] = value
        end
    end
    table.sort(out)
    return out
end

local function fuzzy_match(value, pattern)
    local pos = 1
    for i = 1, #pattern do
        pos = value:find(pattern:sub(i, i), pos, true)
        if not pos then return false end
        pos = pos + 1
    end
    return true
end

local function wildcard_pattern(pattern)
    local out = { "^" }
    for i = 1, #pattern do
        local c = pattern:sub(i, i)
        if c == "*" then
            out[#out + 1] = ".*"
        elseif c == "?" or c == "." then
            out[#out + 1] = "."
        elseif c:match("[%^%$%(%)%%%[%]%+%-%]]") then
            out[#out + 1] = "%" .. c
        else
            out[#out + 1] = c
        end
    end
    return table.concat(out)
end

local function filter_values(values, pattern)
    pattern = tostring(pattern or "")
    if pattern == "" then return unique_sorted(values) end

    local ignorecase = Options.get("wildignorecase") == true
    local wildoptions = tostring(Options.get("wildoptions") or "")
    local needle = ignorecase and pattern:lower() or pattern
    local lua_pattern = wildcard_pattern(needle)
    local out = {}
    for i = 1, #values do
        local value = tostring(values[i])
        local candidate = ignorecase and value:lower() or value
        local matched
        if wildoptions:find("fuzzy", 1, true) then
            matched = fuzzy_match(candidate, needle)
        else
            local ok, start = pcall(string.find, candidate, lua_pattern)
            matched = ok and start ~= nil
        end
        if matched then out[#out + 1] = value end
    end
    return unique_sorted(out)
end

local function words(items)
    local out = {}
    for i = 1, #items do out[#out + 1] = items[i].word end
    return out
end

local function command_values(user_commands)
    return words(command_names("", user_commands or {}))
end

local function runtime_values(dir, extensions)
    return words(runtime_names(dir, "", extensions))
end

local function buffer_values(diff_only)
    local out = {}
    for _, buf in pairs(buffers or {}) do
        local include = not diff_only
        if diff_only then
            for _, win in pairs(windows or {}) do
                if win.buffer == buf and win.opts and win.opts.diff then include = true end
            end
        end
        if include and type(buf.name) == "string" and buf.name ~= "" then out[#out + 1] = buf.name end
    end
    return out
end

local function variable_values()
    local Scopes = loadModule("lib.luaapi.scopes")
    local out = sorted_keys(Scopes._g)
    local vvars = sorted_keys(Scopes._v, "v:")
    for i = 1, #vvars do out[#out + 1] = vvars[i] end
    local bvars = Scopes._b_by_buf[windows[curwin].buffer.bufnr]
    for key in pairs(bvars or {}) do out[#out + 1] = "b:" .. tostring(key) end
    return out
end

local function function_values(context)
    local Runtime = loadModule("lib.excmd.runtime")
    local out = {}
    for key, value in pairs(context.builtins or {}) do
        if type(key) == "string" and type(value) == "function" and key:sub(1, 1) ~= "_" then
            out[#out + 1] = key .. "("
        end
    end
    for key in pairs(Runtime._FUNCS or {}) do out[#out + 1] = tostring(key) .. "(" end
    return out
end

local function help_values()
    local out, seen = {}, {}
    for _, root in ipairs(RuntimePath.get_search_list()) do
        local file = fs.open(root .. "/doc/tags", "r")
        if file then
            while true do
                local line = file.readLine()
                if line == nil then break end
                local tag = line:match("^([^\t]+)\t")
                if tag and not seen[tag] then out[#out + 1], seen[tag] = tag, true end
            end
            file.close()
        end
    end
    return out
end

local function script_values()
    local Runtime = loadModule("lib.excmd.runtime")
    local out = {}
    for _, info in ipairs(Runtime.GetScriptInfo()) do out[#out + 1] = info.name end
    return out
end

local function environment_values()
    return sorted_keys(loadModule("lib.envvars").snapshot())
end

local function package_values()
    return words(package_names(""))
end

local function filesystem_values(dirs_only)
    local out = words(file_names(""))
    if not dirs_only then return out end
    local dirs = {}
    for i = 1, #out do if out[i]:sub(-1) == "/" then dirs[#dirs + 1] = out[i] end end
    return dirs
end

local function values_for_type(completion_type, context)
    if STATIC_COMPLETIONS[completion_type] then return copy_values(STATIC_COMPLETIONS[completion_type]) end
    if completion_type == "command" then return command_values(context.user_commands) end
    if completion_type == "cmdline" or completion_type == "shellcmdline" then
        return words(Completion.get(context.pattern, context.user_commands))
    end
    if completion_type == "color" then return runtime_values("colors", { ccvim = true, lua = true, vim = true }) end
    if completion_type == "compiler" then return runtime_values("compiler", RUNTIME_EXTENSIONS) end
    if completion_type == "filetype" or completion_type == "syntax" then
        return runtime_values("syntax", RUNTIME_EXTENSIONS)
    end
    if completion_type == "keymap" then return runtime_values("keymap", RUNTIME_EXTENSIONS) end
    if completion_type == "packadd" then return package_values() end
    if completion_type == "runtime" then return words(COMPLETERS.runtime("")) end
    if completion_type == "file" or completion_type == "file_in_path" then return filesystem_values(false) end
    if completion_type == "dir" or completion_type == "dir_in_path" then return filesystem_values(true) end
    if completion_type == "event" then return loadModule("lib.autocmd").ListEvents() end
    if completion_type == "augroup" then return loadModule("lib.autocmd").ListAugroups() end
    if completion_type == "option" then return copy_values(Options.names) end
    if completion_type == "highlight" then return loadModule("lib.highlight").ListNames() end
    if completion_type == "environment" then return environment_values() end
    if completion_type == "buffer" then return buffer_values(false) end
    if completion_type == "diff_buffer" then return buffer_values(true) end
    if completion_type == "function" then return function_values(context) end
    if completion_type == "var" then return variable_values() end
    if completion_type == "expression" then
        local out = function_values(context)
        for _, value in ipairs(variable_values()) do out[#out + 1] = value end
        return out
    end
    if completion_type == "help" then return help_values() end
    if completion_type == "scriptnames" then return script_values() end
    if completion_type == "arglist" then return buffer_values(false) end
    return {}
end

local function ignored(value)
    local patterns = tostring(Options.get("wildignore") or "")
    if patterns == "" then return false end
    local basename = value:match("([^/]+)/?$") or value
    for pattern in patterns:gmatch("[^,]+") do
        local matcher = wildcard_pattern(pattern)
        if value:find(matcher) or basename:find(matcher) then return true end
    end
    return false
end

function Completion.for_type(pattern, completion_type, filtered, context)
    pattern = tostring(pattern or "")
    completion_type = tostring(completion_type or "")
    context = context or {}
    context.pattern = pattern

    local custom_kind, custom_function = completion_type:match("^(customlist?),(.+)$")
    local values
    if custom_kind then
        if type(context.call_function) ~= "function" then return {} end
        local result = context.call_function(custom_function, pattern, "", 0)
        if custom_kind == "custom" then
            values = {}
            for line in tostring(result or ""):gmatch("[^\r\n]+") do values[#values + 1] = line end
        else
            values = type(result) == "table" and result or {}
        end
    else
        if not VALID_TYPES[completion_type] then
            error(loadModule("lib.error")(475, completion_type))
        end
        values = values_for_type(completion_type, context)
    end

    if completion_type ~= "cmdline" and completion_type ~= "shellcmdline" then
        values = filter_values(values, pattern)
    else
        values = unique_sorted(values)
    end
    if filtered == true or filtered == 1 then
        local out = {}
        for i = 1, #values do if not ignored(values[i]) then out[#out + 1] = values[i] end end
        values = out
    end
    return values
end

local function matches(values, prefix)
    local out, low = {}, prefix:lower()
    for i = 1, #values do
        local value = tostring(values[i])
        if value:lower():sub(1, #low) == low then out[#out + 1] = { word = value } end
    end
    return out
end

command_names = function(prefix, user_commands)
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

file_names = function(prefix)
    local expanded = Filesystem.ExpandWildcards(prefix .. "*")
    local out = {}
    for i = 1, #expanded do
        local path = relative_path(expanded[i])
        if fs.isDir(expanded[i]) then path = path .. "/" end
        out[#out + 1] = { word = path:gsub("([\\ ])", "\\%1") }
    end
    return out
end

runtime_names = function(dir, prefix, extensions)
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

package_names = function(prefix)
    local names = {}
    for _, path in ipairs(RuntimePath.list_packages("opt")) do
        names[#names + 1] = path:match("([^/]+)$")
    end
    table.sort(names)
    return matches(names, prefix)
end

RUNTIME_EXTENSIONS = { lua = true, vim = true }
COMPLETERS = {
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
