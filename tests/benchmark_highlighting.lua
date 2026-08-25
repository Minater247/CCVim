-- This file compares the syntax groups assigned to files by this utility and the real neovim executable.
-- It has been useful for testing, so I am including it for anyone else why wants to develop this.

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function starts_with(s, prefix)
    return s:sub(1, #prefix) == prefix
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

local function usage()
    io.write([[
Usage: lua tests/benchmark_highlighting.lua [file] [options]

Options:
  --ft=<filetype>          Force filetype instead of nvim detection.
  --runs=<n>               Number of runs per engine (default: 3).
  --mode=<full|target>     full=blit every line, target=blit only last line.
  --profile                Print Lua syntax matcher profiling for the last run.
  --vim9                   Include "Vim9 ..." prefixed syntax commands.
  --help                   Show this help.

The default file is:
  runtime/pack/dist/opt/netrw/autoload/netrw.vim

Examples:
  lua tests/benchmark_highlighting.lua
  lua tests/benchmark_highlighting.lua runtime/pack/dist/opt/netrw/autoload/netrw.vim --ft=vim --runs=5
]])
end

local function parse_args(argv)
    local opts = {
        file = "runtime/pack/dist/opt/netrw/autoload/netrw.vim",
        file_set = false,
        ft = nil,
        runs = 3,
        mode = "full",
        profile = false,
        include_vim9 = false,
    }

    for i = 1, #argv do
        local a = tostring(argv[i])
        if a == "--help" or a == "-h" then
            usage()
            os.exit(0)
        elseif starts_with(a, "--ft=") then
            opts.ft = a:sub(6)
        elseif starts_with(a, "--runs=") then
            local n = tonumber(a:sub(8))
            if n and n > 0 then
                opts.runs = math.floor(n)
            end
        elseif starts_with(a, "--mode=") then
            local mode = trim(a:sub(8)):lower()
            if mode == "full" or mode == "target" then
                opts.mode = mode
            else
                error("Unsupported mode: " .. mode)
            end
        elseif a == "--vim9" then
            opts.include_vim9 = true
        elseif a == "--profile" then
            opts.profile = true
        elseif starts_with(a, "--") then
            error("Unknown option: " .. a)
        elseif not opts.file_set then
            opts.file = a
            opts.file_set = true
        else
            error("Unexpected argument: " .. a)
        end
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

local setup_start = vim.loop.hrtime()
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

local setup_ns = vim.loop.hrtime() - setup_start
io.write("FT\t" .. tostring(vim.bo.filetype or "") .. "\n")

local hl_start = vim.loop.hrtime()
local line_count = vim.api.nvim_buf_line_count(0)
for ln = 1, line_count do
  local text = vim.fn.getline(ln)
  local len = #text
  if len > 0 then
    local col = 1
    while col <= len do
      local id = vim.fn.synID(ln, col, 1)

      local j = col + 1
      while j <= len do
        local id2 = vim.fn.synID(ln, j, 1)
        if id2 ~= id then break end
        j = j + 1
      end

      col = j
    end
  end
end

local highlight_ns = vim.loop.hrtime() - hl_start
io.write(("T\t%d\t%d\t%d\n"):format(setup_ns, highlight_ns, line_count))
vim.cmd("qa!")
]])

    f:close()
end

local function collect_nvim_timing(path, forced_ft)
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

    local out = { filetype = "", setup_ns = 0, highlight_ns = 0, line_count = 0 }

    for line in output:gmatch("[^\n]*\n?") do
        local row = line:gsub("\n$", "")
        if starts_with(row, "FT\t") then
            out.filetype = row:sub(4)
        elseif starts_with(row, "T\t") then
            local s1, s2, s3 = row:match("^T\t(%d+)\t(%d+)\t(%d+)$")
            if s1 then
                out.setup_ns = tonumber(s1) or 0
                out.highlight_ns = tonumber(s2) or 0
                out.line_count = tonumber(s3) or 0
            end
        end
    end

    if out.filetype == "" and forced_ft and forced_ft ~= "" then
        out.filetype = forced_ft
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

local function now_seconds()
    return os.clock()
end

local function collect_lua_timing(path, ft, opts)
    local t0 = now_seconds()

    init_lua_engine_runtime()

    local Runtime = loadModule("lib.syntax_engine.runtime")
    local Compiler = loadModule("lib.syntax_engine.compiler")
    local Profile = loadModule("lib.syntax_engine.profile")
    local State = loadModule("lib.syntax_engine.state")

    local commands, syntax_file_or_err = load_syntax_commands(ft, opts)
    if not commands then
        return nil, syntax_file_or_err
    end

    local lines = read_lines(path)
    local buf = { lines = lines }
    function buf:line_count()
        return #self.lines
    end
    function buf:get_line(line_nr)
        return self.lines[line_nr]
    end

    local ctx = State.new_context({
        syntax = ft,
        synmaxcol = 100000,
    })
    ctx.syntax_commands = commands
    ctx.syntax_ir = Compiler.compile(commands)
    ctx.syntax_ir_dirty = false
    Profile.set_enabled(ctx, opts.profile)

    local setup_ms = (now_seconds() - t0) * 1000

    local h0 = now_seconds()
    if opts.mode == "target" then
        Runtime.line_to_blit(ctx, buf, #lines)
    else
        local blits = Runtime.lines_to_blit(ctx, buf, 1, #lines)
        local checksum = 0
        local line_hits = 0
        local expected_chars = 0
        for ln = 1, #lines do
            expected_chars = expected_chars + #(lines[ln] or "")
        end
        for ln = 1, #lines do
            local b = blits[ln]
            if b and b.hl then
                checksum = checksum + #b.hl
                line_hits = line_hits + 1
            end
        end
        if #lines > 0 and (line_hits ~= #lines or checksum ~= expected_chars) then
            error(("Runtime.lines_to_blit incomplete output (hits=%d/%d checksum=%d expected=%d)")
            :format(line_hits, #lines, checksum, expected_chars))
        end
    end
    local highlight_ms = (now_seconds() - h0) * 1000

    return {
        setup_ms = setup_ms,
        highlight_ms = highlight_ms,
        line_count = #lines,
        syntax_file = syntax_file_or_err,
        profile = opts.profile and Profile.report(ctx) or nil,
    }
end

local function summarize_runs(runs)
    local stats = {
        setup_avg = 0, setup_min = math.huge, setup_max = 0,
        highlight_avg = 0, highlight_min = math.huge, highlight_max = 0,
        total_avg = 0, total_min = math.huge, total_max = 0,
    }
    for i = 1, #runs do
        local r = runs[i]
        local total = r.setup_ms + r.highlight_ms
        stats.setup_avg = stats.setup_avg + r.setup_ms
        stats.highlight_avg = stats.highlight_avg + r.highlight_ms
        stats.total_avg = stats.total_avg + total
        if r.setup_ms < stats.setup_min then stats.setup_min = r.setup_ms end
        if r.setup_ms > stats.setup_max then stats.setup_max = r.setup_ms end
        if r.highlight_ms < stats.highlight_min then stats.highlight_min = r.highlight_ms end
        if r.highlight_ms > stats.highlight_max then stats.highlight_max = r.highlight_ms end
        if total < stats.total_min then stats.total_min = total end
        if total > stats.total_max then stats.total_max = total end
    end
    local n = math.max(1, #runs)
    stats.setup_avg = stats.setup_avg / n
    stats.highlight_avg = stats.highlight_avg / n
    stats.total_avg = stats.total_avg / n
    return stats
end

local function print_engine_runs(name, runs)
    io.write(("\n%s runs:\n"):format(name))
    for i = 1, #runs do
        local r = runs[i]
        io.write(
            ("  run %d: setup=%.2f ms  highlight=%.2f ms  total=%.2f ms\n")
            :format(i, r.setup_ms, r.highlight_ms, r.setup_ms + r.highlight_ms)
        )
    end

    local s = summarize_runs(runs)
    io.write(
        ("  avg: setup=%.2f ms  highlight=%.2f ms  total=%.2f ms\n"):format(
            s.setup_avg,
            s.highlight_avg,
            s.total_avg
        )
    )
    io.write(
        ("  min: setup=%.2f ms  highlight=%.2f ms  total=%.2f ms\n"):format(
            s.setup_min,
            s.highlight_min,
            s.total_min
        )
    )
    io.write(
        ("  max: setup=%.2f ms  highlight=%.2f ms  total=%.2f ms\n"):format(
            s.setup_max,
            s.highlight_max,
            s.total_max
        )
    )
end

local function main(argv)
    local opts = parse_args(argv)
    local target = normalize_path(opts.file)
    if not file_exists(target) then
        error("File not found: " .. target)
    end

    local nvim_runs = {}
    local detected_ft = trim(opts.ft or "")
    for _ = 1, opts.runs do
        local run = collect_nvim_timing(target, opts.ft)
        nvim_runs[#nvim_runs + 1] = {
            setup_ms = (run.setup_ns or 0) / 1000000,
            highlight_ms = (run.highlight_ns or 0) / 1000000,
            line_count = run.line_count or 0,
        }
        if detected_ft == "" then
            detected_ft = trim(run.filetype or "")
        end
    end

    if detected_ft == "" then
        error("Unable to determine filetype. Pass --ft=<filetype>.")
    end

    local lua_runs = {}
    local syntax_file = nil
    for _ = 1, opts.runs do
        local run, lerr = collect_lua_timing(target, detected_ft, opts)
        if not run then
            error("Lua engine benchmark failed: " .. tostring(lerr))
        end
        syntax_file = syntax_file or run.syntax_file
        lua_runs[#lua_runs + 1] = run
    end

    io.write(("File: %s\n"):format(target))
    io.write(("Filetype: %s\n"):format(detected_ft))
    if syntax_file then
        io.write(("Syntax File (Lua engine): %s\n"):format(syntax_file))
    end
    io.write(("Runs: %d\n"):format(opts.runs))
    io.write(("Mode: %s\n"):format(opts.mode))
    if nvim_runs[1] then
        io.write(("Line count: %d\n"):format(nvim_runs[1].line_count or 0))
    end

    print_engine_runs("Neovim", nvim_runs)
    print_engine_runs("Lua engine", lua_runs)
    local profile = lua_runs[#lua_runs] and lua_runs[#lua_runs].profile
    if profile then
        io.write("\nLua matcher profile:\n")
        io.write(table.concat(profile, "\n"), "\n")
    end
end

main(arg)
