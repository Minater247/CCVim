-- This file compares the syntax groups assigned to files by this utility and the real neovim executable.
-- It has been useful for testing, so I am including it for anyone else why wants to develop this.

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(s, prefix)
    return s:sub(1, #prefix) == prefix
end

local function split_csv(raw)
    local out = {}
    for part in tostring(raw or ""):gmatch("[^,]+") do
        local v = trim(part)
        if v ~= "" then
            out[#out + 1] = v
        end
    end
    return out
end

local function script_dir()
    local src = debug.getinfo(1, "S").source
    if starts_with(src, "@") then
        src = src:sub(2)
    end
    return src:match("^(.*)/") or "."
end

local function normalize_path(path)
    local p = tostring(path or "")
    local abs = starts_with(p, "/")
    local out = {}
    for part in p:gmatch("[^/]+") do
        if part == ".." then
            if #out > 0 then
                out[#out] = nil
            end
        elseif part ~= "." then
            out[#out + 1] = part
        end
    end
    return (abs and "/" or "") .. table.concat(out, "/")
end

local function cwd()
    local handle = io.popen("pwd", "r")
    if not handle then
        return "."
    end
    local out = handle:read("*l") or "."
    handle:close()
    return normalize_path(out)
end

local function absolute_path(path)
    local p = tostring(path or "")
    if p == "" then
        return cwd()
    end
    if starts_with(p, "/") then
        return normalize_path(p)
    end
    return normalize_path(cwd() .. "/" .. p)
end

local function dirname(path)
    local d = tostring(path or ""):match("^(.*)/[^/]*$")
    if d and d ~= "" then
        return d
    end
    return "."
end

local function join(a, b)
    if a:sub(-1) == "/" then
        return a .. b
    end
    return a .. "/" .. b
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function read_lines(path)
    local out = {}
    for line in io.lines(path) do
        out[#out + 1] = line
    end
    return out
end

local function read_logical_lines(path)
    local out = {}
    local cur = nil

    for raw in io.lines(path) do
        if raw:match("^%s*\\") then
            if cur then
                local tail = raw:gsub("^%s*\\%s*", "")
                cur = cur .. " " .. tail
            end
        else
            if cur then
                out[#out + 1] = cur
            end
            cur = raw
        end
    end

    if cur then
        out[#out + 1] = cur
    end
    return out
end

local function shell_quote(s)
    local v = tostring(s or "")
    return "'" .. v:gsub("'", "'\\''") .. "'"
end

local function sorted_keys(set)
    local out = {}
    for k in pairs(set) do
        out[#out + 1] = k
    end
    table.sort(out)
    return out
end

local function parse_line_selector(raw)
    if not raw or raw == "" then
        return nil
    end
    local picked = {}
    for _, part in ipairs(split_csv(raw)) do
        local a, b = part:match("^(%d+)%-(%d+)$")
        if a then
            local x = tonumber(a)
            local y = tonumber(b)
            if x and y then
                if x > y then x, y = y, x end
                for n = x, y do
                    picked[n] = true
                end
            end
        else
            local n = tonumber(part)
            if n then
                picked[n] = true
            end
        end
    end
    return picked
end

local function usage()
    io.write([[
Usage: lua vim/compare_highlighting.lua <file> [options]

Options:
  --ft=<filetype>          Force filetype instead of nvim detection.
  --lines=<csv-or-ranges>  Only compare selected lines (example: 7,16,21-31).
  --max-report=<n>         Max mismatched lines to print (default: 80).
  --vim9                   Include "Vim9 ..." prefixed syntax commands.
  --fail-on-diff           Exit with status 1 when differences exist.
  --help                   Show this help.

Example:
  lua tests/compare_highlighting.lua runtime/ftplugin.vim --ft=vim --lines=7,16,21,23,30,31
]])
end

local function parse_args(argv)
    local opts = {
        file = nil,
        ft = nil,
        lines = nil,
        max_report = 80,
        include_vim9 = false,
        fail_on_diff = false,
    }

    for i = 1, #argv do
        local a = tostring(argv[i])
        if a == "--help" or a == "-h" then
            usage()
            os.exit(0)
        elseif starts_with(a, "--ft=") then
            opts.ft = a:sub(6)
        elseif starts_with(a, "--lines=") then
            opts.lines = parse_line_selector(a:sub(9))
        elseif starts_with(a, "--max-report=") then
            local n = tonumber(a:sub(14))
            if n and n > 0 then
                opts.max_report = math.floor(n)
            end
        elseif a == "--vim9" then
            opts.include_vim9 = true
        elseif a == "--fail-on-diff" then
            opts.fail_on_diff = true
        elseif starts_with(a, "--") then
            error("Unknown option: " .. a)
        elseif not opts.file then
            opts.file = a
        else
            error("Unexpected argument: " .. a)
        end
    end

    if not opts.file then
        usage()
        os.exit(2)
    end

    return opts
end

local SCRIPT_DIR = absolute_path(script_dir())
local REPO_ROOT = normalize_path(join(SCRIPT_DIR, ".."))
local RUNTIME_ROOT = join(REPO_ROOT, "runtime")

local function write_nvim_probe_script(path)
    local f, err = io.open(path, "w")
    if not f then
        error("Failed to create nvim probe script: " .. tostring(err))
    end

    f:write([[
local idx = (arg[1] == "--") and 2 or 1
local target = arg[idx]
local forced_ft = arg[idx + 1] or ""

if not target or target == "" then
  io.stderr:write("missing file path\n")
  os.exit(2)
end

vim.o.swapfile = false
vim.o.modeline = false
vim.cmd("set nomore")
vim.cmd("silent edit " .. vim.fn.fnameescape(target))

if forced_ft ~= "" then
  vim.bo.filetype = forced_ft
else
  vim.cmd("filetype on")
  vim.cmd("filetype detect")
end

vim.cmd("syntax on")
if vim.bo.filetype ~= "" then
  vim.bo.syntax = vim.bo.filetype
end

io.write("FT\t" .. tostring(vim.bo.filetype or "") .. "\n")
io.write("SMC\t" .. tostring(vim.bo.synmaxcol or 3000) .. "\n")

local line_count = vim.api.nvim_buf_line_count(0)
for ln = 1, line_count do
  local text = vim.fn.getline(ln)
  local len = #text
  if len > 0 then
    local col = 1
    while col <= len do
      local id = vim.fn.synID(ln, col, 1)
      local name = vim.fn.synIDattr(id, "name")
      if name == "" then name = "Normal" end

      local j = col + 1
      while j <= len do
        local id2 = vim.fn.synID(ln, j, 1)
        local name2 = vim.fn.synIDattr(id2, "name")
        if name2 == "" then name2 = "Normal" end
        if name2 ~= name then break end
        j = j + 1
      end

      name = name:gsub("[\t\r\n]", " ")
      io.write(("S\t%d\t%d\t%d\t%s\n"):format(ln, col, j - 1, name))
      col = j
    end
  end
end

vim.cmd("qa!")
]])

    f:close()
end

local function collect_nvim_segments(path, forced_ft)
    local tmp = os.tmpname()
    write_nvim_probe_script(tmp)

    local cmd = table.concat({
        "nvim --headless -u NONE -i NONE -n -l",
        shell_quote(tmp),
        "--",
        shell_quote(path),
        shell_quote(forced_ft or ""),
        "2>&1",
    }, " ")

    local pipe = io.popen(cmd, "r")
    if not pipe then
        os.remove(tmp)
        error("Failed to start nvim")
    end

    local output = pipe:read("*a") or ""
    local ok, _, code = pipe:close()
    os.remove(tmp)

    if not ok then
        error(("nvim probe failed (exit %s)\n%s"):format(tostring(code or "?"), output))
    end

    local out = {
        filetype = "",
        synmaxcol = 3000,
        segments = {},
    }

    for line in output:gmatch("[^\n]*\n?") do
        local row = line:gsub("\n$", "")
        if starts_with(row, "FT\t") then
            out.filetype = row:sub(4)
        elseif starts_with(row, "SMC\t") then
            out.synmaxcol = tonumber(row:sub(5)) or 3000
        elseif starts_with(row, "S\t") then
            local l, s, e, g = row:match("^S\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
            if l then
                local ln = tonumber(l)
                local cs = tonumber(s)
                local ce = tonumber(e)
                out.segments[ln] = out.segments[ln] or {}
                out.segments[ln][#out.segments[ln] + 1] = {
                    s = cs,
                    e = ce,
                    group = (g ~= "" and g or "Normal"),
                }
            end
        end
    end

    if out.filetype == "" and forced_ft and forced_ft ~= "" then
        out.filetype = forced_ft
    end
    out.synmaxcol = out.synmaxcol or 3000

    return out
end

local function write_nvim_batch_probe_script(path)
    local f, err = io.open(path, "w")
    if not f then
        error("Failed to create nvim batch probe script: " .. tostring(err))
    end

    f:write([[
local first = (arg[1] == "--") and 2 or 1

vim.o.swapfile = false
vim.o.modeline = false
vim.cmd("set nomore")
vim.cmd("filetype on")
vim.cmd("syntax on")

local function scrub(text)
  return tostring(text or ""):gsub("[\t\r\n]", " ")
end

local out_idx = 1
for idx = first, #arg do
  local target = arg[idx]
  io.write(("F\t%d\t%s\n"):format(out_idx, scrub(target)))

  local ok, err = pcall(function()
    vim.cmd("silent edit " .. vim.fn.fnameescape(target))
    vim.cmd("filetype detect")
    if vim.bo.filetype ~= "" then
      vim.bo.syntax = vim.bo.filetype
    end

    io.write("FT\t" .. tostring(out_idx) .. "\t" .. scrub(vim.bo.filetype or "") .. "\n")
    io.write("SMC\t" .. tostring(out_idx) .. "\t" .. tostring(vim.bo.synmaxcol or 3000) .. "\n")

    local line_count = vim.api.nvim_buf_line_count(0)
    for ln = 1, line_count do
      local text = vim.fn.getline(ln)
      local len = #text
      if len > 0 then
        local col = 1
        while col <= len do
          local id = vim.fn.synID(ln, col, 1)
          local name = vim.fn.synIDattr(id, "name")
          if name == "" then name = "Normal" end

          local j = col + 1
          while j <= len do
            local id2 = vim.fn.synID(ln, j, 1)
            local name2 = vim.fn.synIDattr(id2, "name")
            if name2 == "" then name2 = "Normal" end
            if name2 ~= name then break end
            j = j + 1
          end

          io.write(("S\t%d\t%d\t%d\t%d\t%s\n"):format(out_idx, ln, col, j - 1, scrub(name)))
          col = j
        end
      end
    end
    vim.cmd("silent! bwipe!")
  end)

  if not ok then
    io.write(("ERR\t%d\t%s\n"):format(out_idx, scrub(err)))
    vim.cmd("silent! bwipe!")
  end

  out_idx = out_idx + 1
end

vim.cmd("qa!")
]])

    f:close()
end

local function collect_nvim_segments_many(paths)
    local tmp = os.tmpname()
    write_nvim_batch_probe_script(tmp)

    local parts = {
        "nvim --headless -u NONE -i NONE -n -l",
        shell_quote(tmp),
        "--",
    }
    for i = 1, #paths do
        parts[#parts + 1] = shell_quote(paths[i])
    end

    local pipe = io.popen(table.concat(parts, " ") .. " 2>&1", "r")
    if not pipe then
        os.remove(tmp)
        error("Failed to start nvim")
    end

    local output = pipe:read("*a") or ""
    local ok, _, code = pipe:close()
    os.remove(tmp)

    if not ok then
        error(("nvim batch probe failed (exit %s)\n%s"):format(tostring(code or "?"), output))
    end

    local out = {}
    for i = 1, #paths do
        out[paths[i]] = {
            filetype = "",
            synmaxcol = 3000,
            segments = {},
        }
    end

    for line in output:gmatch("[^\n]*\n?") do
        local row = line:gsub("\n$", "")
        if starts_with(row, "FT\t") then
            local idx, ft = row:match("^FT\t(%d+)\t(.*)$")
            idx = tonumber(idx)
            local path = idx and paths[idx]
            if path and out[path] then
                out[path].filetype = ft or ""
            end
        elseif starts_with(row, "SMC\t") then
            local idx, value = row:match("^SMC\t(%d+)\t(.*)$")
            idx = tonumber(idx)
            local path = idx and paths[idx]
            if path and out[path] then
                out[path].synmaxcol = tonumber(value) or 3000
            end
        elseif starts_with(row, "S\t") then
            local idx, l, s, e, g = row:match("^S\t(%d+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
            idx = tonumber(idx)
            local path = idx and paths[idx]
            if path and out[path] then
                local ln = tonumber(l)
                out[path].segments[ln] = out[path].segments[ln] or {}
                out[path].segments[ln][#out[path].segments[ln] + 1] = {
                    s = tonumber(s),
                    e = tonumber(e),
                    group = (g ~= "" and g or "Normal"),
                }
            end
        elseif starts_with(row, "ERR\t") then
            local idx, err = row:match("^ERR\t(%d+)\t(.*)$")
            idx = tonumber(idx)
            local path = idx and paths[idx]
            if path and out[path] then
                out[path].error = err or "nvim probe failed"
            end
        end
    end

    return out
end

local function init_lua_engine_runtime()
    local function make_colors()
        local order = {
            "white", "orange", "magenta", "lightBlue",
            "yellow", "lime", "pink", "gray",
            "lightGray", "cyan", "purple", "blue",
            "brown", "green", "red", "black",
        }
        local t = {}
        local map = {}
        for i = 1, #order do
            local bit = 2 ^ (i - 1)
            t[order[i]] = bit
            map[bit] = string.format("%x", i - 1)
        end

        function t.toBlit(bit)
            return map[bit] or "0"
        end

        function t.packRGB(r, g, b)
            return { r, g, b }
        end

        function t.unpackRGB(rgb)
            if type(rgb) == "table" then
                return rgb[1] or 0, rgb[2] or 0, rgb[3] or 0
            end
            return 0, 0, 0
        end

        return t
    end

    _G.colors = make_colors()
    _G.term = {
        getPaletteColor = function(_) return 0, 0, 0 end,
        setTextColor = function(_) end,
        setBackgroundColor = function(_) end,
    }
    _G.screen = {
        get_palette_slot = function(_) return 0, 0, 0 end,
        hl_attrs = function(_) return {} end,
        default_colors_set = function() end,
        hl_id_for = function(_) return 0 end,
        hl_group_set = function() end,
        set_palette_slot = function() end,
    }
    _G.LOG_ERROR = function() end
    _G.LOG_DEBUG = function() end
    _G.LOG_INTERNAL = function() end
    if not math.clamp then
        math.clamp = function(value, min_value, max_value)
            if value < min_value then
                return min_value
            end
            if value > max_value then
                return max_value
            end
            return value
        end
    end

    local cache = {}
    function _G.loadModule(name, opts)
        opts = opts or {}

        local cached = cache[name]
        if cached ~= nil then
            if type(cached) == "table" and cached.__ccvim_lazy_proxy and opts.immediate then
                return cached.__ccvim_materialize()
            end
            return cached
        end

        local rel = name:gsub("%.", "/") .. ".lua"
        local path = join(REPO_ROOT, rel)
        local env = setmetatable({
            _V = nil,
            loadModule = _G.loadModule,
        }, { __index = _G })

        local chunk, err = loadfile(path, "t", env)
        if not chunk then
            error(("loadModule failed for %s (%s)"):format(name, tostring(err)))
        end

        local resolved = false
        local mod
        local function materialize()
            if not resolved then
                mod = chunk()
                if mod == nil then
                    mod = true
                end
                resolved = true
                cache[name] = mod
            end
            return mod
        end

        if opts.immediate then
            return materialize()
        end

        local proxy = {
            __ccvim_lazy_proxy = true,
            __ccvim_materialize = materialize,
        }
        setmetatable(proxy, {
            __index = function(_, key)
                return materialize()[key]
            end,
            __newindex = function(_, key, value)
                materialize()[key] = value
            end,
            __call = function(_, ...)
                return materialize()(...)
            end,
            __len = function()
                return #materialize()
            end,
            __pairs = function()
                return pairs(materialize())
            end,
            __tostring = function()
                return tostring(materialize())
            end,
        })
        cache[name] = proxy
        return proxy
    end
end

local function normalize_syn_line(raw, include_vim9)
    local cmd = trim(raw)
    if cmd == "" or starts_with(cmd, "\"") then
        return nil
    end

    if cmd:match("^VimL%s+") then
        cmd = cmd:gsub("^VimL%s+", "")
    elseif cmd:match("^Vim9%s+") then
        if include_vim9 then
            cmd = cmd:gsub("^Vim9%s+", "")
        else
            return nil
        end
    elseif cmd:match("^VimFold%a*%s+") then
        cmd = cmd:gsub("^VimFold%a*%s+", "")
    end

    if cmd:match("^syntax%s+") then
        cmd = cmd:gsub("^syntax%s+", "")
    elseif cmd:match("^syn%s+") then
        cmd = cmd:gsub("^syn%s+", "")
    else
        return nil
    end

    return cmd
end

local function parse_runtime_include(raw)
    local cmd = trim(raw)
    local path = cmd:match("^runtime!?%s+(.+)$")
    if not path or path == "" then
        return nil
    end
    if path:find("[%*%?%[%]{}]") then
        return nil
    end
    return trim(path)
end

local function parse_execute_syntax_line(raw, include_vim9, vars)
    local cmd = trim(raw)
    if not (starts_with(cmd, "exe ") or starts_with(cmd, "execute ")) then
        return nil
    end

    local expr = trim(cmd:gsub("^execute?%s+", "", 1))
    local parts = {}
    local i = 1

    while i <= #expr do
        local ch = expr:sub(i, i)
        if ch:match("%s") or ch == "." then
            i = i + 1
        elseif ch == "'" or ch == "\"" then
            local j = i + 1
            while j <= #expr and expr:sub(j, j) ~= ch do
                j = j + 1
            end
            if j > #expr then
                return nil
            end
            parts[#parts + 1] = expr:sub(i + 1, j - 1)
            i = j + 1
        else
            local token = expr:match("^([%w_:]+)", i)
            if not token then
                return nil
            end
            parts[#parts + 1] = tostring(vars[token] or "")
            i = i + #token
        end
    end

    return normalize_syn_line(table.concat(parts), include_vim9)
end

local function resolve_include_path(current_file, include_file)
    local raw = trim(include_file or "")
    raw = raw:gsub("^['\"](.*)['\"]$", "%1")
    if raw == "" then return nil end

    local candidates = {}
    if starts_with(raw, "/") then
        candidates[#candidates + 1] = raw
    else
        candidates[#candidates + 1] = normalize_path(raw)
        candidates[#candidates + 1] = normalize_path(join(dirname(current_file), raw))
        candidates[#candidates + 1] = normalize_path(join(RUNTIME_ROOT, raw))
        candidates[#candidates + 1] = normalize_path(join(RUNTIME_ROOT, "syntax/" .. raw))
    end

    for i = 1, #candidates do
        local p = candidates[i]
        if file_exists(p) then
            return p
        end
    end
    return nil
end

local function load_syntax_commands(ft, opts)
    local Parser = loadModule("lib.syntax_engine.command_parser")

    local syntax_file = normalize_path(join(RUNTIME_ROOT, "syntax/" .. tostring(ft) .. ".vim"))
    if not file_exists(syntax_file) then
        return nil, ("missing syntax file: %s"):format(syntax_file)
    end

    local commands = {}
    local seen_files = {}
    local vars = {}

    local function truthy(v)
        if type(v) == "number" then
            return v ~= 0
        end
        if type(v) == "string" then
            return v ~= ""
        end
        return not not v
    end

    local function exists_var(name)
        return vars[name] ~= nil
    end

    local function parse_assignment(raw)
        local name, rhs = raw:match("^let!?%s+([%w_:]+)%s*=%s*(.+)$")
        if not name then
            return false
        end

        local v = trim(rhs)
        local quote = v:sub(1, 1)
        if (quote == "'" or quote == "\"") and v:sub(-1) == quote then
            vars[name] = v:sub(2, -2)
            return true
        end

        local num = tonumber(v)
        if num ~= nil then
            vars[name] = num
            return true
        end

        if vars[v] ~= nil then
            vars[name] = vars[v]
            return true
        end

        return false
    end

    local function normalize_condition_expr(expr)
        local out = trim(expr)
        out = out:gsub("([=!<>]=)[#?]", "%1")
        out = out:gsub("!=", "~=")
        out = out:gsub("&&", " and ")
        out = out:gsub("%|%|", " or ")
        out = out:gsub("get%s*%(%s*([%a]):%s*,%s*(['\"])(.-)%2%s*,%s*([^)]+)%)", function(scope, _, name, default)
            return ("getvar(%q, %q, %s)"):format(scope .. ":", name, default)
        end)
        out = out:gsub("exists%s*%((['\"])(.-)%1%)", function(_, name)
            return ("exists(%q)"):format(name)
        end)
        out = out:gsub("([%a_][%w_]*:[%w_:#]+)", function(name)
            return ("var(%q)"):format(name)
        end)

        local chars = {}
        local i = 1
        while i <= #out do
            local ch = out:sub(i, i)
            if ch == "!" then
                local nxt = out:sub(i + 1, i + 1)
                if nxt == "=" or nxt == "~" then
                    chars[#chars + 1] = ch
                else
                    chars[#chars + 1] = " not "
                end
            else
                chars[#chars + 1] = ch
            end
            i = i + 1
        end
        return table.concat(chars)
    end

    local function eval_condition(expr)
        local lua_expr = normalize_condition_expr(expr)
        local env = setmetatable({
            exists = function(name)
                return exists_var(name)
            end,
            var = function(name)
                return vars[name] or 0
            end,
            getvar = function(scope, name, default)
                local value = vars[tostring(scope or "") .. tostring(name or "")]
                if value ~= nil then
                    return value
                end
                return default
            end,
            has = function(_)
                return false
            end,
        }, {
            __index = function(_, key)
                return vars[key] or 0
            end,
        })

        local chunk = load("return (" .. lua_expr .. ")", "cond", "t", env)
        if not chunk then
            return false
        end
        local ok, value = pcall(chunk)
        if not ok then
            return false
        end
        return truthy(value)
    end

    local function parse_if_control(raw)
        local line = trim(raw)
        local expr = line:match("^if%s+(.+)$")
        if expr then return "if", expr end
        expr = line:match("^elseif%s+(.+)$")
        if expr then return "elseif", expr end
        if line == "else" then return "else", nil end
        if line == "endif" then return "endif", nil end
        return nil, nil
    end

    local function collect_file(path, include_cluster, force_contained)
        local resolved = normalize_path(path)
        if seen_files[resolved] then
            return {}
        end
        seen_files[resolved] = true

        local groups = {}
        local logical = read_logical_lines(resolved)
        local cond_stack = {}

        local function is_active()
            for j = 1, #cond_stack do
                if not cond_stack[j].active then
                    return false
                end
            end
            return true
        end

        for i = 1, #logical do
            local raw = trim(logical[i])

            local ctl, expr = parse_if_control(raw)
            if ctl == "if" then
                local parent_active = is_active()
                local cond = parent_active and eval_condition(expr) or false
                cond_stack[#cond_stack + 1] = {
                    parent_active = parent_active,
                    branch_taken = cond,
                    active = parent_active and cond,
                }
                goto continue
            elseif ctl == "elseif" then
                local top = cond_stack[#cond_stack]
                if top then
                    if not top.parent_active then
                        top.active = false
                    elseif top.branch_taken then
                        top.active = false
                    else
                        local cond = eval_condition(expr)
                        top.active = cond
                        if cond then top.branch_taken = true end
                    end
                end
                goto continue
            elseif ctl == "else" then
                local top = cond_stack[#cond_stack]
                if top then
                    if top.parent_active and not top.branch_taken then
                        top.active = true
                        top.branch_taken = true
                    else
                        top.active = false
                    end
                end
                goto continue
            elseif ctl == "endif" then
                if #cond_stack > 0 then
                    cond_stack[#cond_stack] = nil
                end
                goto continue
            end

            if not is_active() then
                goto continue
            end

            parse_assignment(raw)

            local runtime_path = parse_runtime_include(raw)
            if runtime_path then
                local inc_path = resolve_include_path(resolved, runtime_path)
                if inc_path then
                    local nested = collect_file(inc_path, nil, force_contained)
                    for g in pairs(nested) do
                        groups[g] = true
                    end
                end
                goto continue
            end

            local payload = normalize_syn_line(raw, opts.include_vim9)
            if not payload then
                payload = parse_execute_syntax_line(raw, opts.include_vim9, vars)
            end
            if payload then
                local parsed = Parser.parse(payload)
                if parsed.kind == "include" then
                    local inc_path = resolve_include_path(resolved, parsed.file)
                    if inc_path then
                        local nested = collect_file(inc_path, parsed.cluster, true)
                        for g in pairs(nested) do
                            groups[g] = true
                        end
                    end
                elseif parsed.kind ~= "unknown" then
                    if
                        force_contained
                        and (parsed.kind == "keyword" or parsed.kind == "match" or parsed.kind == "region")
                    then
                        parsed.options.flags.contained = true
                    end

                    commands[#commands + 1] = parsed

                    if (parsed.kind == "keyword" or parsed.kind == "match" or parsed.kind == "region")
                        and parsed.group and parsed.group ~= "" then
                        groups[parsed.group] = true
                    end
                end
            end
            ::continue::
        end

        if include_cluster and include_cluster ~= "" then
            local add = sorted_keys(groups)
            if #add > 0 then
                commands[#commands + 1] = {
                    kind = "cluster",
                    raw = "synthetic include cluster",
                    name = include_cluster,
                    contains = nil,
                    add = add,
                    remove = nil,
                    attrs = {},
                    unknown = {},
                }
            end
        end

        return groups
    end

    collect_file(syntax_file, nil, false)

    local generated_file = normalize_path(join(RUNTIME_ROOT, ("syntax/%s/generated.vim"):format(tostring(ft))))
    if file_exists(generated_file) then
        collect_file(generated_file, nil, false)
    end

    return commands, syntax_file
end

local function segments_to_groups(len, segments)
    local groups = {}
    for i = 1, len do
        groups[i] = "Normal"
    end
    for i = 1, #segments do
        local s = math.max(1, segments[i].s or 1)
        local e = math.min(len, segments[i].e or len)
        local g = segments[i].group or "Normal"
        for col = s, e do
            groups[col] = g
        end
    end
    return groups
end

local function collect_lua_segments(path, ft, opts)
    local lines = read_lines(path)
    local out = {
        syntax_file = normalize_path(join(RUNTIME_ROOT, "syntax/" .. tostring(ft) .. ".vim")),
        segments = {},
        lines = lines,
    }

    local MockEnv = require("tests.test_mocks")
    local mock = MockEnv.setup({
        ccvim_path = REPO_ROOT,
        bootstrap_default_editor = true,
    })
    local ok, err = pcall(function()
        local Event = mock.loadModule("lib.event")
        Event.LoadCommandModule()

        local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
        local vim = ApiBuild.Build().vim
        local G = mock.globals()
        local buffer = G.windows[G.curwin].buffer
        buffer.name = path
        buffer.lines = lines
        buffer.loaded = true

        vim.cmd("filetype on")
        vim.cmd("syntax on")
        if opts.ft and opts.ft ~= "" then
            vim.bo.filetype = opts.ft
        else
            vim.cmd("filetype detect")
        end

        out.syntax_file = normalize_path(join(RUNTIME_ROOT, "syntax/" .. tostring(vim.bo.syntax or ft) .. ".vim"))
        for ln = 1, #lines do
            local text = lines[ln]
            local segments = {}
            local col = 1
            while col <= #text do
                local group = vim.fn.synIDattr(vim.fn.synID(ln, col, 1), "name")
                if group == "" then group = "Normal" end
                local last = col + 1
                while last <= #text do
                    local next_group = vim.fn.synIDattr(vim.fn.synID(ln, last, 1), "name")
                    if next_group == "" then next_group = "Normal" end
                    if next_group ~= group then break end
                    last = last + 1
                end
                segments[#segments + 1] = {
                    s = col,
                    e = last - 1,
                    group = group,
                }
                col = last
            end
            out.segments[ln] = segments
        end
    end)
    mock.cleanup()

    if not ok then
        return nil, tostring(err)
    end

    return out
end

local function fmt_snippet(s)
    local out = tostring(s or "")
    out = out:gsub("\t", "\\t")
    if #out > 60 then
        out = out:sub(1, 57) .. "..."
    end
    return out
end

local function compare_and_print(path, ft, nvim_data, lua_data, opts)
    opts = opts or {}
    local lines = lua_data.lines
    local line_count = #lines

    local compared_lines = 0
    local mismatch_lines = 0
    local mismatch_cols = 0
    local total_cols = 0
    local reports = {}

    for ln = 1, line_count do
        if (not opts.lines) or opts.lines[ln] then
            compared_lines = compared_lines + 1

            local text = lines[ln] or ""
            local len = #text
            total_cols = total_cols + len

            local ng = segments_to_groups(len, nvim_data.segments[ln] or {})
            local lg = segments_to_groups(len, lua_data.segments[ln] or {})

            local ranges = {}
            local col = 1
            while col <= len do
                if ng[col] ~= lg[col] then
                    local n_name = ng[col]
                    local l_name = lg[col]
                    local s = col
                    col = col + 1
                    while col <= len and ng[col] == n_name and lg[col] == l_name do
                        col = col + 1
                    end
                    ranges[#ranges + 1] = {
                        s = s,
                        e = col - 1,
                        nvim = n_name,
                        lua = l_name,
                    }
                else
                    col = col + 1
                end
            end

            if #ranges > 0 then
                mismatch_lines = mismatch_lines + 1
                for i = 1, #ranges do
                    mismatch_cols = mismatch_cols + (ranges[i].e - ranges[i].s + 1)
                end
                reports[#reports + 1] = {
                    line = ln,
                    text = text,
                    ranges = ranges,
                }
            end
        end
    end

    local stats = {
        file = path,
        filetype = ft,
        syntax_file = lua_data.syntax_file,
        compared_lines = compared_lines,
        mismatch_lines = mismatch_lines,
        mismatch_cols = mismatch_cols,
        total_cols = total_cols,
        reports = reports,
    }

    if opts.quiet then
        return stats
    end

    io.write(("File: %s\n"):format(path))
    io.write(("Filetype: %s\n"):format(ft))
    io.write(("Syntax File (Lua engine): %s\n"):format(lua_data.syntax_file))
    io.write(("Compared Lines: %d\n"):format(compared_lines))
    io.write(("Mismatched Lines: %d\n"):format(mismatch_lines))
    io.write(("Mismatched Columns: %d / %d\n"):format(mismatch_cols, total_cols))

    if mismatch_lines == 0 then
        io.write("No discrepancies found.\n")
        return stats
    end

    io.write("\nDiscrepancies:\n")
    local shown = 0
    for i = 1, #reports do
        if shown >= opts.max_report then
            io.write(("... truncated after %d mismatched lines\n"):format(opts.max_report))
            break
        end
        shown = shown + 1
        local r = reports[i]
        io.write(("[%d] %s\n"):format(r.line, fmt_snippet(r.text)))
        for j = 1, #r.ranges do
            local rg = r.ranges[j]
            local snippet = fmt_snippet(r.text:sub(rg.s, rg.e))
            io.write(
                ("  %d-%d nvim=%s  lua=%s  text='%s'\n")
                :format(rg.s, rg.e, tostring(rg.nvim), tostring(rg.lua), snippet)
            )
        end
    end

    return stats
end

local function compare_file(opts)
    opts = opts or {}
    local target = normalize_path(opts.file)
    if not file_exists(target) then
        error("File not found: " .. target)
    end

    local nvim_data = opts.nvim_data or collect_nvim_segments(target, opts.ft)
    if nvim_data.error then
        error("nvim probe failed: " .. tostring(nvim_data.error))
    end
    local ft = trim(opts.ft or "")
    if ft == "" then
        ft = trim(nvim_data.filetype)
    end
    if ft == "" then
        error("Unable to determine filetype. Pass --ft=<filetype>.")
    end

    local lua_opts = {}
    for k, v in pairs(opts) do
        lua_opts[k] = v
    end
    lua_opts.synmaxcol = lua_opts.synmaxcol or nvim_data.synmaxcol or 3000

    local lua_data, lerr = collect_lua_segments(target, ft, lua_opts)
    if not lua_data then
        error("Lua engine probe failed: " .. tostring(lerr))
    end

    return compare_and_print(target, ft, nvim_data, lua_data, opts)
end

local function main(argv)
    local opts = parse_args(argv)
    local stats = compare_file(opts)
    if opts.fail_on_diff and stats.mismatch_lines > 0 then
        os.exit(1)
    end
end

local M = {
    compare_file = compare_file,
    collect_lua_segments = collect_lua_segments,
    collect_nvim_segments = collect_nvim_segments,
    collect_nvim_segments_many = collect_nvim_segments_many,
    collect_static_commands = function(ft, opts)
        init_lua_engine_runtime()
        return load_syntax_commands(ft, opts or {})
    end,
    normalize_path = normalize_path,
}

local module_name = ...
if not (type(module_name) == "string" and module_name:match("compare_highlighting$")) then
    main(arg)
end

return M
