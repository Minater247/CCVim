-- Builtins table: used by Vimscript evaluator and :call to dispatch core functions.
-- Additionally, we export a Lua-side proxy (fn._proxy) that mimics Neovim's vim.fn:
-- it resolves to Vimscript functions (user-defined) and falls back to builtins.

local Builtins   = {}

local Error      = loadModule("lib.error")
local Highlight  = loadModule("lib.highlight")
local Syntax
local Runtime
local ExMsg
local EnvVars
local Buffer     = loadModule("layout.buffer")
local Tab        = loadModule("lib.tab")
local scopes     = loadModule("lib.luaapi.scopes")
local VimRegex   = loadModule("lib.excmd.vim_regex")
local Sign       = loadModule("lib.sign")
local Filesystem = loadModule("lib.filesystem")
local TblUtils   = loadModule("lib.luaapi.tblutils")
local VimFs      = loadModule("lib.luaapi.fs")
local RuntimePath = loadModule("lib.runtimepath")

local funcref_name_by_fn = setmetatable({}, { __mode = "k" })
local funcref_fn_by_name = {}
local _jobs = {}
local _next_job_id = 1

-- Helper: call a Vimscript function by name (user-defined via runtime registry) or a builtin here.
local function call_vimfunc(name, ...)
    -- Builtin first
    local b = Builtins[name]
    if type(b) == "function" then
        return b(...)
    end
    Runtime = Runtime or loadModule("lib.excmd.runtime")
    -- User-defined Vimscript function
    local def, resolved_name = Runtime.ResolveFunctionDef(name, { state = Runtime._CURRENT_STATE })
    if not def and Runtime.TryAutoloadFunction(name) then
        def, resolved_name = Runtime.ResolveFunctionDef(name, { state = Runtime._CURRENT_STATE })
    end
    if not def then
        -- if Dict.member and global dict exists, try g: prefix
        local dict, mem = name:match("^([%w_]+)%.([%w_]+)$")
        if dict and scopes._g[dict] then
            local gname = "g:" .. dict .. "." .. mem
            def, resolved_name = Runtime.ResolveFunctionDef(gname, { state = Runtime._CURRENT_STATE })
            name = gname
        end
    end
    if not def then
        local fr = funcref_fn_by_name[name]
        if type(fr) == "function" then
            return fr(...)
        end
        LOG_INTERNAL("missing", "vim.fn.%s not implemented", tostring(name))
        error(Error(117, name):toString())
    end
    local call_name = resolved_name or name
    -- Map args to a:/l: by parameter list (including a:0/a:000 for varargs).
    local args = { ... }
    local l_scope, a_scope = Runtime.BuildCallScopes(args, def.params or {})
    -- Dict function: inject a:self/l:self
    if def.attrs and def.attrs.dict then
        local dname = name:match("^g:([%w_]+)%.") or name:match("^([%w_]+)%.")
        if dname then
            local selfdict = scopes._g[dname]
            a_scope.self = selfdict
            l_scope.self = selfdict
        end
    end
    Runtime = Runtime or loadModule("lib.excmd.runtime")
    if def.kind == "compiled" and type(def.body) == "function" then
        local state = {
            g = scopes._g,
            s = def.scope or {},
            script_sid = def.script_sid,
            script_ctx = def.script_ctx,
            v = { ["true"] = true, ["false"] = false, null = nil, errmsg = "", exception = nil, throwpoint = nil },
            funcs = def.funcs or Runtime._FUNCS or {},
        }
        local rt = Runtime.new(state)
        rt:push_frame(args, def.params or {})
        local ok, rv = pcall(def.body, rt)
        rt:pop_frame()
        if ok then return rv end
        if type(rv) == "table" and rv.__ret then return rv.value end
        error(Error.IsError(rv) and rv:toString() or tostring(rv))
    else
        local state = {
            g = scopes._g,
            s = def.scope or {},
            script_sid = def.script_sid,
            script_ctx = def.script_ctx,
            v = { ["true"] = true, ["false"] = false, null = nil, errmsg = "", exception = nil, throwpoint = nil },
            funcs = def.funcs or Runtime._FUNCS or {},
            a = a_scope,
            l = l_scope,
            frames = {
                {
                    kind = "func",
                    l = l_scope,
                    a = a_scope,
                },
            },
        }
        state.funcs[name] = def
        state.funcs[call_name] = def
        if def.name then
            state.funcs[def.name] = def
        end
        local body = def.body
        if type(body) == "table" then
            local lines = {}
            for i = 1, #body do
                local node = body[i]
                if type(node) == "table" then
                    lines[#lines + 1] = node.text or node.raw or node.cmd or ""
                else
                    lines[#lines + 1] = tostring(node)
                end
            end
            body = table.concat(lines, "\n")
        end
        local ok, rv = Runtime.run(body, {
            state = state,
            ctrl = Runtime._CURRENT_CTRL,
            origin = {
                kind = "vim-function",
                func = call_name,
                source = def.script_ctx,
            },
        })
        if ok == false and rv then
            error(Error.IsError(rv) and rv:toString() or tostring(rv))
        end
        return rv
    end
end

local function register_funcref_name(name, fn)
    if type(name) ~= "string" or name == "" then
        return false
    end
    if type(fn) ~= "function" then
        return false
    end
    funcref_name_by_fn[fn] = name
    funcref_fn_by_name[name] = fn
    return true
end

local function resolve_win(id)
    if id == nil or id == 0 then
        return windows[curwin]
    end
    if type(id) ~= "number" then
        return nil
    end
    return windows[id]
end

local function _abs_path(p)
    return VimFs.abspath(tostring(p or ""))
end

local function _trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function _is_abs_or_explicit_rel(path)
    local p = tostring(path or "")
    if p == "" then return false end
    if p:sub(1, 1) == "/" then return true end
    if p:sub(1, 2) == "./" then return true end
    if p == "." then return true end
    if p:sub(1, 3) == "../" then return true end
    if p == ".." then return true end
    return false
end

local function _has_glob(s)
    return tostring(s or ""):find("[%*%?%[]") ~= nil
end

local function _dir_of(path)
    local p = tostring(path or "")
    if p == "" then return "" end
    p = p:gsub("/+$", "")
    if p == "" then return "/" end
    local d = p:match("^(.*)/[^/]*$")
    if d == nil then
        return "."
    end
    if d == "" then return "/" end
    return d
end

local function _join(base, rel)
    base = tostring(base or "")
    rel = tostring(rel or "")
    if rel == "" then return base end
    if rel:sub(1, 1) == "/" then return rel end
    if base == "" then return rel end
    if base == "/" then return "/" .. rel end
    if base:sub(-1) == "/" then
        return base .. rel
    end
    return base .. "/" .. rel
end

local function _expand_path_entry(entry, cwd, cur_file_dir)
    local raw = _trim(entry)
    if raw == "" then
        return { cwd }
    end

    if raw == "." then
        return { cur_file_dir ~= "" and cur_file_dir or cwd }
    end

    local want_upward = false
    if raw:sub(-1) == ";" then
        raw = raw:sub(1, -2)
        want_upward = true
    end
    if raw == "" then
        raw = "."
    end

    local root
    if raw == "." then
        root = cur_file_dir ~= "" and cur_file_dir or cwd
    elseif _is_abs_or_explicit_rel(raw) then
        root = _abs_path(raw)
    else
        root = _abs_path(_join(cwd, raw))
    end

    local bases = {}
    if _has_glob(root) then
        local matches = Filesystem.ExpandWildcards(root)
        for i = 1, #matches do
            local m = matches[i]
            if fs.exists(m) and fs.isDir(m) then
                bases[#bases + 1] = VimFs.normalize(m, { expand_env = false })
            end
        end
    else
        bases[1] = VimFs.normalize(root, { expand_env = false })
    end

    if not want_upward then
        return bases
    end

    local out = {}
    local seen = {}
    for i = 1, #bases do
        local d = bases[i]
        while d and d ~= "" do
            local norm = VimFs.normalize(d, { expand_env = false })
            if not seen[norm] then
                out[#out + 1] = norm
                seen[norm] = true
            end
            if norm == "/" then
                break
            end
            d = _dir_of(norm)
            if d == norm then
                break
            end
        end
    end
    return out
end

local function _suffixesadd_list(buf)
    local out = {}
    local seen = {}
    if not buf then
        return out
    end
    local raw = options.get("suffixesadd", nil, buf) or ""
    local items = options.ParseCSL(raw)
    for i = 1, #items do
        local s = items[i]
        if s ~= "" and not seen[s] then
            out[#out + 1] = s
            seen[s] = true
        end
    end
    return out
end

local function _candidate_names(name, buf, use_suffixes)
    local out = { tostring(name or "") }
    local seen = { [out[1]] = true }
    if not use_suffixes then
        return out
    end

    local suff = _suffixesadd_list(buf)
    for i = 1, #suff do
        local cand = out[1] .. suff[i]
        if not seen[cand] then
            out[#out + 1] = cand
            seen[cand] = true
        end
    end
    return out
end

local function _matches_for_name(name, path_spec, buf, find_dirs, use_suffixes)
    local raw_name = tostring(name or "")
    if raw_name == "" then
        return {}
    end

    local win = windows[curwin]
    local cwd = Builtins.getcwd()
    local cur_file_dir = ""
    if win and win.buffer and win.buffer.name and win.buffer.name ~= "" then
        cur_file_dir = _dir_of(_abs_path(win.buffer.name))
    end

    local names = _candidate_names(raw_name, buf, use_suffixes)
    local out, seen = {}, {}

    local function maybe_add(path)
        local p = VimFs.normalize(path, { expand_env = false })
        if not fs.exists(p) then return end
        if find_dirs then
            if not fs.isDir(p) then return end
        else
            if fs.isDir(p) then return end
        end
        if not seen[p] then
            out[#out + 1] = p
            seen[p] = true
        end
    end

    if _is_abs_or_explicit_rel(raw_name) then
        for i = 1, #names do
            maybe_add(_abs_path(names[i]))
        end
        return out
    end

    local p = tostring(path_spec or "")
    local entries = options.ParseCSL(p)
    if #entries == 0 then
        entries = { ".", "", }
    end

    for i = 1, #entries do
        local bases = _expand_path_entry(entries[i], cwd, cur_file_dir)
        for bi = 1, #bases do
            local base = bases[bi]
            for ni = 1, #names do
                maybe_add(_join(base, names[ni]))
            end
        end
    end

    return out
end

local function _eval_includeexpr(fname, buf)
    if not buf then
        return tostring(fname or "")
    end
    local expr = tostring(options.get("includeexpr", nil, buf) or "")
    if expr == "" then
        return tostring(fname or "")
    end

    local VimExpr = loadModule("lib.excmd.vimxpr")
    local scope_v = { fname = tostring(fname or "") }
    local rv = VimExpr.evaluate(expr, {
        scope = { g = scopes._g, v = scope_v },
        funcs = Builtins,
    })
    if Error.IsError(rv) then
        return tostring(fname or "")
    end
    return tostring(rv or "")
end

local function _resolve_with_includeexpr(name, path_spec, buf, find_dirs, use_suffixes)
    local matches = _matches_for_name(name, path_spec, buf, find_dirs, use_suffixes)
    if #matches > 0 then
        return matches
    end
    local transformed = _eval_includeexpr(name, buf)
    if transformed == "" or transformed == tostring(name or "") then
        return matches
    end
    return _matches_for_name(transformed, path_spec, buf, find_dirs, use_suffixes)
end

local function _extract_cfile_text(win)
    if not win or not win.buffer then return "" end
    local buf = win.buffer
    local line = buf:get_line(win.cursory, true) or ""
    if line == "" then return "" end

    local cx = win.cursorx
    local line_len = buf:str_len(line)
    if cx < 1 then cx = 1 end
    if cx > line_len and line_len > 0 then
        cx = line_len
    end

    local function is_cfile_char(ch)
        return ch:match("[%w%._%-%+/%\\$%%,#{}%[%]~@:]") ~= nil
    end

    if cx < 1 or cx > line_len then
        return ""
    end
    if not is_cfile_char(buf:str_char_at(line, cx)) then
        if cx > 1 and is_cfile_char(buf:str_char_at(line, cx - 1)) then
            cx = cx - 1
        else
            return ""
        end
    end

    local s, e = cx, cx
    while s > 1 and is_cfile_char(buf:str_char_at(line, s - 1)) do s = s - 1 end
    while e < line_len and is_cfile_char(buf:str_char_at(line, e + 1)) do e = e + 1 end
    return buf:str_sub(line, s, e)
end

local function _expand_cfile(buf)
    local win = windows[curwin]
    local raw = _extract_cfile_text(win)
    if raw == "" then
        return ""
    end

    if _is_abs_or_explicit_rel(raw) then
        return _eval_includeexpr(raw, buf)
    end

    local path_spec = (buf and options.get("path", nil, buf)) or ".,,"
    local found = _resolve_with_includeexpr(raw, path_spec, buf, false, true)
    if #found > 0 then
        return found[1]
    end
    return _eval_includeexpr(raw, buf)
end

local function _is_vim_list_expr(expr)
    return type(expr) == "table" and not expr.__call
end

local function _syntax_mod()
    Syntax = Syntax or loadModule("lib.syntax")
    return Syntax
end

local function _prepare_match_pattern(pat, use_ignorecase_opt)
    pat = tostring(pat or "")

    -- Determine case policy from \c / \C markers (last one wins). Remove them from pattern.
    local case_override -- true => case sensitive, false => ignore case
    pat = pat:gsub("\\[cC]", function(m)
        case_override = (m == "\\C")
        return "" -- strip
    end)

    -- Base case sensitivity on override or global 'ignorecase'.
    local case_sensitive
    if case_override ~= nil then
        case_sensitive = case_override
    else
        if use_ignorecase_opt == false then
            case_sensitive = true
        else
            case_sensitive = not options.get("ignorecase")
        end
    end

    local compiled, c_err = VimRegex.compile(pat)
    if not compiled then
        return nil, nil, c_err
    end
    return compiled, case_sensitive, nil
end

local function _search_set_cursor(win, lnum, col1)
    if type(win._set_cursor_raw) == "function" then
        win:_set_cursor_raw(lnum, col1)
        return
    end

    local buf = win.buffer
    local lines = buf:lines_ref(true)
    local line_count = #lines
    if line_count < 1 then
        line_count = 1
    end
    if lnum < 1 then lnum = 1 end
    if lnum > line_count then lnum = line_count end

    local line = lines[lnum] or ""
    local max_col = buf:str_len(line) + 1
    if col1 < 1 then col1 = 1 end
    if col1 > max_col then col1 = max_col end

    win.cursory = lnum
    win.cursorx = col1
end

local function _search_truthy(v)
    return not (v == nil or v == false or v == 0)
end

local function _search_submatch_nr(text, compiled, case_sensitive, match_s, match_e)
    local s, e, caps = VimRegex.find_compiled_with_caps(text, compiled, case_sensitive, nil, match_s)
    if not s or s ~= match_s or e ~= match_e or type(caps) ~= "table" then
        return 1
    end

    local first_idx = nil
    for k, v in pairs(caps) do
        if type(k) == "number" and v ~= nil then
            if first_idx == nil or k < first_idx then
                first_idx = k
            end
        end
    end
    if first_idx == nil then
        return 1
    end
    return first_idx + 1
end

-- Vim-like stringification for non-string values (minimal subset used by join())
local function vim_string(v)
    local t = type(v)
    if t == "string" then
        return "'" .. v:gsub("'", "''") .. "'"
    elseif t == "number" then
        return tostring(v)
    elseif t == "boolean" then
        return v and "v:true" or "v:false"
    elseif v == nil then
        return "v:null"
    elseif t == "table" then
        local is_list = (#v > 0) or (v[1] ~= nil)
        if is_list then
            local parts = {}
            for i = 1, #v do parts[#parts + 1] = vim_string(v[i]) end
            return "[" .. table.concat(parts, ", ") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                local kstr = (type(k) == "string") and ("'" .. k:gsub("'", "''") .. "'") or tostring(k)
                parts[#parts + 1] = kstr .. ": " .. vim_string(val)
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        end
    end
    return tostring(v)
end

-- ---------------- Builtins (Lua implementations) ----------------

-- win_gettype([{nr}]): return window kind string per Vim help
-- Implements a subset relevant to this runtime:
--   "popup"    -> floating window (Window.floatpos set)
--   "quickfix" -> quickfix window (win.quickfix truthy)
--   "loclist"  -> location-list window (win.loclist truthy)
--   ""         -> normal window
--   "unknown"  -> window not found
function Builtins.win_gettype(nr)
    local win = resolve_win(nr)
    if not win then return "unknown" end

    -- Floating window created via nvim_open_win has floatpos
    if win.floatpos ~= nil then
        return "popup"
    end

    if win.quickfix and win.quickfix ~= 0 then
        return "quickfix"
    end
    if win.loclist and win.loclist ~= 0 then
        return "loclist"
    end

    -- Not implemented in this runtime yet:
    --   autocmd window, command-line window, preview window
    -- Fall back to normal (empty string)
    return ""
end

function Builtins.winwidth(nr)
    local win = resolve_win(nr)
    if not win then return -1 end

    if win.floatpos then
        return win.floatpos.w
    else
        return win.frame.width
    end
end

function Builtins.winsaveview(...)
    if select("#", ...) > 0 then
        error(Error(118, "winsaveview"):toString())
    end

    local win = windows[curwin]
    local line = win.buffer:get_line(win.cursory, true) or ""
    local tcfg = Tab.get_tab_config(win.buffer)

    local want = win._held_vx
    if want == nil then
        want = Tab.vcol_of_prefix(line, win.cursorx, tcfg) + 1
    end

    local scrollx = win.scrollx or 1
    if scrollx < 1 then scrollx = 1 end

    return {
        lnum = win.cursory,
        col = win.cursorx - 1,
        coladd = 0,
        curswant = want - 1,
        topline = (win.scrolly and win.scrolly[1]) or 1,
        topfill = 0,
        leftcol = math.max(0, scrollx - 1),
        skipcol = (win.opts.wrap and ((win.scrolly and win.scrolly[2]) or 0)) or 0
    }
end

function Builtins.winrestview(dict, ...)
    if select("#", ...) > 0 or type(dict) ~= "table" then
        error(Error(118, "winrestview"):toString())
    end

    local win = windows[curwin]
    local linecnt = win.buffer:line_count(true)
    if linecnt < 1 then linecnt = 1 end

    if dict.lnum ~= nil or dict.col ~= nil then
        local lnum = dict.lnum or win.cursory
        local col = dict.col or (win.cursorx - 1)
        win:_set_cursor_raw(lnum, col + 1)
    end

    if dict.topline ~= nil then
        local tl = dict.topline
        if tl < 1 then tl = 1 end
        if tl > linecnt then tl = linecnt end
        win.scrolly[1] = tl
    end

    if win.opts.wrap then
        if dict.skipcol ~= nil then
            local sc = dict.skipcol
            if sc < 0 then sc = 0 end
            win.scrolly[2] = sc
        end
    end

    if dict.leftcol ~= nil then
        if win.opts.wrap then
            win.scrollx = 0
        else
            local lc = dict.leftcol
            if lc < 0 then lc = 0 end
            win.scrollx = math.max(1, lc + 1)
        end
    end

    if dict.curswant ~= nil then
        local cw = dict.curswant
        if cw == math.huge then
            win._held_vx = math.huge
        else
            if cw < 0 then cw = 0 end
            win._held_vx = math.max(1, cw + 1)
        end
    end

    if win.opts.wrap then
        local _, params = win:_wrap_params()
        win:_wrap_clamp_scroll(params)
    end

    win.need_redraw = true
    need_redraw = true
    return 0
end

function Builtins.expand(str, nosuf, list)
    local raw = tostring(str or "")
    if raw:find("<cfile>", 1, true) then
        local buf = windows[curwin] and windows[curwin].buffer or nil
        raw = raw:gsub("<cfile>", _expand_cfile(buf))
    end

    local expansions = Filesystem.Expand(raw, nosuf)

    if list then
        if type(expansions) == "string" then
            expansions = { expansions }
        end
    else
        if type(expansions) == "table" then
            expansions = table.concat(expansions, "\n")
        end
    end
    return expansions
end

function Builtins.systemlist(cmd, input, keepempty)
    -- TODO: implement properly. ComputerCraft doesn't provide utilities for this so we'll have to write our own
    if type(cmd) == "string" and cmd:sub(1, 3) == "ls " then
        return fs.list(VimFs.abspath(cmd:sub(4)))
    else
        error("systemlist is very limited currently!! Don't understand command: " .. tostring(cmd))
    end
end

-- TODO: These should be properly scheduled in with the parallel api.
-- Currently these do not actually run in parallel, they just run immediately.
-- Need to figure out a way to handle scheduling properly...
local function _invoke_job_cb(cb, ...)
    if type(cb) == "function" then
        local ok, err = pcall(cb, ...)
        if not ok then
            LOG_DEBUG("job callback error: %s", tostring(err))
        end
    elseif type(cb) == "string" then
        local ok, err = pcall(call_vimfunc, cb, ...)
        if not ok then
            LOG_DEBUG("job callback (%s) error: %s", tostring(cb), tostring(err))
        end
    end
end

function Builtins.jobstart(cmd, opts)
    opts = (type(opts) == "table") and opts or {}

    local job_id = _next_job_id
    _next_job_id = _next_job_id + 1

    local textcmd
    if type(cmd) == "table" then
        local parts = {}
        for i = 1, #cmd do
            parts[#parts + 1] = tostring(cmd[i])
        end
        textcmd = table.concat(parts, " ")
    else
        textcmd = tostring(cmd or "")
    end

    local out = {}
    if textcmd ~= "" then
        local ok, lines = pcall(Builtins.systemlist, textcmd)
        if ok and type(lines) == "table" then
            out = lines
        end
    end

    _jobs[job_id] = {
        running = false,
        exit_code = 0,
    }

    _invoke_job_cb(opts.on_stdout, job_id, out, "stdout")
    _invoke_job_cb(opts.on_stderr, job_id, {}, "stderr")
    _invoke_job_cb(opts.on_exit, job_id, 0, "exit")

    return job_id
end

function Builtins.jobstop(id)
    id = tonumber(id)
    if not id or not _jobs[id] then
        return 0
    end
    _jobs[id].running = false
    return 1
end

function Builtins.jobwait(jobs, timeout)
    if type(jobs) ~= "table" then
        return { -3 }
    end

    local out = {}
    for i = 1, #jobs do
        local id = tonumber(jobs[i])
        local job = id and _jobs[id] or nil
        if not job then
            out[i] = -3
        elseif job.running then
            out[i] = -1
        else
            out[i] = job.exit_code or 0
        end
    end
    return out
end

-- Builtins.fnamemodify for ComputerCraft
-- Depends on: shell, fs, optional VimRegex (R) for regex search (see :s/:gs notes).

local function _ensure_dir_trailing(p)
    if p == "/" then return p end
    if fs.isDir(p) and p:sub(-1) ~= "/" then return p .. "/" end
    return p
end

local function _head(p)
    -- Remove single trailing slash (Vim: on a dir name, :h removes only the trailing slash)
    if #p > 1 and p:sub(-1) == "/" then p = p:sub(1, -2) end
    if p == "/" then return "/" end
    local s, e = p:find("/[^/]*$") -- last component including slash
    if not s then
        -- relative single component -> empty; absolute single component -> "/"
        return (p:sub(1, 1) == "/") and "/" or ""
    end
    local h = p:sub(1, s - 1)
    if h == "" then h = "/" end
    return h
end

local function _tail(p)
    if #p > 1 and p:sub(-1) == "/" then p = p:sub(1, -2) end
    if p == "/" then return "" end
    return p:match("([^/]+)$") or ""
end

local function _rootname(p)
    -- Strip last extension; but if basename starts with '.' and has no other dots -> keep.
    local dir, base = p:match("^(.-)/([^/]*)$") -- dir may be ""
    if not base then
        base = p; dir = ""
    end
    if base:sub(1, 1) == "." and not base:find("%.", 2, true) then
        return p                            -- only a leading dot; unchanged
    end
    local cut = base:match("^(.*)%.[^.]+$") -- drop last .ext
    if not cut then return p end
    return (dir ~= "" and (dir .. "/") or "") .. cut
end

local function _extname(p, n)
    n = n or 1
    local base = _tail(p)
    if base:sub(1, 1) == "." and not base:find("%.", 2, true) then return "" end
    local first_dot = base:find("%.")
    if not first_dot then return "" end
    local exts = {}
    for tok in base:sub(first_dot + 1):gmatch("[^%.]+") do table.insert(exts, tok) end
    if #exts == 0 then return "" end
    if n >= #exts then return table.concat(exts, ".") end
    local start = #exts - n + 1
    local out = {}
    for i = start, #exts do out[#out + 1] = exts[i] end
    return table.concat(out, ".")
end

local function _rel_to(base_abs, target_abs)
    base_abs = base_abs:gsub("//+", "/")
    target_abs = target_abs:gsub("//+", "/")
    if target_abs == base_abs then return "." end
    if base_abs ~= "/" then base_abs = base_abs .. "/" end
    if target_abs:sub(1, #base_abs) == base_abs then
        return target_abs:sub(#base_abs + 1)
    end
    return target_abs
end

local function _shell_escape_cc(s)
    -- CC shell tokenizes on whitespace; quoting is sufficient for typical cases.
    if s:find("[\t %(%)]") then
        s = '"' .. s:gsub('"', '\\"') .. '"'
    end
    return s
end

-- Optional: very light regex substitute using your VimRegex module (R).
-- NOTE: This handles *no* backreferences yet. It does delimiter parsing identical to help.
local function _sub_once(text, pat, sub, R)
    if R and R.find then
        local s, e = R.find(text, pat, true) -- case-sensitive by default here
        if s then return (text:sub(1, s - 1) .. sub .. text:sub(e + 1)) end
        return text
    else
        -- literal fallback if VimRegex isn't wired yet
        return text:gsub(pat:gsub("([^%w])", "%%%1"), sub, 1)
    end
end

local function _sub_global(text, pat, sub, R)
    if R and R.find then
        local out, start = text, 1
        while true do
            local s, e = R.find(out:sub(start), pat, true)
            if not s then break end
            s, e = start + s - 1, start + e - 1
            out = out:sub(1, s - 1) .. sub .. out:sub(e + 1)
            start = s + #sub
        end
        return out
    else
        return (text:gsub(pat:gsub("([^%w])", "%%%1"), sub))
    end
end

function Builtins.fnamemodify(fname, mods, R)
    fname = tostring(fname or "")
    mods  = tostring(mods or "")

    -- Special-case: empty fname with :h -> "."
    if fname == "" and mods:match("^:h") then
        return "."
    end

    local i, n = 1, #mods
    local out = fname

    while i <= n do
        if mods:sub(i, i) ~= ":" then
            i = i + 1
            goto continue
        end
        i = i + 1
        local c = mods:sub(i, i) or ""
        i = i + 1

        if c == "p" then
            out = _ensure_dir_trailing(VimFs.abspath(out))
        elseif c == "8" then
            error("8.3 short format not supported on ComputerCraft")
        elseif c == "~" then
            -- no HOME on CC by default; leave unchanged (or wire your own)
        elseif c == "." then
            out = _rel_to(Builtins.getcwd(), VimFs.abspath(out))
        elseif c == "h" then
            out = _head(out)
        elseif c == "t" then
            out = _tail(out)
        elseif c == "r" then
            out = _rootname(out)
        elseif c == "e" then
            -- handle repeats (:e:e)
            local reps = 1
            while mods:sub(i, i) == ":" and mods:sub(i + 1, i + 1) == "e" do
                reps = reps + 1; i = i + 2
            end
            out = _extname(out, reps)
        elseif c == "s" then
            -- :s<d>pat<d>sub<d>
            local d = mods:sub(i, i); i = i + 1
            local j = mods:find(d, i, true); if not j then break end
            local pat = mods:sub(i, j - 1); i = j + 1
            local k = mods:find(d, i, true); if not k then break end
            local sub = mods:sub(i, k - 1); i = k + 1
            out = _sub_once(out, pat, sub, R)
        elseif c == "g" and mods:sub(i, i) == "s" then
            i = i + 1
            local d = mods:sub(i, i); i = i + 1
            local j = mods:find(d, i, true); if not j then break end
            local pat = mods:sub(i, j - 1); i = j + 1
            local k = mods:find(d, i, true); if not k then break end
            local sub = mods:sub(i, k - 1); i = k + 1
            out = _sub_global(out, pat, sub, R)
        elseif c == "S" then
            out = _shell_escape_cc(out)
        end

        ::continue::
    end

    return out:gsub("//+", "/")
end

function Builtins.stdpath(type)
    if type == "config" then
        return ccvim_path .. "/config"
    elseif type == "log" then
        return ccvim_path .. "/log"
    elseif type == "data" then
        return ccvim_path .. "/data"
    else
        error("stdpath: idk what to do with: " .. tostring(type))
    end
end

local has_features = {
    autocmd = true,
    eval = true,
    nvim = true,
    syntax = true,

    ["nvim-0.7"] = true,
    ["nvim-0.8"] = true,
    ["nvim-0.9"] = true,
    ["nvim-0.10"] = true,
}
local has_patches = {
    [1557] = true,
    [279] = true,
    [213] = true,
}
local explicitly_no = {
    amiga = true,
    gui = true,
    gui_running = true,
    mac = true,
    macunix = true,
    wsl = true,
    win32 = true,
    win32unix = true,
}
function Builtins.has(thing)
    if type(thing) ~= "string" then
        return 0
    end
    thing = thing:gsub("^%s+", ""):gsub("%s+$", "")
    if thing:sub(1, 5) == "patch" then
        local num = tonumber(thing:sub(6))
        local ok = (num and has_patches[num]) and 1 or 0
        LOG_DEBUG("has(%s) -> %s", tostring(thing), tostring(ok))
        return ok
    end
    if has_features[thing] then
        return 1
    end
    if explicitly_no[thing] then
        return 0
    end
    LOG_INTERNAL("has", "has(%s) unknown -> 0", tostring(thing))
    return 0
end

function Builtins.hlexists(name)
    return Highlight.GroupExists(name) and 1 or 0
end

local function _hl_name_from_id(id)
    id = tonumber(id) or 0
    if id <= 0 then return "" end
    return Highlight.NameById(id) or ""
end

local function _hl_resolve_link_name(name)
    local cur = tostring(name or "")
    if cur == "" then return "" end

    local seen = {}
    while true do
        if seen[cur] then
            return cur
        end
        seen[cur] = true
        local nxt = Highlight.GetLink(cur)
        if not nxt or nxt == "" then
            return cur
        end
        cur = nxt
    end
end

local function _hl_color_hex(color)
    if color == nil then
        return ""
    end
    local ok, r, g, b = pcall(term.getPaletteColor, color)
    if not ok or type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
        return ""
    end
    if r <= 1 and g <= 1 and b <= 1 then
        r = r * 255
        g = g * 255
        b = b * 255
    end
    return string.format("#%02x%02x%02x", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

function Builtins.hlID(name, ...)
    if select("#", ...) > 0 then
        error(Error(118, "hlID"):toString())
    end
    local hl_name = tostring(name or "")
    if hl_name == "" then return 0 end
    return Highlight.IdByName(hl_name)
end

function Builtins.synID(lnum, col, trans, ...)
    if select("#", ...) > 0 then
        error(Error(118, "synID"):toString())
    end

    local win = windows[curwin]
    local q = _syntax_mod().Query(win, tonumber(lnum) or 0, tonumber(col) or 0)
    local id = q.top_id or 0
    if trans and trans ~= 0 and trans ~= false then
        id = Builtins.synIDtrans(id)
    end
    return id
end

function Builtins.synstack(lnum, col, ...)
    if select("#", ...) > 0 then
        error(Error(118, "synstack"):toString())
    end

    local win = windows[curwin]
    local q = _syntax_mod().Query(win, tonumber(lnum) or 0, tonumber(col) or 0)
    return q.ids or {}
end

function Builtins.synconcealed(lnum, col, ...)
    if select("#", ...) > 0 then
        error(Error(118, "synconcealed"):toString())
    end

    local win = windows[curwin]
    local q = _syntax_mod().Query(win, tonumber(lnum) or 0, tonumber(col) or 0)
    return { q.conceal or 0, q.cchar or "", q.top_id or 0 }
end

function Builtins.synIDtrans(id, ...)
    if select("#", ...) > 0 then
        error(Error(118, "synIDtrans"):toString())
    end

    local name = _hl_name_from_id(id)
    if name == "" then
        return 0
    end
    local resolved = _hl_resolve_link_name(name)
    return Highlight.IdByName(resolved)
end

function Builtins.synIDattr(syn_id, what, mode, ...)
    if select("#", ...) > 0 then
        error(Error(118, "synIDattr"):toString())
    end

    local name = _hl_name_from_id(syn_id)
    if name == "" then
        return ""
    end

    local attr = tostring(what or ""):lower()
    if attr == "name" then
        return name
    end

    local hl = Highlight.For(name)
    local fg = hl[1]
    local bg = hl[2]

    if attr == "fg" or attr == "foreground" then
        return fg or ""
    end
    if attr == "bg" or attr == "background" then
        return bg or ""
    end
    if attr == "fg#" then
        return _hl_color_hex(fg)
    end
    if attr == "bg#" then
        return _hl_color_hex(bg)
    end
    if attr == "sp#" then
        return ""
    end

    if attr == "reverse" or attr == "inverse" then
        local raw = Highlight.RawFor(name) or {}
        return raw[3] == -1 and "1" or ""
    end

    if attr == "bold" or attr == "italic" or attr == "underline" or attr == "undercurl" or attr == "strikethrough" then
        return ""
    end

    return ""
end

-- function({name} [, {arglist} [, {dict}]]) -> Funcref
-- Minimal support needed for option-value-function use cases.
Builtins["function"] = function(name, arglist, _dict)
    local fname
    if type(name) == "function" then
        fname = funcref_name_by_fn[name]
    else
        fname = tostring(name or "")
        Runtime = Runtime or loadModule("lib.excmd.runtime")
        local canon = Runtime.CanonicalFunctionName(fname, { state = Runtime._CURRENT_STATE })
        if canon then
            fname = canon
        end
    end
    if type(fname) ~= "string" or fname == "" then
        error(Error(474, "function()"):toString())
    end

    local prefix = {}
    if arglist ~= nil then
        if type(arglist) ~= "table" then
            error(Error(474, "function()"):toString())
        end
        for i = 1, #arglist do
            prefix[i] = arglist[i]
        end
    end

    local funcref = function(...)
        local argv = {}
        for i = 1, #prefix do
            argv[#argv + 1] = prefix[i]
        end
        local nargs = select("#", ...)
        for i = 1, nargs do
            argv[#argv + 1] = select(i, ...)
        end
        return call_vimfunc(fname, table.unpack(argv))
    end
    register_funcref_name(fname, funcref)
    return funcref
end

Builtins.funcref = function(name, arglist, dict)
    return Builtins["function"](name, arglist, dict)
end

-- type({expr}): 0 number, 1 string, 2 func, 3 list, 4 dict, 5 float, 6 bool, 7 nil
function Builtins.type(expr)
    local t = type(expr)
    if t == "number" then
        return 0
    elseif t == "string" then
        return 1
    elseif t == "function" then
        return 2
    elseif t == "boolean" then
        return 6
    elseif t == "nil" then
        return 7
    elseif t == "table" then
        local mt = getmetatable(expr)
        if mt and mt.__vimxpr_kind == "list" then
            return 3
        end
        if mt and mt.__vimxpr_kind == "dict" then
            return 4
        end
        -- treat as list if only numeric keys, else dict
        local is_list = true
        for k, _ in pairs(expr) do
            if type(k) ~= "number" then
                is_list = false
                break
            end
        end
        return is_list and 3 or 4
    end
    return 0
end

function Builtins.getpos(expr)
    if expr == "." then
        return { 0, windows[curwin].cursory, windows[curwin].cursorx, 0 } -- TODO: 'virtualedit'
    elseif expr == "$" then
        return { 0, windows[curwin].buffer:line_count(true), 1, 0 }
    else
        LOG_INTERNAL("unimplemented", "Builtins.getpos: unhandled expr %s", (expr or "<<nil>>"))
    end

    return { 0, 0, 0, 0 }
end

function Builtins.line(expr, winid)
    local prev_curwin
    if winid then
        local win = resolve_win(winid)
        if not win then return 0 end
        prev_curwin = curwin
        curwin = win.winnr
    end

    local rv = Builtins.getpos(expr)

    if winid then
        curwin = prev_curwin
    end

    return rv[2]
end

function Builtins.charcol(expr, winid)
    local prev_curwin
    if winid then
        local win = resolve_win(winid)
        if not win then return 0 end
        prev_curwin = curwin
        curwin = win.winnr
    end

    local rv = Builtins.getpos(expr)

    if winid then
        curwin = prev_curwin
    end

    return rv[3]
end

function Builtins.winline(...)
    if select("#", ...) > 0 then
        error(Error(118, "winline"):toString())
    end

    local win = windows[curwin]
    if not win then
        return 0
    end

    local top = (win.scrolly and win.scrolly[1]) or 1
    local wrap_off = (win.scrolly and win.scrolly[2]) or 0
    local row = (tonumber(win.cursory) or 1) - top + 1 - wrap_off
    if row < 1 then
        row = 1
    end
    return math.floor(row)
end

-- Minimal getline({lnum} [, {end}]).
-- Supports ".", "$", and numeric line numbers.
function Builtins.getline(expr, last)
    local win = windows[curwin]
    local lines = win.buffer:lines_ref(true)
    local line_count = #lines

    local function resolve_lnum(v, fallback)
        if v == nil then
            return fallback
        end
        if type(v) == "string" then
            if v == "." then
                return win.cursory or fallback
            elseif v == "$" then
                return line_count
            elseif v:match("^%d+$") then
                return tonumber(v)
            end
            return fallback
        end
        if type(v) == "number" then
            return math.floor(v)
        end
        return fallback
    end

    local lnum = resolve_lnum(expr, win.cursory or 1)
    if last ~= nil then
        local end_lnum = resolve_lnum(last, lnum)
        if lnum > end_lnum then
            return {}
        end
        local start_lnum = math.max(1, lnum)
        local stop_lnum = math.min(line_count, end_lnum)
        if start_lnum > stop_lnum then
            return {}
        end
        local out = {}
        for i = start_lnum, stop_lnum do
            out[#out + 1] = lines[i] or ""
        end
        return out
    end

    if lnum < 1 or lnum > line_count then
        return ""
    end
    return lines[lnum] or ""
end

function Builtins.setline(lnum, text, ...)
    if select("#", ...) > 0 then
        error(Error(118, "setline"):toString())
    end

    local win = windows[curwin]
    local buf = win.buffer
    local lines = buf:lines_ref(true)
    local line_count = #lines

    local function resolve_lnum(v, fallback)
        if v == nil then
            return fallback
        end
        if type(v) == "string" then
            if v == "." then
                return win.cursory or fallback
            elseif v == "$" then
                return line_count
            elseif v:match("^%d+$") then
                return tonumber(v)
            end
            return fallback
        end
        if type(v) == "number" then
            return math.floor(v)
        end
        return fallback
    end

    local target = resolve_lnum(lnum, win.cursory or 1)
    if target < 1 or target > line_count + 1 then
        return 1
    end

    local replacement = {}
    if type(text) == "table" and not text.__call then
        if #text == 0 then
            return 0
        end
        for i = 1, #text do
            local item = text[i]
            if type(item) == "string" then
                replacement[i] = item
            else
                replacement[i] = vim_string(item)
            end
        end
    else
        if type(text) == "string" then
            replacement[1] = text
        else
            replacement[1] = vim_string(text)
        end
    end

    local start0 = target - 1
    local stop0 = math.min(line_count, start0 + #replacement)
    buf:set_lines(start0, stop0, false, replacement)
    win.need_redraw = true
    need_redraw = true
    return 0
end

-- add(list, item): append item to list and return the list (mutates in place)
function Builtins.add(lst, item, ...)
    if select('#', ...) > 0 then
        error(Error(118, 'add'):toString())
    end
    if type(lst) ~= 'table' then
        error('add(): expected List')
    end
    lst[#lst + 1] = item
    return lst
end

-- strlen(x): return byte length of stringified value (ASCII OK)
local function _glob_collect(pattern)
    return Filesystem.ExpandWildcards(pattern) or {}
end

local function _split_path_parts(path)
    local parts = {}
    for seg in tostring(path or ""):gmatch("[^/]+") do
        parts[#parts + 1] = seg
    end
    return parts
end

local function _relpath_from_cwd(abs_target)
    local cwd = _abs_path(".")
    local target = _abs_path(abs_target)
    if cwd == target then
        return "."
    end
    if cwd ~= "/" and target:sub(1, #cwd + 1) == cwd .. "/" then
        return target:sub(#cwd + 2)
    end

    local cwd_parts = _split_path_parts(cwd)
    local tgt_parts = _split_path_parts(target)
    local i = 1
    while i <= #cwd_parts and i <= #tgt_parts and cwd_parts[i] == tgt_parts[i] do
        i = i + 1
    end

    local out = {}
    for _ = i, #cwd_parts do
        out[#out + 1] = ".."
    end
    for j = i, #tgt_parts do
        out[#out + 1] = tgt_parts[j]
    end
    if #out == 0 then
        return "."
    end
    return table.concat(out, "/")
end

local function _glob_expr_is_absolute(expr)
    local e = tostring(expr or "")
    if e == "" then
        return false
    end
    if e:sub(1, 1) == "/" then
        return true
    end
    if e:match("^%a:[/\\]") then
        return true
    end
    if e:match("^%a[%w+.-]*://") then
        return true
    end
    if e:sub(1, 1) == "~" then
        return true
    end
    return false
end

local function _glob_matches_for_relative_expr(expr, matches)
    local e = tostring(expr or "")
    if _glob_expr_is_absolute(e) then
        return matches
    end

    local out = {}
    local keep_dot_slash = e:sub(1, 2) == "./"
    for i = 1, #matches do
        local rel = _relpath_from_cwd(matches[i])
        if keep_dot_slash and rel ~= "." and rel:sub(1, 2) ~= "./" and rel:sub(1, 3) ~= "../" then
            rel = "./" .. rel
        end
        out[#out + 1] = rel
    end
    return out
end

local VIMXPR_LIST_MT = { __vimxpr_kind = "list" }

local function _mark_vim_list(tbl)
    if type(tbl) ~= "table" then
        return tbl
    end
    local mt = getmetatable(tbl)
    if mt and mt.__vimxpr_kind == "list" then
        return tbl
    end
    return setmetatable(tbl, VIMXPR_LIST_MT)
end

local function _glob_return(matches, want_list)
    if want_list then
        return _mark_vim_list(matches)
    end
    return table.concat(matches, "\n")
end

-- glob({expr} [, {nosuf} [, {list} [, {allinks}]]])
-- We ignore {nosuf} and {allinks} in this runtime; return list when requested, else newline-joined string.
function Builtins.glob(expr, nosuf, list, alllinks)
    local pat = tostring(expr or "")
    local want_list = list and list ~= 0 and list ~= false
    local matches = _glob_collect(pat)
    matches = _glob_matches_for_relative_expr(pat, matches)
    return _glob_return(matches, want_list)
end

-- globpath({path}, {expr} [, {nosuf} [, {list} [, {allinks}]]])
-- {path} is comma-separated list of base dirs. Returns first-match order across paths.
function Builtins.globpath(path, expr, nosuf, list, alllinks)
    local paths = {}
    for p in tostring(path or ""):gmatch("([^,]+)") do
        local trimmed = p:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            paths[#paths + 1] = trimmed
        end
    end

    local pat = tostring(expr or "")
    local want_list = list and list ~= 0 and list ~= false

    local matches = {}
    for _, base in ipairs(paths) do
        local pref = base
        if pref ~= "" and pref:sub(-1) ~= "/" then
            pref = pref .. "/"
        end
        local found = _glob_collect(pref .. pat)
        for _, m in ipairs(found) do
            matches[#matches + 1] = m
        end
    end

    return _glob_return(matches, want_list)
end
function Builtins.strlen(x, ...)
    if select("#", ...) > 0 then
        error(Error(118, "strlen"):toString())
    end
    if x == nil then return 0 end
    local s = (type(x) == "string") and x or tostring(x)
    return #s
end

-- stridx({haystack}, {needle} [, {start}]): return 0-based byte index, or -1.
function Builtins.stridx(haystack, needle, start, ...)
    if select("#", ...) > 0 then
        error(Error(118, "stridx"):toString())
    end

    local h = tostring(haystack or "")
    local n = tostring(needle or "")

    if start == nil then
        if n == "" then return 0 end
        local pos = h:find(n, 1, true)
        return pos and (pos - 1) or -1
    end

    local st = tonumber(start) or 0
    st = math.floor(st)
    if st < 0 then
        st = 0
    else
        -- With explicit {start}, Vim returns -1 when start is at/after end.
        if st >= #h then return -1 end
    end

    if n == "" then
        return st
    end

    local pos = h:find(n, st + 1, true)
    return pos and (pos - 1) or -1
end

-- exists({name}): support for internal scopes, $ENV and *FuncName
function Builtins.exists(expr)
    Runtime = Runtime or loadModule("lib.excmd.runtime")

    local function expand_curly_name(raw)
        if type(raw) ~= "string" then return raw end
        if not raw:find("{", 1, true) then return raw end

        local out = {}
        local i, n = 1, #raw
        while i <= n do
            local ch = raw:sub(i, i)
            if ch ~= "{" then
                out[#out + 1] = ch
                i = i + 1
            else
                local depth = 1
                local j = i + 1
                local in_s, in_d, esc = false, false, false
                while j <= n do
                    local c = raw:sub(j, j)
                    if in_s then
                        if c == "'" then
                            if raw:sub(j + 1, j + 1) == "'" then
                                j = j + 1
                            else
                                in_s = false
                            end
                        end
                    elseif in_d then
                        if esc then
                            esc = false
                        elseif c == "\\" then
                            esc = true
                        elseif c == "\"" then
                            in_d = false
                        end
                    else
                        if c == "'" then
                            in_s = true
                        elseif c == "\"" then
                            in_d = true
                        elseif c == "{" then
                            depth = depth + 1
                        elseif c == "}" then
                            depth = depth - 1
                            if depth == 0 then break end
                        end
                    end
                    j = j + 1
                end
                if depth ~= 0 then
                    return Error(0, "Unterminated { in variable name")
                end
                local inner = raw:sub(i + 1, j - 1)
                local ok, val = Runtime.EvalExpression(inner, {
                    state = Runtime._CURRENT_STATE,
                    ctrl = Runtime._CURRENT_CTRL,
                })
                if not ok then return val end
                out[#out + 1] = val == nil and "" or tostring(val)
                i = j + 1
            end
        end
        return table.concat(out)
    end

    local s = tostring(expr or "")
    if s:find("{", 1, true) then
        local expanded = expand_curly_name(s)
        if Error.IsError(expanded) then
            LOG_DEBUG("exists() curly expansion failed: %s", expanded:toString())
        elseif type(expanded) == "string" then
            s = expanded
        end
    end

    local scoped = s:match("^([gslavbtw]):")
    if scoped and (s:find("[", 1, true) or s:find(".", 1, true)) then
        local ok, val = Runtime.EvalExpression(s, {
            state = Runtime._CURRENT_STATE,
            ctrl = Runtime._CURRENT_CTRL,
        })
        if not ok then
            return 0
        end
        return (val ~= nil) and 1 or 0
    end

    if s:sub(1, 2) == "g:" then
        local key = s:sub(3)
        return (scopes._g[key] ~= nil) and 1 or 0
    elseif s:sub(1, 2) == "v:" then
        local key = s:sub(3)
        return (scopes._v[key] ~= nil) and 1 or 0
    elseif s:sub(1, 2) == "s:" then
        local key = s:sub(3)
        local st = Runtime._CURRENT_STATE
        if st and st.s then
            local ok = (st.s[key] ~= nil) and 1 or 0
            if key == "vimentered" then
                LOG_DEBUG("exists(s:vimentered) state=%s val=%s -> %s", tostring(st), tostring(st.s[key]),
                    tostring(ok))
            end
            return ok
        end
        if key == "vimentered" then
            LOG_DEBUG("exists(s:vimentered) state=nil -> 0")
        end
        return 0
    elseif s:sub(1, 2) == "b:" then
        local key = s:sub(3)
        return (scopes.b[key] ~= nil) and 1 or 0
    elseif s:sub(1, 2) == "w:" then
        local key = s:sub(3)
        return (scopes.w[key] ~= nil) and 1 or 0
    elseif s:sub(1, 2) == "t:" then
        local key = s:sub(3)
        return (scopes.t[key] ~= nil) and 1 or 0
    elseif s:sub(1, 2) == "l:" then
        local key = s:sub(3)
        local st = Runtime._CURRENT_STATE
        local frames = st and st.frames
        if frames then
            for i = #frames, 1, -1 do
                if frames[i].kind == "func" then
                    return (frames[i].l[key] ~= nil) and 1 or 0
                end
            end
        end
        return 0
    elseif s:sub(1, 2) == "a:" then
        local key = s:sub(3)
        local st = Runtime._CURRENT_STATE
        local frames = st and st.frames
        if frames then
            for i = #frames, 1, -1 do
                if frames[i].kind == "func" then
                    return (frames[i].a[key] ~= nil) and 1 or 0
                end
            end
        end
        return 0
    elseif s:sub(1, 1) == "$" then
        local key = s:sub(2)
        EnvVars = EnvVars or loadModule("lib.envvars")
        return EnvVars.exists(key) and 1 or 0
    elseif s:sub(1, 1) == "*" then
        local fname = s:sub(2)
        if Builtins[fname] ~= nil then return 1 end
        Runtime = Runtime or loadModule("lib.excmd.runtime")
        local def = Runtime.ResolveFunctionDef(fname, { state = Runtime._CURRENT_STATE })
        if def then return 1 end
        local gdef = Runtime.ResolveFunctionDef("g:" .. fname, { state = Runtime._CURRENT_STATE })
        if gdef then return 1 end
        return 0
    end
    -- Bare variable name: check function-local first, then global scope.
    Runtime = Runtime or loadModule("lib.excmd.runtime")
    local st = Runtime._CURRENT_STATE
    local frames = st and st.frames
    if frames then
        for i = #frames, 1, -1 do
            if frames[i].kind == "func" then
                return (frames[i].l[s] ~= nil) and 1 or 0
            end
        end
    end
    return (scopes._g[s] ~= nil) and 1 or 0
end

-- did_filetype(): true if filetype was set by detection (or already set)
function Builtins.did_filetype()
    local bnr = (windows[curwin] and windows[curwin].buffer and windows[curwin].buffer.bufnr) or 0
    local bt = scopes._b_by_buf[bnr]
    if bt and bt.did_filetype then
        return 1
    end
    local ft = options.get("filetype", nil, windows[curwin] and windows[curwin].buffer or nil)
    if ft ~= nil and ft ~= "" then
        return 1
    end
    return 0
end

-- search({pattern} [, {flags} [, {stopline} [, {timeout} [, {skip}]]]])
function Builtins.search(pattern, flags, stopline, timeout, skip, ...)
    if select("#", ...) > 0 then
        error(Error(118, "search"):toString())
    end

    local win = windows[curwin]
    local buf = win and win.buffer
    if not win or not buf then
        return 0
    end

    local lines = buf:lines_ref(true)
    if #lines == 0 then
        lines = { "" }
    end

    local pat = tostring(pattern or "")
    if pat == "" then
        return 0
    end

    local fl = tostring(flags or "")
    local backward = fl:find("b", 1, true) ~= nil
    local accept_cursor = fl:find("c", 1, true) ~= nil
    local move_to_end = fl:find("e", 1, true) ~= nil
    local no_move = fl:find("n", 1, true) ~= nil
    local want_submatch = fl:find("p", 1, true) ~= nil
    local start_at_cursor = fl:find("z", 1, true) ~= nil

    local want_wrap
    local has_w = fl:find("w", 1, true) ~= nil
    local has_W = fl:find("W", 1, true) ~= nil
    if has_w then
        want_wrap = true
    elseif has_W then
        want_wrap = false
    else
        local ok, rv = pcall(function()
            return options.get("wrapscan")
        end)
        if ok then
            want_wrap = not not rv
        else
            want_wrap = true
        end
    end

    local line_count = #lines
    local stop = tonumber(stopline or 0) or 0
    stop = math.floor(stop)
    if stop < 0 then
        stop = 0
    end
    if stop > line_count then
        stop = line_count
    end
    if stop > 0 then
        want_wrap = false
    end

    local timeout_ms = tonumber(timeout or 0) or 0
    timeout_ms = math.floor(timeout_ms)
    if timeout_ms < 0 then
        timeout_ms = 0
    end
    local started_at = (timeout_ms > 0) and os.clock() or nil
    local function timed_out()
        if timeout_ms <= 0 then
            return false
        end
        return (os.clock() - started_at) * 1000 > timeout_ms
    end

    local compiled, case_sensitive, c_err = _prepare_match_pattern(pat)
    if not compiled then
        error("search(): pattern compile failed: " .. tostring(c_err))
    end

    local line_starts = {}
    local abs_pos = 1
    for i = 1, line_count do
        line_starts[i] = abs_pos
        abs_pos = abs_pos + #(lines[i] or "")
        if i < line_count then
            abs_pos = abs_pos + 1
        end
    end
    local text = table.concat(lines, "\n")
    local text_len = #text

    local function abs_to_line_col(abs_idx)
        if abs_idx < 1 then
            abs_idx = 1
        elseif abs_idx > text_len + 1 then
            abs_idx = text_len + 1
        end

        local lo, hi = 1, line_count
        local found = 1
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if line_starts[mid] <= abs_idx then
                found = mid
                lo = mid + 1
            else
                hi = mid - 1
            end
        end

        local line_text = lines[found] or ""
        local byte_col1 = abs_idx - line_starts[found] + 1
        local byte_max_col = #line_text + 1
        if byte_col1 < 1 then
            byte_col1 = 1
        elseif byte_col1 > byte_max_col then
            byte_col1 = byte_max_col
        end
        local col1 = buf:str_col_from_byte(line_text, byte_col1, true)
        return found, col1
    end

    local cur_lnum = math.floor(tonumber(win.cursory) or 1)
    if cur_lnum < 1 then
        cur_lnum = 1
    elseif cur_lnum > line_count then
        cur_lnum = line_count
    end
    local cur_col = math.floor(tonumber(win.cursorx) or 1)
    local cur_max_col = buf:line_len(cur_lnum, true) + 1
    if cur_col < 1 then
        cur_col = 1
    elseif cur_col > cur_max_col then
        cur_col = cur_max_col
    end
    local cur_byte_col = buf:line_byte_index(cur_lnum, cur_col, true, true)
    local cur_abs = line_starts[cur_lnum] + cur_byte_col - 1

    local matches = {}
    -- For ordinary patterns, search each line independently so ^/$ anchor to
    -- line boundaries like Vim's search(). Fall back to full-buffer matching
    -- when the pattern explicitly includes newline-aware atoms.
    local newline_aware = pat:find("\\_", 1, true) ~= nil
        or pat:find("\\n", 1, true) ~= nil

    if not newline_aware then
        for lnum = 1, line_count do
            local line_text = lines[lnum] or ""
            local from = 1
            local max_from = #line_text + 1
            while from <= max_from do
                if timed_out() then
                    return 0
                end
                local s, e = VimRegex.find_compiled(line_text, compiled, case_sensitive, from)
                if not s then
                    break
                end
                local ee = e or s
                matches[#matches + 1] = {
                    s = line_starts[lnum] + s - 1,
                    e = line_starts[lnum] + ee - 1,
                }
                local next_from
                if ee < s then
                    next_from = s + 1
                else
                    next_from = ee + 1
                end
                if next_from <= from then
                    next_from = from + 1
                end
                from = next_from
            end
        end
    else
        local from = 1
        while from <= text_len + 1 do
            if timed_out() then
                return 0
            end
            local s, e = VimRegex.find_compiled(text, compiled, case_sensitive, from)
            if not s then
                break
            end
            matches[#matches + 1] = { s = s, e = e or s }
            local next_from = s + 1
            if next_from <= from then
                next_from = from + 1
            end
            from = next_from
        end
    end

    local skip_kind = type(skip)
    local check_skip = (skip_kind == "function") or (skip_kind == "string" and skip ~= "")
    local function should_skip(candidate_line, candidate_col)
        if not check_skip then
            return false, nil
        end

        local save_line = win.cursory
        local save_col = win.cursorx
        _search_set_cursor(win, candidate_line, candidate_col)

        local ok, rv
        if skip_kind == "function" then
            ok, rv = pcall(skip)
            if not ok then
                _search_set_cursor(win, save_line, save_col)
                return nil, rv
            end
        else
            local rt_ok, eval_ok, eval_rv = pcall(function()
                Runtime = Runtime or loadModule("lib.excmd.runtime")
                return Runtime.EvalExpression(skip, {
                    state = Runtime._CURRENT_STATE,
                    ctrl = Runtime._CURRENT_CTRL,
                })
            end)
            if not rt_ok then
                _search_set_cursor(win, save_line, save_col)
                return nil, eval_ok
            end
            if not eval_ok then
                _search_set_cursor(win, save_line, save_col)
                return nil, eval_rv
            end
            ok, rv = true, eval_rv
        end

        _search_set_cursor(win, save_line, save_col)
        return _search_truthy(rv), nil
    end

    local selected = nil
    local function pick_candidate(idx)
        local m = matches[idx]
        local match_lnum, match_col = abs_to_line_col(m.s)
        local skip_it, skip_err = should_skip(match_lnum, match_col)
        if skip_err ~= nil then
            return nil, skip_err
        end
        if skip_it then
            return false, nil
        end
        selected = {
            s = m.s,
            e = m.e,
            line = match_lnum,
            col = match_col,
        }
        return true, nil
    end

    if not backward then
        local lower = cur_abs + (accept_cursor and 0 or 1)

        for i = 1, #matches do
            if timed_out() then
                return 0
            end
            local m = matches[i]
            if m.s >= lower then
                local lnum = abs_to_line_col(m.s)
                if stop > 0 and lnum > stop then
                    break
                end
                local ok, err = pick_candidate(i)
                if err ~= nil then
                    return -1
                end
                if ok then
                    break
                end
            end
        end

        if not selected and want_wrap and stop == 0 then
            for i = 1, #matches do
                if timed_out() then
                    return 0
                end
                local m = matches[i]
                if m.s >= lower then
                    break
                end
                local ok, err = pick_candidate(i)
                if err ~= nil then
                    return -1
                end
                if ok then
                    break
                end
            end
        end
    else
        local upper
        if start_at_cursor then
            upper = line_starts[cur_lnum]
        else
            upper = cur_abs + (accept_cursor and 1 or 0)
        end
        local lower = 1
        if stop > 0 then
            lower = line_starts[stop]
        end

        for i = #matches, 1, -1 do
            if timed_out() then
                return 0
            end
            local m = matches[i]
            if m.s >= upper then
                -- continue
            elseif m.s < lower then
                break
            else
                local ok, err = pick_candidate(i)
                if err ~= nil then
                    return -1
                end
                if ok then
                    break
                end
            end
        end

        if not selected and want_wrap and stop == 0 then
            local wrap_lower = start_at_cursor and line_starts[cur_lnum] or (cur_abs + 1)
            for i = #matches, 1, -1 do
                if timed_out() then
                    return 0
                end
                local m = matches[i]
                if m.s < wrap_lower then
                    break
                end
                local ok, err = pick_candidate(i)
                if err ~= nil then
                    return -1
                end
                if ok then
                    break
                end
            end
        end
    end

    if not selected then
        return 0
    end

    local rv
    if want_submatch then
        rv = _search_submatch_nr(text, compiled, case_sensitive, selected.s, selected.e)
    else
        rv = selected.line
    end

    if not no_move then
        local dest_lnum = selected.line
        local dest_col = selected.col
        if move_to_end then
            local end_abs = selected.e
            if end_abs < selected.s then
                end_abs = selected.s
            end
            dest_lnum, dest_col = abs_to_line_col(end_abs)
        end
        _search_set_cursor(win, dest_lnum, dest_col)
        win.need_redraw = true
        need_redraw = true
    end

    return rv
end

function Builtins.getcwd(winnr, tabnr)
    local tabpage = tabpages[(tabnr == 0 or not tabnr) and curtp or tabnr]
    local window
    if winnr == 0 or not winnr then
        window = windows[curwin]
    else
        if windows[winnr].tabpagenr == tabpage.tabnr then
            window = windows[winnr]
        elseif #tabpage.windows >= winnr then
            window = tabpage.windows[winnr]
        else
            error(Error(5002))
        end
    end

    local p = window.curdir or tabpage.curdir
    if p then
        return _abs_path(p)
    end

    local cwd = tostring(shell.dir() or "")
    if cwd == "" then
        cwd = "/"
    elseif cwd:sub(1, 1) ~= "/" then
        cwd = "/" .. cwd
    end
    return VimFs.normalize(cwd, { expand_env = false })
end

function Builtins.findfile(name, path, count)
    local win = windows[curwin]
    local buf = win and win.buffer or nil
    local target = tostring(name or "")
    if target == "" then return "" end

    local path_spec
    if path == nil then
        path_spec = (buf and options.get("path", nil, buf)) or ".,,"
    else
        path_spec = tostring(path)
    end

    local matches = _resolve_with_includeexpr(target, path_spec, buf, false, true)
    local idx = tonumber(count or 1) or 1
    idx = math.floor(idx)
    if idx < 1 then idx = 1 end
    return matches[idx] or ""
end

function Builtins.finddir(name, path, count)
    local win = windows[curwin]
    local buf = win and win.buffer or nil
    local target = tostring(name or "")
    if target == "" then return "" end

    local path_spec
    if path == nil then
        path_spec = (buf and options.get("path", nil, buf)) or ".,,"
    else
        path_spec = tostring(path)
    end

    local matches = _resolve_with_includeexpr(target, path_spec, buf, true, false)
    local idx = tonumber(count or 1) or 1
    idx = math.floor(idx)
    if idx < 1 then idx = 1 end
    return matches[idx] or ""
end

-- TODO: deferred flags
function Builtins.mkdir(name, flags, _)
    local raw = tostring(name or "")
    if raw == "" then
        return 0
    end

    local path = _abs_path(raw)
    local fl = tostring(flags or "")
    local parents = fl:find("p", 1, true) ~= nil

    if fs.exists(path) then
        if fs.isDir(path) then
            return parents and 1 or 0
        end
        return 0
    end

    if not parents then
        local parent = _dir_of(path)
        if not fs.exists(parent) or not fs.isDir(parent) then
            return 0
        end
    end

    local ok = pcall(fs.makeDir, path)
    if not ok then
        return 0
    end

    if fs.exists(path) and fs.isDir(path) then
        return 1
    end
    return 0
end

function Builtins.isdirectory(path)
    local s = tostring(path or "")
    if s == "" then return 0 end
    local p = _abs_path(s)
    local ok = fs.isDir(p) and 1 or 0
    if s == "." then
        LOG_DEBUG("isdirectory('.') resolved=%s -> %s", tostring(p), tostring(ok))
    end
    return ok
end

-- filereadable({file}) -> 1 if exists and readable, else 0
function Builtins.filereadable(file)
    local fname = tostring(file or "")
    if fname == "" then return 0 end
    local p = _abs_path(fname)
    if not fs.exists(p) or fs.isDir(p) then
        return 0
    end
    local h = fs.open(p, "r")
    if h then
        h.close(); return 1
    end
    return 0
end

local function _split_readfile_lines(text, keep_trailing_empty)
    if text == "" then
        return {}
    end
    local out = {}
    local start = 1
    while true do
        local nl = text:find("\n", start, true)
        if not nl then
            local tail = text:sub(start)
            if tail ~= "" or keep_trailing_empty then
                out[#out + 1] = tail
            end
            break
        end
        out[#out + 1] = text:sub(start, nl - 1)
        start = nl + 1
    end
    return out
end

local function _readfile_apply_max(lines, max_arg)
    if max_arg == nil then
        return lines
    end
    local n = tonumber(max_arg) or 0
    if n >= 0 then
        n = math.floor(n)
    else
        n = math.ceil(n)
    end
    if n == 0 then
        return {}
    end
    if n > 0 then
        if #lines <= n then
            return lines
        end
        local out = {}
        for i = 1, n do
            out[i] = lines[i]
        end
        return out
    end
    local want = -n
    if #lines <= want then
        return lines
    end
    local out = {}
    local start = #lines - want + 1
    local j = 1
    for i = start, #lines do
        out[j] = lines[i]
        j = j + 1
    end
    return out
end

-- readfile({fname} [, {type} [, {max}]]) -> List of lines
function Builtins.readfile(fname, kind, max)
    local raw = tostring(fname or "")
    local path = _abs_path(raw)

    local handle
    do
        local ok_rb, h_rb = pcall(fs.open, path, "rb")
        if ok_rb and h_rb then
            handle = h_rb
        else
            local ok_r, h_r = pcall(fs.open, path, "r")
            if ok_r and h_r then
                handle = h_r
            end
        end
    end

    if not handle then
        ExMsg = ExMsg or loadModule("lib.excmd.exmsg")
        ExMsg.echoerr(Error(484, raw):toString())
        return {}
    end

    local ok_read, data = pcall(function()
        return handle.readAll and handle.readAll() or ""
    end)
    pcall(function()
        if handle and handle.close then
            handle.close()
        end
    end)

    if not ok_read then
        ExMsg = ExMsg or loadModule("lib.excmd.exmsg")
        ExMsg.echoerr(Error(484, raw):toString())
        return {}
    end

    local mode = tostring(kind or "")
    local binary = mode:find("b", 1, true) ~= nil
    local as_blob = mode:find("B", 1, true) ~= nil
    local text = tostring(data or "")

    if as_blob then
        return text
    end

    text = text:gsub("\0", "\n")
    if not binary then
        -- Strip UTF-8 BOM in text mode.
        if text:sub(1, 3) == "\239\187\191" then
            text = text:sub(4)
        end
        -- In text mode CR before NL is dropped.
        text = text:gsub("\r\n", "\n")
    end

    local lines = _split_readfile_lines(text, binary)
    return _readfile_apply_max(lines, max)
end

local function _json_decode_list_input(expr)
    if type(expr) ~= "table" or expr.__call then
        return nil
    end
    local maxk = 0
    local count = 0
    for k, _ in pairs(expr) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return nil
        end
        if k > maxk then
            maxk = k
        end
        count = count + 1
    end
    if count ~= maxk then
        return nil
    end
    local parts = {}
    for i = 1, #expr do
        parts[i] = tostring(expr[i] or "")
    end
    return table.concat(parts, "\n")
end

-- json_decode({expr}): parse JSON string or readfile()-style list.
function Builtins.json_decode(expr)
    local payload
    if type(expr) == "string" then
        payload = expr
    else
        payload = _json_decode_list_input(expr)
    end
    if payload == nil then
        error(Error(474, "json_decode()"):toString())
    end

    local parser = textutils.unserializeJSON
    local decoded, perr = parser(payload, {
        parse_null = true,
        parse_empty_array = false,
    })
    if decoded == nil then
        local reason = tostring(perr or "json_decode()")
        error(Error(474, reason):toString())
    end
    return decoded
end

-- match({expr}, {pat} [, {start} [, {count}]])
function Builtins.match(expr, pat, start, count)
    local compiled, case_sensitive, c_err = _prepare_match_pattern(pat)
    if not compiled then
        error("match(): pattern compile failed: " .. tostring(c_err))
    end

    local is_list = _is_vim_list_expr(expr)

    start = tonumber(start or 0) or 0
    local want_count = tonumber(count or 0) or 0
    if want_count < 0 then want_count = 0 end

    -- Helper to iterate matches inside a single string starting from absolute start index
    local function nth_match_in_string(str, abs_start, nth)
        if abs_start < 0 then abs_start = 0 end
        local strlen = #str
        if abs_start > strlen then return -1 end

        if nth == 0 then
            -- Fast path: just find first match honoring special start semantics
            -- When nth not given: if start>0 treat substring from start as beginning so ^ matches there.
            local search_text = (abs_start > 0) and str:sub(abs_start + 1) or str
            local s, e
            -- VimRegex.find_compiled returns 1-based indices in search_text
            s, e = VimRegex.find_compiled(search_text, compiled, case_sensitive)
            if not s then return -1 end
            return abs_start + (s - 1)
        end

        -- When nth>0: iterate non-overlapping matches from start of string, ignoring those before abs_start.
        local pos = 1
        local found = 0
        local hay = str
        while pos <= #hay do
            local segment = hay:sub(pos)
            local s, e
            s, e = VimRegex.find_compiled(segment, compiled, case_sensitive)
            if not s then break end
            local abs_s = pos + s - 1
            if abs_s >= abs_start then
                found = found + 1
                if found == nth then
                    return abs_s - 1 -- convert to 0-based byte offset
                end
            end
            -- Advance; guard against zero-length matches
            if e < s then
                pos = pos + s -- move at least one char forward
            else
                pos = pos + e
            end
            pos = pos + 1
        end
        return -1
    end

    if not is_list then
        local str = tostring(expr or "")
        if want_count == 0 then
            local off = nth_match_in_string(str, start, 0)
            return off
        else
            local off = nth_match_in_string(str, start, want_count)
            return off
        end
    end

    -- List handling
    local list = expr
    local len = #list
    -- Adjust start index semantics for list
    if start < 0 then
        start = len + start
        if start < 0 then start = 0 end
    end
    if start >= len then return -1 end

    if want_count == 0 then
        for i = start + 1, len do
            local item = list[i]
            local as_str = tostring(item)
            local s, e = VimRegex.find_compiled(as_str, compiled, case_sensitive)
            if s then
                return i - 1 -- zero-based index of item
            end
        end
        return -1
    else
        local found = 0
        for i = start + 1, len do
            local as_str = tostring(list[i])
            local s, e = VimRegex.find_compiled(as_str, compiled, case_sensitive)
            if s then
                found = found + 1
                if found == want_count then
                    return i - 1
                end
            end
        end
        return -1
    end
end

-- matchstr({expr}, {pat} [, {start} [, {count}]])
function Builtins.matchstr(expr, pat, start, count, ...)
    if select("#", ...) > 0 then
        error(Error(118, "matchstr"):toString())
    end

    local is_list = _is_vim_list_expr(expr)
    local idx = Builtins.match(expr, pat, start, count)
    if idx < 0 then
        return ""
    end

    if is_list then
        return expr[idx + 1]
    end

    local str = tostring(expr or "")
    local compiled, case_sensitive, c_err = _prepare_match_pattern(pat)
    if not compiled then
        error("matchstr(): pattern compile failed: " .. tostring(c_err))
    end

    local segment = str:sub(idx + 1)
    local s, e = VimRegex.find_compiled(segment, compiled, case_sensitive)
    if not s then
        return ""
    end
    return segment:sub(s, e)
end

-- matchstrpos({expr}, {pat} [, {start} [, {count}]])
function Builtins.matchstrpos(expr, pat, start, count, ...)
    if select("#", ...) > 0 then
        error(Error(118, "matchstrpos"):toString())
    end

    local compiled, case_sensitive, c_err = _prepare_match_pattern(pat)
    if not compiled then
        error("matchstrpos(): pattern compile failed: " .. tostring(c_err))
    end

    local is_list = _is_vim_list_expr(expr)
    start = tonumber(start or 0) or 0
    local want_count = tonumber(count or 0) or 0
    if want_count < 0 then want_count = 0 end

    if not is_list then
        local idx = Builtins.match(expr, pat, start, count)
        if idx < 0 then
            return { "", -1, -1 }
        end

        local str = tostring(expr or "")
        local segment = str:sub(idx + 1)
        local s, e = VimRegex.find_compiled(segment, compiled, case_sensitive)
        if not s then
            return { "", -1, -1 }
        end
        local m = segment:sub(s, e)
        local finish = idx + (e - s + 1)
        return { m, idx, finish }
    end

    local list = expr
    local len = #list
    if start < 0 then
        start = len + start
        if start < 0 then start = 0 end
    end
    if start >= len then
        return { "", -1, -1, -1 }
    end

    if want_count == 0 then
        for i = start + 1, len do
            local as_str = tostring(list[i])
            local s, e = VimRegex.find_compiled(as_str, compiled, case_sensitive)
            if s then
                return { as_str:sub(s, e), i - 1, s - 1, e }
            end
        end
        return { "", -1, -1, -1 }
    end

    local found = 0
    for i = start + 1, len do
        local as_str = tostring(list[i])
        local s, e = VimRegex.find_compiled(as_str, compiled, case_sensitive)
        if s then
            found = found + 1
            if found == want_count then
                return { as_str:sub(s, e), i - 1, s - 1, e }
            end
        end
    end
    return { "", -1, -1, -1 }
end

local function _split_trim_default(out)
    -- Vim's split() drops all leading empty items by default.
    while #out > 0 and out[1] == "" do
        table.remove(out, 1)
    end
    -- ...and a single trailing empty item.
    if #out > 0 and out[#out] == "" then
        table.remove(out, #out)
    end
end

local function _split_by_compiled(str, compiled, case_sensitive, keepempty)
    local out = {}
    local n = #str
    local cursor = 1
    local search_from = 1

    while search_from <= n + 1 do
        local segment = str:sub(search_from)
        local s, e = VimRegex.find_compiled(segment, compiled, case_sensitive)
        if not s then break end

        local abs_s = search_from + s - 1
        local abs_e = search_from + e - 1
        local piece = str:sub(cursor, abs_s - 1)
        local matched_len = (e >= s) and (e - s + 1) or 0

        if piece ~= "" or keepempty or matched_len > 0 then
            out[#out + 1] = piece
        end

        cursor = abs_e + 1
        if e < s then
            search_from = abs_s + 1
        else
            search_from = abs_e + 1
        end
    end

    local tail = str:sub(cursor)
    if tail ~= "" or keepempty then
        out[#out + 1] = tail
    end

    if not keepempty then
        _split_trim_default(out)
    end
    return out
end

local function _split_by_pattern(str, pat, keepempty)
    -- Special-case a bare \zs: split into individual characters.
    if pat == "\\zs" then
        local out = {}
        if keepempty then out[#out + 1] = "" end
        for i = 1, #str do
            out[#out + 1] = str:sub(i, i)
            if keepempty then out[#out + 1] = "" end
        end
        return out
    end

    -- Common pattern to keep a separator at the end of each split item.
    if #pat > 3 and pat:sub(-3) == "\\zs" then
        local base = pat:sub(1, -4)
        local compiled_base, case_sensitive_base, base_err = _prepare_match_pattern(base, false)
        if not compiled_base then
            error("split(): pattern compile failed: " .. tostring(base_err))
        end

        local out = {}
        local n = #str
        local cursor = 1
        local search_from = 1

        while search_from <= n + 1 do
            local segment = str:sub(search_from)
            local s, e = VimRegex.find_compiled(segment, compiled_base, case_sensitive_base)
            if not s then break end

            local abs_s = search_from + s - 1
            local abs_e = search_from + e - 1
            local split_pos = abs_e + 1
            local piece = str:sub(cursor, split_pos - 1)

            if piece ~= "" or keepempty then
                out[#out + 1] = piece
            end

            cursor = split_pos
            if e < s then
                search_from = abs_s + 1
            else
                search_from = abs_e + 1
            end
        end

        local tail = str:sub(cursor)
        if tail ~= "" or keepempty then
            out[#out + 1] = tail
        end

        if not keepempty then
            _split_trim_default(out)
        end
        return out
    end

    local compiled, case_sensitive, c_err = _prepare_match_pattern(pat, false)
    if not compiled then
        error("split(): pattern compile failed: " .. tostring(c_err))
    end
    return _split_by_compiled(str, compiled, case_sensitive, keepempty)
end

-- split({string} [, {pattern} [, {keepempty}]])
function Builtins.split(str, pattern, keepempty, ...)
    if select("#", ...) > 0 then
        error(Error(118, "split"):toString())
    end

    local s = tostring(str or "")
    local p = (pattern == nil) and "" or tostring(pattern)

    local keep = false
    if keepempty ~= nil then
        if type(keepempty) == "boolean" then
            keep = keepempty
        else
            keep = (tonumber(keepempty) or 0) ~= 0
        end
    end

    if p == "" then
        p = "\\s\\+"
    end

    return _split_by_pattern(s, p, keep)
end

function Builtins.sign_define(name, dict)
    if type(name) == "string" then
        Sign.define(name, dict)
    elseif type(name) == "table" then
        for i = 1, #name do
            Sign.define(name[i].name, name[i])
        end
    else
        error("Unhandled sign name type: " .. name)
    end
    return 0
end

function Builtins.sign_getdefined(name)
    return Sign.getdefined(name)
end

-- TODO: properly handle utf-8/utf-16
function Builtins.byteidx(expr, nr, utf16)
    return nr
end

function Builtins.sign_undefine(name)
    if name == nil then
        return Sign.undefine(nil)
    elseif type(name) == "string" then
        return Sign.undefine(name)
    elseif type(name) == "table" then
        local rv = {}
        for i = 1, #name do
            local item = name[i]
            local sign_name = (type(item) == "table") and item.name or item
            rv[#rv + 1] = Sign.undefine(sign_name)
        end
        return rv
    else
        error("Unhandled sign name type: " .. name)
    end
end

function Builtins.sign_place(id, group, name, buf, opts)
    return Sign.place(id, group, name, buf, opts)
end

function Builtins.sign_getplaced(buf, dict)
    return Sign.getplaced(buf, dict)
end

function Builtins.sign_jump(id, group, buf)
    return Sign.jump(id, group, buf)
end

function Builtins.sign_placelist(list)
    local out = {}
    for i = 1, #list do
        local item = list[i]
        out[#out + 1] = Sign.place(
            item.id or 0,
            item.group or "",
            item.name,
            item.buffer or 0,
            {
                lnum = item.lnum,
                priority = item.priority,
            }
        )
    end
    return out
end

function Builtins.sign_unplace(group, opts)
    return Sign.unplace(group, opts)
end

function Builtins.sign_unplacelist(list)
    local out = {}
    for i = 1, #list do
        local item = list[i]
        out[#out + 1] = Sign.unplace(item.group or "", {
            buffer = item.buffer,
            id = item.id,
        })
    end
    return out
end

function Builtins.fnameescape(fname)
    local s = tostring(fname or "")
    return (s:gsub("([ \t\r\n\\\"'|%*%?%[%]{}<>`$!#%%])", "\\%1"))
end

function Builtins.escape(str, chars)
    if type(str) ~= "string" then
        str = tostring(str or "")
    end
    if type(chars) ~= "string" then
        error("escape(): expected {chars} as string")
    end
    local function pat_escape(ch)
        return (ch:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
    end
    for ch in chars:gmatch(".") do
        str = str:gsub(pat_escape(ch), "\\" .. ch)
    end
    return str
end

function Builtins.winnr(arg)
    if not arg then
        return curwin
    elseif arg == "$" then
        local tabwins = tabpages[curtp].windows
        return tabwins[#tabwins].winnr
    elseif arg == "#" then
        return 0 -- TODO: previous window tracking
    else
        error("unhandled winnr(): " .. arg)
    end
end

function Builtins.empty(arg)
    if type(arg) == "table" then
        local empty = not next(arg)
        return empty and 1 or 0
    elseif type(arg) == "string" then
        return (arg == "") and 1 or 0
    elseif type(arg) == "number" then
        return arg == 0
    else
        error("Unhandled object for empty: " .. textutils.serialize(arg))
    end
end

-- Resolve common buffer reference argument forms:
-- - Number: bufnr, where 0 is alternate buffer
-- - String: exact buffer name match
local function _resolve_buffer_ref(expr)
    if type(expr) == "number" then
        if expr == 0 then
            local win = windows[curwin]
            local alt = win and win.altbuf
            if type(alt) == "number" then
                return buffers[alt]
            end
            if type(alt) == "table" then
                return alt
            end
            return nil
        end
        return buffers[expr]
    end

    if type(expr) == "string" then
        for _, buf in pairs(buffers) do
            if buf and buf.name == expr then
                return buf
            end
        end
        return nil
    end

    return nil
end

local function _has_uri_scheme(path)
    return type(path) == "string" and path:match("^[%w][%w%+%-%.]*://") ~= nil
end

local function _find_buffer_by_name(name)
    for _, buf in pairs(buffers) do
        if buf and buf.name == name then
            return buf
        end
    end
    return nil
end

local function _buffer_is_loaded(buf)
    return buf ~= nil and buf.loaded == true
end

-- TODO: handle create
function Builtins.bufnr(expr, create)
    if expr == nil or expr == "" or expr == "%" then
        return windows[curwin].buffer.bufnr
    elseif expr == "$" then
        -- Return the highest buffer number
        local max_bufnr = 0
        for bufnr in pairs(buffers) do
            if bufnr > max_bufnr then
                max_bufnr = bufnr
            end
        end
        return max_bufnr
    elseif expr == "#" then
        local alt = _resolve_buffer_ref(0)
        return (alt and alt.bufnr) or -1
    elseif type(expr) == "number" then
        if expr == 0 then
            return windows[curwin].buffer.bufnr
        end
        local buf = _resolve_buffer_ref(expr)
        -- Return the buffer number if it exists, else -1
        return buf and expr or -1
    elseif type(expr) == "string" then
        local buf = _resolve_buffer_ref(expr)
        return (buf and buf.bufnr) or -1
    end
    return -1
end

-- buflisted([expr]): check if buffer exists and is listed
function Builtins.buflisted(expr)
    local buf
    if expr == nil or expr == 0 then
        buf = windows[curwin].buffer
    else
        buf = _resolve_buffer_ref(expr)
    end

    if not buf then
        return 0
    end

    return (buf.opts and buf.opts.buflisted) and 1 or 0
end

-- bufloaded({buf}): check if buffer exists and is loaded
function Builtins.bufloaded(expr)
    local buf = _resolve_buffer_ref(expr)
    if not buf then
        return 0
    end
    return _buffer_is_loaded(buf) and 1 or 0
end

-- bufadd({name}): add/get an (unloaded, unlisted) buffer by name.
function Builtins.bufadd(name)
    name = tostring(name or "")

    if name ~= "" then
        local existing = _find_buffer_by_name(name)
        if existing then
            return existing.bufnr
        end

        if not _has_uri_scheme(name) then
            local abs = VimFs.abspath(name)
            existing = _find_buffer_by_name(abs)
            if existing then
                return existing.bufnr
            end
            name = abs
        end
    end

    local ok, buf = pcall(Buffer, false, false, false)
    if not ok or not buf then
        return 0
    end

    buf.name = name
    buf.lines = {} -- bufadd creates an unloaded buffer
    buf.loaded = false
    buf.state = "hidden"

    return buf.bufnr
end

-- bufload({buf}): ensure an existing buffer is loaded.
function Builtins.bufload(expr)
    local buf = _resolve_buffer_ref(expr)
    if not buf then
        return 0
    end
    if _buffer_is_loaded(buf) then
        return 1
    end
    buf:Load(true)
    return _buffer_is_loaded(buf) and 1 or 0
end

local function _bufname_from_buf(buf)
    if not buf or not buf.name or buf.name == "" then return "" end
    return buf.name
end

local function _alt_buffer()
    return _resolve_buffer_ref(0)
end

local function _bufname_case_sensitive()
    local ic = options.get("ignorecase")
    if Error.IsError(ic) then ic = 0 end
    return not (ic and ic ~= 0)
end

local function _collect_buffers(listed)
    local out = {}
    for _, buf in pairs(buffers) do
        local is_listed = buf and buf.opts and buf.opts.buflisted
        if listed == nil or is_listed == listed then
            out[#out + 1] = buf
        end
    end
    table.sort(out, function(a, b)
        return (a.bufnr or 0) < (b.bufnr or 0)
    end)
    return out
end

local function _select_bufname_match(bufs, pat)
    local case_sensitive = _bufname_case_sensitive()
    local buckets = { full = {}, start = {}, ["end"] = {}, mid = {} }

    for _, buf in ipairs(bufs) do
        local name = buf and buf.name
        if name and name ~= "" then
            local s, e = VimRegex.find(name, pat, case_sensitive)
            if s then
                local cat
                if s == 1 and e == #name then
                    cat = "full"
                elseif s == 1 then
                    cat = "start"
                elseif e == #name then
                    cat = "end"
                else
                    cat = "mid"
                end
                buckets[cat][#buckets[cat] + 1] = name
            end
        end
    end

    local order = { "full", "start", "end", "mid" }
    for _, cat in ipairs(order) do
        local list = buckets[cat]
        if #list > 1 then return "", true end
        if #list == 1 then return list[1], true end
    end

    return nil, false
end

-- bufname([expr]): get buffer name
function Builtins.bufname(expr)
    if expr == nil or expr == "" or expr == "%" then
        return _bufname_from_buf(windows[curwin] and windows[curwin].buffer)
    end

    if type(expr) == "number" then
        if expr == 0 then
            return _bufname_from_buf(_alt_buffer())
        end
        return _bufname_from_buf(buffers[expr])
    end

    if type(expr) == "string" then
        if expr == "#" then
            return _bufname_from_buf(_alt_buffer())
        end

        -- Treat string as file-pattern (magic, cpoptions empty).
        local match, decided = _select_bufname_match(_collect_buffers(true), expr)
        if decided then return match or "" end
        local match2, decided2 = _select_bufname_match(_collect_buffers(false), expr)
        if decided2 then return match2 or "" end
        return ""
    end

    return ""
end

-- ===== Additional builtins for plugin compatibility (netrw, etc.) =====

local function _is_list(t)
    if type(t) ~= "table" then return false end
    local maxk = 0
    local count = 0
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
            return false
        end
        if k > maxk then maxk = k end
        count = count + 1
    end
    return count == maxk
end

local function _register_storage_key(regname)
    if regname == '"' then
        return "unnamed"
    end
    if regname:match("^%a$") then
        return regname:lower()
    end
    if regname:match("^%d$") then
        return tonumber(regname)
    end
    return regname
end

local function _register_entry_to_text(entry)
    if entry == nil then
        return ""
    end
    if type(entry) ~= "table" then
        return tostring(entry)
    end
    local payload = entry[2]
    if type(payload) == "table" then
        return table.concat(payload, "\n")
    end
    return tostring(payload or "")
end

local function _split_lines_for_register(text)
    if text == "" then
        return { "" }
    end
    local out = {}
    local start = 1
    while true do
        local idx = text:find("\n", start, true)
        if not idx then
            out[#out + 1] = text:sub(start)
            break
        end
        out[#out + 1] = text:sub(start, idx - 1)
        start = idx + 1
    end
    return out
end

local function _register_entry_to_lines(entry)
    if entry == nil then
        return {}
    end
    if type(entry) ~= "table" then
        return _split_lines_for_register(tostring(entry))
    end
    local payload = entry[2]
    if type(payload) == "table" then
        local out = {}
        for i = 1, #payload do
            out[#out + 1] = tostring(payload[i] or "")
        end
        return out
    end
    return _split_lines_for_register(tostring(payload or ""))
end

local function _register_mode_from_options(value, options)
    options = tostring(options or "")
    if options:find("[vc]") then
        return "charwise"
    end
    if options:find("[lV]") then
        return "linewise"
    end
    if options:find("b", 1, true) or options:find(string.char(22), 1, true) then
        return "blockwise"
    end

    if type(value) == "table" and _is_list(value) then
        return "linewise"
    end
    if type(value) == "string" and value:sub(-1) == "\n" then
        return "linewise"
    end
    return "charwise"
end

local function _normalize_register_value(value, mode)
    if type(value) == "table" and (not _is_list(value)) then
        local info = value
        if type(info.regcontents) == "table" then
            value = info.regcontents
        elseif type(info.regcontents) == "string" then
            value = info.regcontents
        end
        if type(info.regtype) == "string" and info.regtype ~= "" then
            local prefix = info.regtype:sub(1, 1)
            if prefix == "V" or prefix == "l" then
                mode = "linewise"
            elseif prefix == "b" or prefix == string.char(22) then
                mode = "blockwise"
            else
                mode = "charwise"
            end
        end
    end

    if mode == "linewise" then
        local lines = {}
        if type(value) == "table" and _is_list(value) then
            for i = 1, #value do
                lines[#lines + 1] = tostring(value[i] or "")
            end
        else
            local text = tostring(value or "")
            lines = _split_lines_for_register(text)
            if text:sub(-1) == "\n" and #lines > 0 and lines[#lines] == "" then
                table.remove(lines, #lines)
            end
        end
        return { "linewise", lines }
    end

    if mode == "blockwise" then
        mode = "charwise" -- width tracking not implemented yet
    end
    return { "charwise", tostring(value or "") }
end

function Builtins.setreg(regname, value, options)
    local reg = tostring(regname or "")
    if reg == "" or reg == "@" then
        reg = '"'
    end
    reg = reg:sub(1, 1)

    local opts = tostring(options or "")
    local append = opts:find("a", 1, true) ~= nil
    if reg:match("^%u$") then
        append = true
        reg = reg:lower()
    end

    if reg == "_" then
        return 0
    end

    if reg == "#" then
        local win = windows[curwin]
        local alt = nil
        if type(value) == "number" then
            alt = buffers[value]
        elseif type(value) == "string" then
            if value ~= "" then
                alt = _resolve_buffer_ref(value)
                if not alt then
                    local bufnr = Builtins.bufadd(value)
                    alt = buffers[bufnr]
                end
            end
        elseif type(value) == "table" and type(value.bufnr) == "number" then
            alt = buffers[value.bufnr]
        end
        if win then
            win.altbuf = alt
        end
        registers["#"] = { "charwise", tostring((alt and alt.name) or "") }
        return 0
    end

    local mode = _register_mode_from_options(value, opts)
    local key = _register_storage_key(reg)
    local entry
    if type(value) == "table" and (not _is_list(value)) and type(value.points_to) == "string" then
        local target = value.points_to
        if target == "" or target == "@" then
            target = '"'
        end
        target = target:sub(1, 1)
        entry = registers[_register_storage_key(target)] or { "charwise", "" }
    else
        entry = _normalize_register_value(value, mode)
    end

    if append then
        local prev = registers[key]
        if entry[1] == "linewise" then
            local merged = _register_entry_to_lines(prev)
            local add = entry[2]
            for i = 1, #add do
                merged[#merged + 1] = add[i]
            end
            entry = { "linewise", merged }
        else
            entry = { "charwise", _register_entry_to_text(prev) .. _register_entry_to_text(entry) }
        end
    end

    registers[key] = entry
    if reg == '"' then
        registers.unnamed = entry
    else
        registers.unnamed = entry
    end

    if opts:find("u", 1, true) or opts:find('"', 1, true) then
        registers.unnamed = entry
    end

    return 0
end

local function _macro_register_name(state_key)
    local value = registers[state_key]
    if value == nil then
        return ""
    end
    return tostring(value)
end

-- TODO: Implement these properly once macros are added
function Builtins.reg_recording()
    return _macro_register_name("__recording_register")
end

function Builtins.reg_executing()
    return _macro_register_name("__executing_register")
end

function Builtins.reg_recorded()
    return _macro_register_name("__last_recorded_register")
end

function Builtins.len(x)
    if type(x) == "string" then
        return #x
    elseif type(x) == "table" then
        if _is_list(x) then
            return #x
        end
        local n = 0
        for _ in pairs(x) do n = n + 1 end
        return n
    elseif x == nil then
        return 0
    else
        return #tostring(x)
    end
end

local function _require_dict_for_keys_items(dict)
    if type(dict) ~= "table" then
        error(Error(1206, 1):toString())
    end
    local mt = getmetatable(dict)
    if mt and mt.__vimxpr_kind == "list" then
        error(Error(1206, 1):toString())
    end
    if not (mt and mt.__vimxpr_kind == "dict") then
        local has_non_numeric_key = false
        local has_numeric_key = false
        for k, _ in pairs(dict) do
            if type(k) == "number" and k >= 1 and k % 1 == 0 then
                has_numeric_key = true
            else
                has_non_numeric_key = true
                break
            end
        end
        if not has_non_numeric_key and has_numeric_key then
            error(Error(1206, 1):toString())
        end
    end
end

function Builtins.keys(dict, ...)
    if select("#", ...) > 0 then
        error(Error(118, "keys"):toString())
    end
    _require_dict_for_keys_items(dict)
    local out = {}
    for k, _ in pairs(dict) do
        out[#out + 1] = tostring(k)
    end
    return out
end

function Builtins.keytrans(str, ...)
    if select("#", ...) > 0 then
        error(Error(118, "keytrans"):toString())
    end
    local Key = loadModule("lib.key")
    return Key.keytrans(tostring(str or ""))
end

function Builtins.items(dict, ...)
    if select("#", ...) > 0 then
        error(Error(118, "items"):toString())
    end
    _require_dict_for_keys_items(dict)
    local out = {}
    for k, v in pairs(dict) do
        out[#out + 1] = { tostring(k), v }
    end
    return out
end

function Builtins.has_key(dict, key, ...)
    if select("#", ...) > 0 then
        error(Error(118, "has_key"):toString())
    end
    if type(dict) ~= "table" then return 0 end
    if key == nil then return 0 end
    local k = (type(key) == "string") and key or tostring(key)
    return (dict[k] ~= nil) and 1 or 0
end

local function _vim_truthy(v)
    if type(v) == "boolean" then return v end
    if v == nil then return false end
    if type(v) == "number" then return v ~= 0 end
    if type(v) == "string" then
        local n = tonumber(v)
        if n ~= nil then
            return n ~= 0
        end
        return v ~= ""
    end
    return true
end

local function _hasmapto_modes(mode)
    local raw = tostring(mode or "")
    if raw == "" then
        raw = "nvo"
    end

    local out = {}
    local seen = {}
    local function add(m)
        if seen[m] then return end
        seen[m] = true
        out[#out + 1] = m
    end

    for i = 1, #raw do
        local ch = raw:sub(i, i)
        if ch == "n" then
            add("normal")
        elseif ch == "v" then
            add("visual")
            add("select")
        elseif ch == "x" then
            add("visual")
        elseif ch == "s" then
            add("select")
        elseif ch == "o" then
            add("operator")
        elseif ch == "i" then
            add("insert")
        elseif ch == "l" then
            add("lang")
        elseif ch == "c" then
            add("cmdline")
        elseif ch == "t" then
            add("terminal")
        end
    end

    return out
end

local function _strtoseq_tolerant(str)
    local Key = loadModule("lib.key")
    local seq = {}
    local i, n = 1, #str

    local function append(src)
        for j = 1, #src do
            seq[#seq + 1] = src[j]
        end
    end

    while i <= n do
        local ch = str:sub(i, i)
        if ch ~= "<" then
            local j = str:find("<", i, true) or (n + 1)
            local ok, part = pcall(Key.strtoseq, str:sub(i, j - 1))
            if not ok then
                return nil
            end
            append(part)
            i = j
        else
            local j = str:find(">", i + 1, true)
            if not j then
                local ok, part = pcall(Key.strtoseq, "<lt>")
                if not ok then
                    return nil
                end
                append(part)
                i = i + 1
            else
                local token = str:sub(i, j)
                local ok, part = pcall(Key.strtoseq, token)
                if ok then
                    append(part)
                else
                    local literal = "<lt>" .. str:sub(i + 1, j)
                    local ok2, part2 = pcall(Key.strtoseq, literal)
                    if not ok2 then
                        return nil
                    end
                    append(part2)
                end
                i = j + 1
            end
        end
    end

    return seq
end

function Builtins.hasmapto(what, mode, abbr, ...)
    if select("#", ...) > 0 then
        error(Error(118, "hasmapto"):toString())
    end

    if _vim_truthy(abbr) then
        return 0
    end

    local Command = loadModule("lib.command")
    local modes = _hasmapto_modes(mode)
    if #modes == 0 then
        return 0
    end

    return Command.has_map_to(modes, tostring(what or "")) and 1 or 0
end

function Builtins.mapcheck(name, mode, abbr, ...)
    if select("#", ...) > 0 then
        error(Error(118, "mapcheck"):toString())
    end

    if _vim_truthy(abbr) then
        return ""
    end

    local modes = _hasmapto_modes(mode)
    if #modes == 0 then
        return ""
    end

    local lhs_seq = _strtoseq_tolerant(tostring(name or ""))
    if not lhs_seq then
        return ""
    end

    local Command = loadModule("lib.command")
    return Command.mapcheck(modes, lhs_seq)
end

function Builtins.get(container, key, default)
    if type(container) ~= "table" then return default end
    if key == nil then return default end
    local k = key
    if _is_list(container) and type(k) == "number" then
        -- Vim lists are 0-based; our Lua lists are 1-based.
        k = k + 1
    end
    local v = container[k]
    if v == nil then return default end
    return v
end

function Builtins.index(lst, item, start, ic)
    if type(lst) ~= "table" then return -1 end
    local s = tonumber(start or 0) or 0
    if s < 0 then s = 0 end
    local idx = 0
    for i = 1, #lst do
        if idx >= s then
            local v = lst[i]
            if ic and type(v) == "string" and type(item) == "string" then
                if v:lower() == item:lower() then return idx end
            else
                if v == item then return idx end
            end
        end
        idx = idx + 1
    end
    return -1
end

local function _extend_list(dst, src, idx)
    if type(dst) ~= "table" or type(src) ~= "table" then
        error("extend(): expected List arguments")
    end
    local n = #dst
    local i = tonumber(idx)
    if i == nil then i = n end -- default append (0-based)
    if i < 0 then
        i = n + 1 + i
    end
    if i < 0 then i = 0 end
    if i > n then i = n end
    local pos = i + 1 -- Lua 1-based insertion
    for j = 1, #src do
        table.insert(dst, pos + (j - 1), src[j])
    end
    return dst
end

local function _extend_dict(dst, src, action)
    if type(dst) ~= "table" or type(src) ~= "table" then
        error("extend(): expected Dictionary arguments")
    end
    local act = action or "force"
    if act ~= "force" and act ~= "keep" and act ~= "error" then
        error("extend(): invalid action")
    end
    for k, v in pairs(src) do
        local exists = dst[k] ~= nil
        if exists and act == "keep" then
            -- keep existing
        elseif exists and act == "error" then
            error("extend(): Duplicate key " .. tostring(k))
        else
            dst[k] = v
        end
    end
    return dst
end

-- extend({list1}, {list2}[, idx]) or extend({dict1}, {dict2}[, action])
function Builtins.extend(dst, src, arg)
    if _is_list(dst) and _is_list(src) then
        return _extend_list(dst, src, arg)
    elseif type(dst) == "table" and type(src) == "table" then
        return _extend_dict(dst, src, arg)
    end
    error("extend(): type mismatch")
end

-- extendnew(): like extend() but returns a copy
function Builtins.extendnew(dst, src, arg)
    if type(dst) ~= "table" or type(src) ~= "table" then
        error("extendnew(): expected table arguments")
    end
    local copy = TblUtils.deepcopy(dst)
    return Builtins.extend(copy, src, arg)
end

-- uniq({list}[, {ic}]): in-place removal of adjacent duplicates (list must be sorted first), returns {list}
function Builtins.uniq(lst, ic)
    if type(lst) ~= "table" then
        error("uniq(): expected List")
    end
    local casefold = ic and ic ~= 0 and ic ~= false
    local out = {}
    local last = nil
    for i = 1, #lst do
        local v = lst[i]
        local key = vim_string(v)
        if casefold then
            key = key:lower()
        end
        if key ~= last then
            out[#out + 1] = v
            last = key
        end
    end
    -- mutate in place
    for i = 1, #lst do lst[i] = nil end
    for i = 1, #out do lst[i] = out[i] end
    return lst
end

function Builtins.max(lst)
    if type(lst) ~= "table" then return 0 end
    local m = nil
    for _, v in pairs(lst) do
        if type(v) == "number" then
            if m == nil or v > m then m = v end
        end
    end
    return m or 0
end

local function _copy_table_kind(tbl)
    if type(tbl) ~= "table" then
        return nil
    end
    local mt = getmetatable(tbl)
    if mt and mt.__vimxpr_kind == "list" then
        return "list"
    end
    if mt and mt.__vimxpr_kind == "dict" then
        return "dict"
    end
    return _is_list(tbl) and "list" or "dict"
end

local function _copy_mark_kind(src, dst)
    local mt = getmetatable(src)
    if mt ~= nil then
        return setmetatable(dst, mt)
    end
    return dst
end

local function _copy_shallow_table(tbl)
    local out = {}
    if _copy_table_kind(tbl) == "list" then
        for i = 1, #tbl do
            out[i] = tbl[i]
        end
    else
        for k, v in pairs(tbl) do
            out[k] = v
        end
    end
    return _copy_mark_kind(tbl, out)
end

local function _deepcopy_value(obj, noref_mode, cache, stack, depth)
    if type(obj) ~= "table" then
        return obj
    end

    local next_depth = depth + 1
    if next_depth > 100 then
        error(Error(698):toString())
    end

    if not noref_mode then
        local cached = cache[obj]
        if cached ~= nil then
            return cached
        end
        local out = _copy_mark_kind(obj, {})
        cache[obj] = out
        if _copy_table_kind(obj) == "list" then
            for i = 1, #obj do
                out[i] = _deepcopy_value(obj[i], noref_mode, cache, stack, next_depth)
            end
        else
            for k, v in pairs(obj) do
                out[k] = _deepcopy_value(v, noref_mode, cache, stack, next_depth)
            end
        end
        return out
    end

    if stack[obj] then
        error(Error(724):toString())
    end
    stack[obj] = true

    local out = _copy_mark_kind(obj, {})
    if _copy_table_kind(obj) == "list" then
        for i = 1, #obj do
            out[i] = _deepcopy_value(obj[i], noref_mode, cache, stack, next_depth)
        end
    else
        for k, v in pairs(obj) do
            out[k] = _deepcopy_value(v, noref_mode, cache, stack, next_depth)
        end
    end

    stack[obj] = nil
    return out
end

function Builtins.copy(obj, ...)
    if select("#", ...) > 0 then
        error(Error(118, "copy"):toString())
    end
    if type(obj) ~= "table" then
        return obj
    end
    return _copy_shallow_table(obj)
end

function Builtins.deepcopy(obj, noref, ...)
    if select("#", ...) > 0 then
        error(Error(118, "deepcopy"):toString())
    end
    return _deepcopy_value(obj, _vim_truthy(noref), {}, {}, 0)
end

function Builtins.join(lst, sep)
    if type(lst) ~= "table" then
        error("join(): expected List")
    end
    local glue = sep == nil and " " or tostring(sep)
    local parts = {}
    for i = 1, #lst do
        local v = lst[i]
        if type(v) == "string" then
            parts[#parts + 1] = v
        else
            parts[#parts + 1] = v == nil and "" or vim_string(v)
        end
    end
    return table.concat(parts, glue)
end

-- Returns the runtime search path, including pack/*/start entries.
function Builtins.nvim_list_runtime_paths()
    return RuntimePath.get_search_list()
end

-- Matches files/dirs under the runtime search path; when all=false returns first match only.
function Builtins.nvim_get_runtime_file(name, all)
    if type(name) ~= "string" then
        error("nvim_get_runtime_file(): expected name as string")
    end
    local want_all = not not all
    local rtp = RuntimePath.get_search_list()

    local out = {}
    for _, base in ipairs(rtp) do
        local matches = Filesystem.ExpandWildcards(base .. "/" .. name)
        for _, m in ipairs(matches) do
            out[#out + 1] = m
            if not want_all then
                return out
            end
        end
    end
    return out
end

function Builtins.map(lst, expr)
    if type(lst) ~= "table" then
        error("map(): expected List or Dict")
    end
    if type(expr) == "function" then
        for k, v in pairs(lst) do
            local rv = expr(k, v)
            if Error.IsError(rv) then
                error(rv:toString())
            end
            lst[k] = rv
        end
        return lst
    end
    if type(expr) ~= "string" then
        error("map(): expected {expr} as string or function")
    end

    local VimExpr = loadModule("lib.excmd.vimxpr")
    local prev_val = scopes._v.val
    local prev_key = scopes._v.key
    for k, v in pairs(lst) do
        scopes._v.val = v
        scopes._v.key = k
        local rv = VimExpr.evaluate(expr, {
            scope = { g = scopes._g, v = scopes._v },
            funcs = Builtins,
        })
        if Error.IsError(rv) then
            scopes._v.val = prev_val
            scopes._v.key = prev_key
            error(rv:toString())
        end
        lst[k] = rv
    end
    scopes._v.val = prev_val
    scopes._v.key = prev_key
    return lst
end

function Builtins.sort(lst, how)
    if type(lst) ~= "table" then return lst end
    local cmp = nil
    if type(how) == "string" then
        if how:find("i", 1, true) then
            cmp = function(a, b) return tostring(a):lower() < tostring(b):lower() end
        elseif how:find("n", 1, true) then
            cmp = function(a, b) return tonumber(a) < tonumber(b) end
        end
    elseif type(how) == "function" then
        cmp = how
    end
    table.sort(lst, cmp)
    return lst
end

function Builtins.strpart(str, start, len)
    local s = tostring(str or "")
    local st = tonumber(start or 0) or 0
    local ln = len and (tonumber(len) or 0) or nil
    if st < 0 then st = 0 end
    -- Vim's strpart is 0-based; Lua's string.sub is 1-based.
    local from = st + 1
    if not ln then
        return s:sub(from)
    end
    if ln <= 0 then return "" end
    return s:sub(from, from + ln - 1)
end

function Builtins.strdisplaywidth(str)
    local s = tostring(str or "")
    return #s
end

function Builtins.printf(fmt, ...)
    local f = tostring(fmt or "")
    -- Vim's %S is a string specifier; Lua uses %s
    f = f:gsub("%%([%-0-9%.]*)S", "%%%1s")
    local ok, rv = pcall(string.format, f, ...)
    if not ok then
        error("printf(): " .. tostring(rv))
    end
    return rv
end

function Builtins.strftime(fmt, time)
    local f = tostring(fmt or "")
    local t = time
    if t == nil or t == "" then
        return os.date(f)
    end
    return os.date(f, tonumber(t) or 0)
end

function Builtins.getftype(fname)
    local p = tostring(fname or "")
    if p == "" then return "" end
    local path = _abs_path(p)
    if not fs.exists(path) then return "" end
    if fs.isDir(path) then return "dir" end
    return "file"
end

function Builtins.getfsize(fname)
    local p = tostring(fname or "")
    if p == "" then return -1 end
    local path = _abs_path(p)
    if not fs.exists(path) then return -1 end
    if fs.isDir(path) then return 0 end
    return fs.getSize(path) or 0
end

function Builtins.getftime(fname)
    local p = tostring(fname or "")
    if p == "" then return -1 end
    local path = _abs_path(p)
    if not fs.exists(path) then return -1 end
    -- ComputerCraft doesn't expose mtime; return 0 to indicate "unknown"
    return 0
end

function Builtins.executable(fname)
    local p = tostring(fname or "")
    if p == "" then return 0 end
    local path = _abs_path(p)
    if fs.exists(path) and not fs.isDir(path) and path:match("%.lua$") then
        return 1
    end
    return 0
end

-- execute({command} [, {silent}]): execute command(s) and capture output.
-- {command} may be a string or list of command strings.
-- {silent} may be "", "silent", or "silent!" (default: "silent").
function Builtins.execute(command, silent, ...)
    if select("#", ...) > 0 then
        error(Error(118, "execute"):toString())
    end

    local mode
    if silent == nil then
        mode = "silent"
    else
        mode = tostring(silent)
        if mode ~= "" and mode ~= "silent" and mode ~= "silent!" then
            error(Error(474, "execute(): invalid {silent} value"):toString())
        end
    end

    local script
    if type(command) == "table" and not command.__call then
        for k, _ in pairs(command) do
            if type(k) ~= "number" then
                error(Error(1098):toString())
            end
        end
        local cmds = {}
        for i = 1, #command do
            local line = tostring(command[i] or "")
            if mode ~= "" then
                line = mode .. " " .. line
            end
            cmds[#cmds + 1] = line
        end
        script = table.concat(cmds, "\n")
    elseif type(command) == "string" then
        script = command
        if mode ~= "" then
            script = mode .. " " .. script
        end
    else
        error(Error(1098):toString())
    end

    Runtime = Runtime or loadModule("lib.excmd.runtime")
    ExMsg = ExMsg or loadModule("lib.excmd.exmsg")

    local cap = ExMsg.StartCapture()
    ExMsg.PushUISuppress()
    local thrown = nil
    local ok, ran_ok, rv = xpcall(function()
        return Runtime.run(script, {
            state = Runtime._CURRENT_STATE,
            ctrl = Runtime._CURRENT_CTRL,
            origin = {
                kind = "vim-execute",
                source = Runtime._CURRENT_STATE and Runtime._CURRENT_STATE.script_ctx or nil,
            },
        })
    end, function(e)
        thrown = e
        return e
    end)
    ExMsg.PopUISuppress()
    local output, last_err = ExMsg.EndCapture(cap)

    -- execute() returns captured text without a trailing line break.
    output = output:gsub("\n$", "")

    if not ok then
        if mode == "silent!" then
            return output
        end
        error(tostring(thrown))
    end

    if not ran_ok then
        if mode == "silent!" then
            return output
        end
        local emsg = last_err or ((rv and rv.toString) and rv:toString()) or tostring(rv)
        error(emsg)
    end

    return output
end

function Builtins.glob(expr, nosuf, list, alllinks)
    local e = tostring(expr or "")
    local want_list = list and list ~= 0 and list ~= false
    if e == "" then
        if want_list then
            return _mark_vim_list({})
        end
        return ""
    end
    local matches = Filesystem.ExpandWildcards(e) or {}
    matches = _glob_matches_for_relative_expr(e, matches)
    if want_list then
        return _mark_vim_list(matches)
    end
    return table.concat(matches, "\n")
end

function Builtins.shellescape(str, special)
    local s = tostring(str or "")
    s = s:gsub("\\", "\\\\")
    s = s:gsub("\"", "\\\"")
    local needs_quote = (special == 1) or s:match("[%s%p]") ~= nil
    if needs_quote then
        return "\"" .. s .. "\""
    end
    return s
end

function Builtins.simplify(path)
    local p = tostring(path or "")
    if p == "" then return "" end
    local is_abs = p:sub(1, 1) == "/"
    local keep_dot_prefix = (not is_abs) and p:sub(1, 2) == "./"
    local keep_trailing_sep = p:sub(-1) == "/"
    local keep_double_slash = p:sub(1, 2) == "//" and p:sub(1, 3) ~= "///"
    local parts = {}
    for seg in p:gmatch("[^/]+") do
        if seg == "." or seg == "" then
            -- skip
        elseif seg == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts, #parts)
            elseif not is_abs then
                parts[#parts + 1] = ".."
            end
        else
            parts[#parts + 1] = seg
        end
    end
    local out = table.concat(parts, "/")
    if is_abs then
        if keep_double_slash then
            out = "//" .. out
        else
            out = "/" .. out
        end
    end
    if out == "" then
        out = is_abs and (keep_double_slash and "//" or "/") or "."
    end
    if keep_dot_prefix
        and out ~= "."
        and out ~= ""
        and out ~= ".."
        and out:sub(1, 2) ~= "./"
        and out:sub(1, 3) ~= "../"
    then
        out = "./" .. out
    end
    if keep_trailing_sep and out ~= "/" and out ~= "//" then
        if out == "." then
            if keep_dot_prefix then
                out = "./"
            else
                out = ""
            end
        elseif out:sub(-1) ~= "/" then
            out = out .. "/"
        end
    end
    return out
end

function Builtins.resolve(filename)
    local name = tostring(filename or "")
    if name == "" then
        return ""
    end
    local keep_trailing = name:sub(-1) == "/"
    local out = Builtins.simplify(name)
    if keep_trailing and out ~= "/" and out:sub(-1) ~= "/" then
        out = out .. "/"
    end
    return out
end

function Builtins.histdel(_history, _item, ...)
    if select("#", ...) > 0 then
        error(Error(118, "histdel"):toString())
    end
    -- TODO: history backends pending.
    -- TODO: support item deletion.
    return 1
end

function Builtins.substitute(expr, pat, sub, flags)
    local s = tostring(expr or "")
    local p = tostring(pat or "")
    local r = tostring(sub or "")
    local f = tostring(flags or "")
    if p == "" then return s end
    local g = f:find("g", 1, true) ~= nil
    local ic = f:find("i", 1, true) ~= nil

    local compiled = VimRegex.compile(p)
    if not compiled then
        return s
    end

    local has_num_ref = r:find("\\[0-9]") ~= nil
    local caps_compiled = nil
    if has_num_ref then
        -- VimRegex simple mode drops \(...\) captures; build a capture-annotated
        -- pattern using \z( ... \) to recover \1..\9 replacement semantics.
        local out = {}
        local i, n = 1, #p
        while i <= n do
            local ch = p:sub(i, i)
            if ch == "\\" and i < n then
                local nxt = p:sub(i + 1, i + 1)
                if nxt == "z" and p:sub(i + 2, i + 2) == "(" then
                    out[#out + 1] = "\\z("
                    i = i + 3
                elseif nxt == "(" then
                    out[#out + 1] = "\\z("
                    i = i + 2
                else
                    out[#out + 1] = "\\" .. nxt
                    i = i + 2
                end
            else
                out[#out + 1] = ch
                i = i + 1
            end
        end
        caps_compiled = VimRegex.compile(table.concat(out))
    end

    local function repl(match, caps)
        local out = {}
        local i, n = 1, #r
        while i <= n do
            local ch = r:sub(i, i)
            if ch == "\\" and i < n then
                local nxt = r:sub(i + 1, i + 1)
                local d = tonumber(nxt)
                if d ~= nil then
                    if d == 0 then
                        out[#out + 1] = match
                    else
                        local cap = (type(caps) == "table") and caps[d] or nil
                        out[#out + 1] = cap == nil and "" or tostring(cap)
                    end
                elseif nxt == "&" then
                    out[#out + 1] = "&"
                elseif nxt == "\\" then
                    out[#out + 1] = "\\"
                else
                    out[#out + 1] = nxt
                end
                i = i + 2
            elseif ch == "&" then
                out[#out + 1] = match
                i = i + 1
            else
                out[#out + 1] = ch
                i = i + 1
            end
        end
        return table.concat(out)
    end

    local out = {}
    local idx = 1
    local case_sensitive = not ic
    while idx <= #s do
        local sub_s = s:sub(idx)
        local ss, ee, caps
        if caps_compiled then
            ss, ee, caps = VimRegex.find_compiled_with_caps(sub_s, caps_compiled, case_sensitive)
        end
        if not ss then
            ss, ee = VimRegex.find_compiled(sub_s, compiled, case_sensitive)
        end
        if not ss then
            out[#out + 1] = sub_s
            break
        end
        out[#out + 1] = sub_s:sub(1, ss - 1)
        local match = sub_s:sub(ss, ee)
        out[#out + 1] = repl(match, caps)

        local prev_idx = idx
        if ee < ss then
            idx = idx + ss
        else
            idx = idx + ee
        end
        if idx <= prev_idx then
            idx = prev_idx + 1
        end

        if not g then
            out[#out + 1] = sub_s:sub(ee + 1)
            break
        end
    end
    return table.concat(out)
end

-- string({expr}): Vimscript-style stringification
function Builtins.string(expr, ...)
    if select("#", ...) > 0 then
        error(Error(118, "string"):toString())
    end
    return vim_string(expr)
end

-- Export: the builtins table for evaluator and :call; plus a Lua proxy for vim.fn usage
local export = Builtins

export._proxy = setmetatable({}, {
    __index = function(_, key)
        -- Return a callable that looks up Vimscript function or builtin at call time
        return function(...)
            return call_vimfunc(key, ...)
        end
    end
})

export._call = call_vimfunc
export._funcref_name = function(fn)
    return funcref_name_by_fn[fn]
end
export._register_funcref = register_funcref_name

return export
