local Completion = {}

local Commands = loadModule("lib.excmd.commands")
local Backend = loadModule("lib.backend")
local Filesystem = loadModule("lib.filesystem")
local VimFs = loadModule("lib.luaapi.fs")
local Options = loadModule("lib.options")
local RuntimePath = loadModule("lib.runtimepath")
local command_names, file_names, path_names, runtime_names, package_names, tag_values
local RUNTIME_EXTENSIONS, COMPLETERS
local Args, Autocmd, EnvVars, Error, Highlight, Menu, Runtime, Scopes

local STATIC_COMPLETIONS = {
    behave = { "mswin", "xterm" },
    breakpoint = { "expr", "file", "func", "here" },
    history = { "/", ":", "=", ">", "?", "@", "all", "cmd", "debug", "expr", "input", "search" },
    mapclear = { "<buffer>" },
    mapping = { "<buffer>", "<expr>", "<nowait>", "<script>", "<silent>", "<special>", "<unique>" },
    messages = { "clear" },
    sign = { "define", "jump", "list", "place", "undefine", "unplace" },
    syntime = { "clear", "off", "on", "report" },
}

local SYNTAX_COMMANDS = {
    "case", "clear", "cluster", "conceal", "enable", "foldlevel", "include", "iskeyword",
    "keyword", "list", "manual", "match", "off", "on", "region", "reset", "spell", "sync",
}

local HIGHLIGHT_COMMANDS = { "clear", "default", "link" }

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
    Scopes = Scopes or loadModule("lib.luaapi.scopes")
    local out = sorted_keys(Scopes._g)
    local vvars = sorted_keys(Scopes._v, "v:")
    for i = 1, #vvars do out[#out + 1] = vvars[i] end
    local bvars = Scopes._b_by_buf[windows[curwin].buffer.bufnr]
    for key in pairs(bvars or {}) do out[#out + 1] = "b:" .. tostring(key) end
    return out
end

local function function_values(context)
    Runtime = Runtime or loadModule("lib.excmd.runtime")
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
    Runtime = Runtime or loadModule("lib.excmd.runtime")
    local out = {}
    for _, info in ipairs(Runtime.GetScriptInfo()) do out[#out + 1] = info.name end
    return out
end

local function environment_values()
    EnvVars = EnvVars or loadModule("lib.envvars")
    return sorted_keys(EnvVars.snapshot())
end

local function package_values()
    return words(package_names(""))
end

local function expression_values(context)
    local out = function_values(context)
    for _, value in ipairs(variable_values()) do out[#out + 1] = value end
    return out
end

local function lua_values()
    local out = sorted_keys(_G)
    for key in pairs(vim or {}) do out[#out + 1] = "vim." .. tostring(key) end
    return out
end

local function menu_values()
    Runtime = Runtime or loadModule("lib.excmd.runtime")
    Menu = Menu or loadModule("lib.menu")
    local out = {}
    for _, entry in ipairs(Menu.entries(Runtime.PrepareApiState(), "", nil)) do
        out[#out + 1] = entry.path
    end
    return out
end

local PROVIDERS = {}

local function register(names, provider)
    for _, name in ipairs(names) do PROVIDERS[name] = provider end
end

for name, values in pairs(STATIC_COMPLETIONS) do
    local items = values
    PROVIDERS[name] = function() return copy_values(items) end
end

register({ "arglist" }, function()
    Args = Args or loadModule("lib.args")
    return Args.list()
end)
register({ "buffer" }, function() return buffer_values(false) end)
register({ "diff_buffer" }, function() return buffer_values(true) end)
register({ "augroup" }, function()
    Autocmd = Autocmd or loadModule("lib.autocmd")
    return Autocmd.ListAugroups()
end)
register({ "event" }, function()
    Autocmd = Autocmd or loadModule("lib.autocmd")
    return Autocmd.ListEvents()
end)
register({ "color" }, function() return runtime_values("colors", { ccvim = true, lua = true, vim = true }) end)
register({ "command" }, function(context) return command_values(context.user_commands) end)
register({ "compiler" }, function() return runtime_values("compiler", RUNTIME_EXTENSIONS) end)
register({ "filetype", "syntax" }, function() return runtime_values("syntax", RUNTIME_EXTENSIONS) end)
register({ "keymap" }, function() return runtime_values("keymap", RUNTIME_EXTENSIONS) end)
register({ "packadd" }, package_values)
register({ "runtime" }, function(context) return words(COMPLETERS.runtime(context.pattern)) end)
register({ "file" }, function(context) return words(file_names(context.pattern)) end)
register({ "file_in_path" }, function(context) return path_names(context.pattern, "path", false) end)
register({ "dir" }, function(context)
    local out = words(file_names(context.pattern))
    local dirs = {}
    for i = 1, #out do if out[i]:sub(-1) == "/" then dirs[#dirs + 1] = out[i] end end
    return dirs
end)
register({ "dir_in_path" }, function(context) return path_names(context.pattern, "cdpath", true) end)
register({ "option" }, function() return copy_values(Options.names) end)
register({ "highlight" }, function()
    Highlight = Highlight or loadModule("lib.highlight")
    return Highlight.ListNames()
end)
register({ "environment" }, environment_values)
register({ "function" }, function(context) return function_values(context) end)
register({ "var" }, variable_values)
register({ "expression" }, expression_values)
register({ "lua" }, lua_values)
register({ "help" }, help_values)
register({ "scriptnames" }, script_values)
register({ "menu" }, menu_values)
register({ "shellcmd" }, function() return Backend.list_commands() end)
register({ "locale" }, function() return Backend.list_locales() end)
register({ "tag", "tag_listfiles" }, function() return tag_values() end)
register({ "user" }, function() return Backend.list_users() end)

PROVIDERS.cmdline = function(context)
    return words(Completion.get(context.pattern, context.user_commands, context))
end

PROVIDERS.shellcmdline = function(context)
    local before = context.pattern:match("^(.*)%s+[^%s]*$")
    if before then return words(file_names(context.pattern:match("([^%s]*)$") or "")) end
    return Backend.list_commands()
end

local function combine(...)
    local out = {}
    for i = 1, select("#", ...) do
        local values = select(i, ...)
        for j = 1, #values do out[#out + 1] = values[j] end
    end
    return out
end

local function words_before_token(arg, token)
    local prefix = arg:sub(1, #arg - #token)
    local out = {}
    for word in prefix:gmatch("%S+") do out[#out + 1] = word end
    return out
end

local function is_augroup(name)
    Autocmd = Autocmd or loadModule("lib.autocmd")
    for _, value in ipairs(Autocmd.ListAugroups()) do
        if value == name then return true end
    end
    return false
end

local COMMAND_COMPLETERS = {
    syntax = function(arg, token, context)
        local before = words_before_token(arg, token)
        if #before == 0 then return filter_values(SYNTAX_COMMANDS, token) end
        if before[1] == "case" and #before == 1 then
            return filter_values({ "ignore", "match" }, token)
        end
        if before[1] == "include" and #before == 1 then
            return Completion.for_type(token, "file", false, context)
        end
        return {}
    end,
    highlight = function(arg, token, context)
        local before = words_before_token(arg, token)
        if #before == 0 then
            return filter_values(combine(HIGHLIGHT_COMMANDS, PROVIDERS.highlight(context)), token)
        end
        if before[1] == "default" and #before == 1 then
            return Completion.for_type(token, "highlight", false, context)
        end
        if before[1] == "clear" and #before == 1 then
            return Completion.for_type(token, "highlight", false, context)
        end
        if before[1] == "link" and (#before == 1 or #before == 2) then
            return Completion.for_type(token, "highlight", false, context)
        end
        return {}
    end,
    autocmd = function(arg, token, context)
        local before = words_before_token(arg, token)
        if #before == 0 then
            return filter_values(combine(PROVIDERS.augroup(context), PROVIDERS.event(context)), token)
        end
        if #before == 1 and is_augroup(before[1]) then
            return Completion.for_type(token, "event", false, context)
        end
        local command_index = is_augroup(before[1]) and 4 or 3
        if #before >= command_index - 1 then
            return Completion.for_type(token, "command", false, context)
        end
        return {}
    end,
}

local function doautocmd_completion(arg, token, context)
    local before = words_before_token(arg, token)
    if #before == 0 then
        return filter_values(combine(PROVIDERS.augroup(context), PROVIDERS.event(context)), token)
    end
    if #before == 1 and is_augroup(before[1]) then
        return Completion.for_type(token, "event", false, context)
    end
    return Completion.for_type(token, "file", false, context)
end

COMMAND_COMPLETERS.doautocmd = doautocmd_completion
COMMAND_COMPLETERS.doautoall = doautocmd_completion

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

local function custom_spec(value)
    local name = value:match("^customlist,(.+)$")
    if name then return "customlist", name end
    name = value:match("^custom,(.+)$")
    if name then return "custom", name end
end

function Completion.for_type(pattern, completion_type, filtered, context)
    pattern = tostring(pattern or "")
    completion_type = tostring(completion_type or "")
    context = context or {}
    context.pattern = pattern

    local custom_kind, custom_function = custom_spec(completion_type)
    local values
    if custom_kind then
        if type(context.call_function) ~= "function" then return {} end
        local result = context.call_function(custom_function, pattern, context.cmdline or "", context.cursorpos or 0)
        if custom_kind == "custom" then
            values = {}
            for line in tostring(result or ""):gmatch("[^\r\n]+") do values[#values + 1] = line end
        else
            values = type(result) == "table" and result or {}
        end
    else
        if not PROVIDERS[completion_type] then
            Error = Error or loadModule("lib.error")
            error(Error(475, completion_type))
        end
        values = PROVIDERS[completion_type](context)
    end

    if not custom_kind and completion_type ~= "cmdline" and completion_type ~= "shellcmdline" then
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

local function comma_values(value)
    local out, part = {}, {}
    local text = tostring(value or "")
    local i = 1
    while i <= #text do
        local ch = text:sub(i, i)
        if ch == "\\" and i < #text then
            part[#part + 1] = text:sub(i + 1, i + 1)
            i = i + 2
        elseif ch == "," then
            out[#out + 1] = table.concat(part)
            part = {}
            i = i + 1
        else
            part[#part + 1] = ch
            i = i + 1
        end
    end
    out[#out + 1] = table.concat(part)
    return out
end

path_names = function(prefix, option, dirs_only)
    local out, seen = {}, {}
    local win = windows[curwin]
    for _, base in ipairs(comma_values(Options.get(option, win, win.buffer))) do
        base = base == "" and "." or base
        local root = VimFs.editor_abspath(base)
        for _, match in ipairs(Filesystem.ExpandWildcards(root .. "/" .. prefix .. "*")) do
            local is_dir = fs.isDir(match)
            if is_dir or not dirs_only then
                local name = match:sub(#root + 2)
                if is_dir then name = name .. "/" end
                name = name:gsub("([\\ ])", "\\%1")
                if not seen[name] then
                    seen[name] = true
                    out[#out + 1] = name
                end
            end
        end
    end
    table.sort(out)
    return out
end

local function add_tag_file(paths, seen, path)
    path = VimFs.editor_abspath(path)
    if fs.exists(path) and not fs.isDir(path) and not seen[path] then
        seen[path] = true
        paths[#paths + 1] = path
    end
end

local function tag_files()
    local paths, seen = {}, {}
    local win = windows[curwin]
    for _, spec in ipairs(comma_values(Options.get("tags", win, win.buffer))) do
        local upward = spec:sub(-1) == ";"
        if upward then spec = spec:sub(1, -2) end
        spec = spec == "" and "tags" or spec
        if upward then
            local dir = VimFs.editor_abspath(".")
            while true do
                add_tag_file(paths, seen, dir .. "/" .. spec:gsub("^%./", ""))
                if dir == "/" then break end
                local parent = dir:match("^(.*)/[^/]+$")
                if not parent then break end
                if parent == "" then parent = "/" end
                if parent == dir then break end
                dir = parent
            end
        else
            add_tag_file(paths, seen, spec)
        end
    end
    return paths
end

tag_values = function()
    local out, seen = {}, {}
    for _, path in ipairs(tag_files()) do
        local file = fs.open(path, "r")
        if file then
            while true do
                local line = file.readLine()
                if line == nil then break end
                local tag = line:match("^([^!][^\t]*)\t")
                if tag and not seen[tag] then
                    seen[tag] = true
                    out[#out + 1] = tag
                end
            end
            file.close()
        end
    end
    table.sort(out)
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

function Completion.validate_spec(spec)
    if type(spec) == "function" then return true end
    Error = Error or loadModule("lib.error")
    if type(spec) ~= "string" then return false, Error(180, tostring(spec)) end
    if PROVIDERS[spec] then return true end
    local custom, name = custom_spec(spec)
    if custom and name ~= "" then return true end
    if spec == "custom" or spec == "customlist" then
        return false, Error(467)
    end
    return false, Error(180, spec)
end

local function user_completion(def, token, line, context)
    local complete = def and (def.complete or (def.opts and def.opts.complete))
    if not complete then return {} end
    context = context or {}
    context.cmdline = line
    context.cursorpos = #line
    if type(complete) == "function" then
        local callback = complete
        context.call_function = function(_, ...)
            return callback(...)
        end
        complete = "customlist,__ccvim_callback"
    end
    if type(complete) ~= "string" then return {} end
    return Completion.for_type(token, complete, false, context)
end

function Completion.get(line, user_commands, context)
    line = tostring(line or "")
    context = context or {}
    context.user_commands = user_commands or context.user_commands or {}
    local body = line:sub(1, 1) == ":" and line:sub(2) or line
    local shell = body:match("^%s*!%s*(.*)$")
    if shell then
        local token = shell:match("([^%s]*)$") or ""
        local start = #line - #token + 1
        local kind = shell:sub(1, #shell - #token):find("%S") and "file" or "shellcmd"
        local values = Completion.for_type(token, kind, false, context)
        local items = {}
        for i = 1, #values do items[#items + 1] = { word = values[i] } end
        return items, start
    end
    local command, gap, arg = body:match("^%s*(%S*)(%s*)(.*)$")
    command, gap, arg = command or "", gap or "", arg or ""
    if gap == "" then
        return command_names(command, context.user_commands), 2
    end

    local token = arg:match("([^%s]*)$") or ""
    local start = #line - #token + 1
    local canonical = Commands.resolve_dispatch_name(command) or command:lower()
    local user_def = context.user_commands[command:lower()]
    if user_def then
        local values = user_completion(user_def, token, body, context)
        local items = {}
        for i = 1, #values do items[#items + 1] = { word = values[i] } end
        return items, start
    end
    local spec = Commands.get_spec(canonical)
    if spec and spec.wrapper then
        local nested, nested_start = Completion.get(arg, context.user_commands, context)
        return nested, #line - #arg + nested_start
    end
    local completion_type = spec and spec.complete
    context.cmdline = body
    context.cursorpos = #body
    local command_completer = COMMAND_COMPLETERS[canonical]
    local values
    if command_completer then
        values = command_completer(arg, token, context)
    elseif completion_type then
        values = Completion.for_type(token, completion_type, false, context)
    else
        return {}, start
    end
    local items = {}
    for i = 1, #values do items[#items + 1] = { word = values[i] } end
    return items, start
end

return Completion
