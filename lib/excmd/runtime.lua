-- vim.lib.excmd.runtime
local Runtime = {}

local VimExpr = loadModule("lib.excmd.vimxpr")
local VimRegex = loadModule("lib.excmd.vim_regex")
local Error = loadModule("lib.error")
local Compiler = loadModule("lib.excmd.compiler")
local Commands = loadModule("lib.excmd.commands")
local Options = loadModule("lib.options")
local Autocmd = loadModule("lib.autocmd")
local ScriptSource
local scopes = loadModule("lib.luaapi.scopes")
local Builtins = loadModule("lib.luaapi.fn")
local Utf8 = loadModule("lib.utf8")

Runtime._FUNCS = {}
Runtime._USER_COMMANDS = {}
Runtime._LAST_PUT_EXPR = ""
Runtime._LAST_SEARCH_PATTERN = ""
Runtime._LAST_SUBSTITUTE_PATTERN = ""
Runtime._LAST_SUBSTITUTE_REPL = ""
Runtime._LAST_SUBSTITUTE_FLAGS = ""
local runtime_undo_batch_depth = 0
local runtime_undo_batch_buffers = nil
local runtime_undo_batch_active = false
local runtime_undo_batch_pause_count = 0

local function runtime_undo_batch_begin()
    runtime_undo_batch_buffers = {}
    runtime_undo_batch_active = true
    runtime_undo_batch_pause_count = 0
    for _, buf in pairs(buffers) do
        runtime_undo_batch_buffers[#runtime_undo_batch_buffers + 1] = buf
        buf:undo_begin()
    end
end

local function runtime_undo_batch_end()
    if runtime_undo_batch_active and runtime_undo_batch_buffers then
        for i = 1, #runtime_undo_batch_buffers do
            runtime_undo_batch_buffers[i]:undo_end()
        end
    end
    runtime_undo_batch_buffers = nil
    runtime_undo_batch_active = false
    runtime_undo_batch_pause_count = 0
end

local function runtime_undo_batch_pause()
    if runtime_undo_batch_depth == 0 then
        return
    end
    runtime_undo_batch_pause_count = runtime_undo_batch_pause_count + 1
    if runtime_undo_batch_pause_count > 1 then
        return
    end
    if runtime_undo_batch_active and runtime_undo_batch_buffers then
        for i = 1, #runtime_undo_batch_buffers do
            runtime_undo_batch_buffers[i]:undo_end()
        end
        runtime_undo_batch_active = false
    end
end

local function runtime_undo_batch_resume()
    if runtime_undo_batch_depth == 0 or runtime_undo_batch_pause_count == 0 then
        return
    end
    runtime_undo_batch_pause_count = runtime_undo_batch_pause_count - 1
    if runtime_undo_batch_pause_count > 0 then
        return
    end
    if (not runtime_undo_batch_active) and runtime_undo_batch_buffers then
        for i = 1, #runtime_undo_batch_buffers do
            runtime_undo_batch_buffers[i]:undo_begin()
        end
        runtime_undo_batch_active = true
    end
end

local SCRIPT_SID_BY_SCOPE = setmetatable({}, { __mode = "k" })
local SCRIPT_SID_BY_CTX = {}
local NEXT_SCRIPT_SID = 0

local function alloc_script_sid()
    NEXT_SCRIPT_SID = NEXT_SCRIPT_SID + 1
    return NEXT_SCRIPT_SID
end

local function script_sid_for_ctx(ctx)
    if type(ctx) ~= "string" or ctx == "" then
        return nil
    end
    local sid = SCRIPT_SID_BY_CTX[ctx]
    if not sid then
        sid = alloc_script_sid()
        SCRIPT_SID_BY_CTX[ctx] = sid
    end
    return sid
end

local function script_sid_for_scope(scope)
    if type(scope) ~= "table" then
        return nil
    end
    local sid = SCRIPT_SID_BY_SCOPE[scope]
    if not sid then
        sid = alloc_script_sid()
        SCRIPT_SID_BY_SCOPE[scope] = sid
    end
    return sid
end

local function script_sid_for_state(state)
    if type(state) ~= "table" then
        return nil
    end
    if type(state.script_sid) == "number" then
        return state.script_sid
    end
    local sid = script_sid_for_ctx(state.script_ctx)
    if not sid then
        sid = script_sid_for_scope(state.s)
    end
    state.script_sid = sid
    return sid
end

local function canonical_function_name(name, opts)
    if type(name) ~= "string" then
        return nil
    end
    if name == "" then
        return ""
    end
    if name:match("^<SNR>%d+_.+$") then
        return name
    end

    local tail = name:match("^s:(.+)$") or name:match("^<SID>(.+)$")
    if not tail then
        return name
    end

    opts = opts or {}
    local sid = opts.sid
    if not sid and opts.state then
        sid = script_sid_for_state(opts.state)
    end
    if not sid and opts.script_ctx then
        sid = script_sid_for_ctx(opts.script_ctx)
    end
    if not sid then
        sid = script_sid_for_state(Runtime._CURRENT_STATE)
    end
    if not sid then
        return nil
    end
    return "<SNR>" .. tostring(sid) .. "_" .. tail
end

local function fresh_v(extra)
    local v = { ["true"] = true, ["false"] = false, errmsg = "" }
    if type(extra) == "table" then
        for k, val in pairs(extra) do v[k] = val end
    end
    return v
end

local function ensure_state(state)
    state = state or {}
    state.g = state.g or scopes._g or {}
    state.s = state.s or {}
    state.l = state.l or {}
    state.a = state.a or {}
    state.v = state.v or fresh_v()
    state.funcs = state.funcs or {}
    state.frames = state.frames or {}
    state.commands = state.commands or {}
    state.menus = state.menus or {}
    state.script_ctx = state.script_ctx
    script_sid_for_state(state)
    return state
end

local function truthy(v)
    if type(v) == "boolean" then return v end
    if v == nil then return false end
    if type(v) == "number" then return v ~= 0 end
    if type(v) == "string" then return v ~= "" end
    if type(v) == "table" then return true end
    return not not v
end

local function eval_expr(expr, state)
    local top = state.frames[#state.frames]
    local scope = {
        g = state.g,
        s = state.s,
        l = top and top.l or state.l,
        a = top and top.a or state.a,
        v = top and top.v or state.v,
    }
    local funcs = state.funcs or {}
    local rv = VimExpr.evaluate(expr, { scope = scope, funcs = funcs })
    if Error.IsError(rv) then error(rv:toString()) end
    return rv
end

local function resolve_function_def(name, opts)
    if type(name) ~= "string" or name == "" then
        return nil, name
    end
    opts = opts or {}
    local state = opts.state or Runtime._CURRENT_STATE
    local canon = canonical_function_name(name, {
        state = state,
        script_ctx = opts.script_ctx,
        sid = opts.sid,
    }) or name

    local def
    if state and state.funcs then
        def = state.funcs[name] or state.funcs[canon]
        if not def then
            local _, tail = canon:match("^<SNR>(%d+)_(.+)$")
            if tail then
                def = state.funcs["s:" .. tail]
            end
        end
    end
    if not def then
        def = Runtime._FUNCS[name] or Runtime._FUNCS[canon]
    end
    return def, canon
end

local function autoload_script_for_function(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end

    local autoload_key = name
    local scope, rest = name:match("^([gslavbtw]):(.+)$")
    if scope then
        if scope ~= "g" then
            return nil
        end
        autoload_key = rest
    end

    if not autoload_key:find("#", 1, true) then
        return nil
    end

    local parts = {}
    for seg in autoload_key:gmatch("[^#]+") do
        parts[#parts + 1] = seg
    end
    if #parts < 2 then
        return nil
    end

    return "autoload/" .. table.concat(parts, "/", 1, #parts - 1)
end

local function try_autoload_function(name)
    local script = autoload_script_for_function(name)
    if not script then
        return false
    end

    ScriptSource = ScriptSource or loadModule("lib.scriptsource")
    LOG_DEBUG("autoload: loading %s for %s", script, name)

    local ok = ScriptSource.source_runtime(script .. ".vim")
    if not ok then
        ok = ScriptSource.source_runtime(script .. ".lua")
    end
    return ok == true
end

local function table_kind_for_index(tbl)
    if type(tbl) ~= "table" then
        return nil
    end

    local mt = getmetatable(tbl)
    if mt and (mt.__vimxpr_kind == "list" or mt.__vimxpr_kind == "dict") then
        return mt.__vimxpr_kind
    end

    local maxk = 0
    local count = 0
    for k, _ in pairs(tbl) do
        if type(k) ~= "number" or k < 1 or (k % 1) ~= 0 then
            return "dict"
        end
        if k > maxk then maxk = k end
        count = count + 1
    end
    if count == 0 then
        return "dict"
    end
    return (count == maxk) and "list" or "dict"
end

local function list_index_to_key(tbl, idx)
    if type(idx) ~= "number" then
        return idx
    end
    if idx >= 0 then
        return idx + 1
    end
    return #tbl + idx + 1
end

local function split_lvalue_base_and_tail(lhs)
    local s = (lhs or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then
        return nil
    end

    local i = 1
    local n = #s
    local ch = s:sub(i, i)
    if ch:match("[gslavbtw]") and s:sub(i + 1, i + 1) == ":" then
        i = i + 2
    end

    local start = i
    while i <= n do
        local c = s:sub(i, i)
        if c:match("[%w_#]") then
            i = i + 1
        else
            break
        end
    end

    if i == start then
        return nil
    end
    local base = s:sub(1, i - 1)
    local tail = s:sub(i)
    if tail == "" then
        return { base = base, segments = {} }
    end
    return { base = base, tail = tail }
end

local function parse_lvalue_segments(tail, state)
    local segs = {}
    local i = 1
    local n = #tail

    local function skip_ws()
        while i <= n and tail:sub(i, i):match("%s") do
            i = i + 1
        end
    end

    skip_ws()
    while i <= n do
        local c = tail:sub(i, i)
        if c == "." then
            i = i + 1
            local s = i
            while i <= n and tail:sub(i, i):match("[%w_#]") do
                i = i + 1
            end
            if i == s then
                return nil
            end
            segs[#segs + 1] = { kind = "member", key = tail:sub(s, i - 1) }
            skip_ws()
        elseif c == "[" then
            local j = i + 1
            local depth = 1
            local in_s, in_d, esc = false, false, false
            while j <= n do
                local cj = tail:sub(j, j)
                if in_s then
                    if cj == "'" then
                        if tail:sub(j + 1, j + 1) == "'" then
                            j = j + 1
                        else
                            in_s = false
                        end
                    end
                elseif in_d then
                    if esc then
                        esc = false
                    elseif cj == "\\" then
                        esc = true
                    elseif cj == "\"" then
                        in_d = false
                    end
                else
                    if cj == "'" then
                        in_s = true
                    elseif cj == "\"" then
                        in_d = true
                    elseif cj == "[" then
                        depth = depth + 1
                    elseif cj == "]" then
                        depth = depth - 1
                        if depth == 0 then break end
                    end
                end
                j = j + 1
            end
            if depth ~= 0 then
                return nil
            end
            local expr = tail:sub(i + 1, j - 1)
            local ok, key = pcall(eval_expr, expr, state)
            if not ok then
                return nil
            end
            segs[#segs + 1] = { kind = "index", key = key }
            i = j + 1
            skip_ws()
        else
            return nil
        end
    end

    return segs
end

local function resolve_assignment_slot(base, state)
    local scope, name = base:match("^([gslavbtw]):(.+)$")
    local top = state.frames[#state.frames]
    if scope == "g" then return state.g, name end
    if scope == "s" then return state.s, name end
    if scope == "l" then
        if not top then return nil, nil, Error(461, base) end
        return top.l, name
    end
    if scope == "a" then
        if not top then return nil, nil, Error(461, base) end
        return top.a, name
    end
    if scope == "v" then return (top and top.v or state.v), name end
    if scope == "b" then return scopes.b, name end
    if scope == "w" then return scopes.w, name end
    if scope == "t" then return scopes.t, name end

    if top and top.l[base] ~= nil then
        return top.l, base
    end
    if state.g[base] ~= nil then
        return state.g, base
    end
    if top then
        return top.l, base
    end
    return state.g, base
end

local function resolve_path_key(container, seg)
    if seg.kind == "member" then
        return seg.key
    end
    local kind = table_kind_for_index(container)
    if kind == "list" then
        return list_index_to_key(container, seg.key)
    end
    return seg.key
end

local function split_list_lhs_items(spec)
    local s = tostring(spec or "")
    local out, buf = {}, {}
    local in_s, in_d, esc = false, false, false
    local depth_p, depth_c, depth_b = 0, 0, 0

    local function flush()
        local item = table.concat(buf):gsub("^%s+", ""):gsub("%s+$", "")
        out[#out + 1] = item
        buf = {}
    end

    for i = 1, #s do
        local ch = s:sub(i, i)
        if esc then
            buf[#buf + 1] = ch
            esc = false
        elseif ch == "\\" then
            esc = true
            buf[#buf + 1] = ch
        elseif not in_d and ch == "'" then
            in_s = not in_s
            buf[#buf + 1] = ch
        elseif not in_s and ch == '"' then
            in_d = not in_d
            buf[#buf + 1] = ch
        elseif not in_s and not in_d then
            if ch == "(" then
                depth_p = depth_p + 1
                buf[#buf + 1] = ch
            elseif ch == ")" then
                depth_p = math.max(0, depth_p - 1)
                buf[#buf + 1] = ch
            elseif ch == "{" then
                depth_c = depth_c + 1
                buf[#buf + 1] = ch
            elseif ch == "}" then
                depth_c = math.max(0, depth_c - 1)
                buf[#buf + 1] = ch
            elseif ch == "[" then
                depth_b = depth_b + 1
                buf[#buf + 1] = ch
            elseif ch == "]" then
                depth_b = math.max(0, depth_b - 1)
                buf[#buf + 1] = ch
            elseif ch == "," and depth_p == 0 and depth_c == 0 and depth_b == 0 then
                flush()
            else
                buf[#buf + 1] = ch
            end
        else
            buf[#buf + 1] = ch
        end
    end

    if #buf > 0 then
        flush()
    end
    return out
end

local function assign_lhs(lhs, value, state)
    local s = (lhs or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if s:sub(1, 1) == "[" and s:sub(-1) == "]" then
        local inner = s:sub(2, -2)
        local items = split_list_lhs_items(inner)
        local src = {}
        if type(value) == "string" then
            for i = 1, #value do
                src[#src + 1] = value:sub(i, i)
            end
        elseif type(value) == "table" then
            for i = 1, #value do
                src[i] = value[i]
            end
        end
        for i = 1, #items do
            local item = items[i]
            if item ~= "" then
                local ok = assign_lhs(item, src[i], state)
                if Error.IsError(ok) then
                    return ok
                end
            end
        end
        return true
    end

    local parsed = split_lvalue_base_and_tail(s)
    if parsed and parsed.tail and parsed.tail ~= "" then
        local segments = parse_lvalue_segments(parsed.tail, state)
        if segments and #segments > 0 then
            local slot_tbl, slot_key, slot_err = resolve_assignment_slot(parsed.base, state)
            if slot_err then return slot_err end
            if type(slot_tbl) ~= "table" then
                return Error(0, "Invalid assignment target: " .. tostring(lhs))
            end
            local cursor = slot_tbl[slot_key]
            if type(cursor) ~= "table" then
                return Error(121, parsed.base)
            end
            for i = 1, #segments - 1 do
                local k = resolve_path_key(cursor, segments[i])
                local nxt = cursor[k]
                if type(nxt) ~= "table" then
                    return Error(121, parsed.base)
                end
                cursor = nxt
            end
            local last_key = resolve_path_key(cursor, segments[#segments])
            cursor[last_key] = value
            return true
        end
    end

    local scope, name = s:match("^([gslavbtw]):(.+)$")
    local top = state.frames[#state.frames]
    if scope == "g" then state.g[name] = value; return true end
    if scope == "s" then state.s[name] = value; return true end
    if scope == "l" then if not top then return Error(461, s) end; top.l[name] = value; return true end
    if scope == "a" then if not top then return Error(461, s) end; top.a[name] = value; return true end
    if scope == "v" then (top and top.v or state.v)[name] = value; return true end
    if scope == "b" then scopes.b[name] = value; return true end
    if scope == "w" then scopes.w[name] = value; return true end
    if scope == "t" then scopes.t[name] = value; return true end
    if top then top.l[s] = value; return true end
    state.g[s] = value; return true
end

local function unlet(names, _, state)
    local top = state.frames[#state.frames]
    for tok in names:gmatch("%S+") do
        local name = tok:gsub(",%$", "")
        local scope, key = name:match("^([gslavbtw]):(.+)$")
        if scope == "g" then state.g[key] = nil
        elseif scope == "s" then state.s[key] = nil
        elseif scope == "l" then if top then top.l[key] = nil end
        elseif scope == "a" then if top then top.a[key] = nil end
        elseif scope == "v" then (top and top.v or state.v)[key] = nil
        elseif scope == "b" then scopes.b[key] = nil
        elseif scope == "w" then scopes.w[key] = nil
        elseif scope == "t" then scopes.t[key] = nil
        else state.g[name] = nil end
    end
    return true
end

local function iter_list(val)
    if type(val) == "string" then
        local t = {}
        for i = 1, #val do t[#t + 1] = val:sub(i, i) end
        return t
    elseif type(val) == "table" then
        local t = {}
        for i = 1, #val do t[i] = val[i] end
        return t
    end
    return {}
end

local function to_number(v)
    if type(v) == "number" then
        return v
    end
    if type(v) == "boolean" then
        return v and 1 or 0
    end
    if type(v) == "string" then
        local n = tonumber(v)
        if n ~= nil then
            return n
        end
        local lead = v:match("^%s*([+-]?%d+)")
        if lead then
            local ln = tonumber(lead)
            if ln ~= nil then
                return ln
            end
        end
        return 0
    end
    if v == nil then
        return 0
    end
    return 0
end

local function build_call_scopes(arg_values, param_names)
    param_names = param_names or {}
    arg_values = arg_values or {}

    local l_scope, a_scope = {}, {}
    local fixed_count = 0
    local has_varargs = false

    for i = 1, #param_names do
        local pname = param_names[i]
        if pname == "..." then
            has_varargs = true
        else
            fixed_count = fixed_count + 1
            local valid_name = type(pname) == "string" and pname:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
            local key = valid_name and pname or ("a" .. tostring(fixed_count))
            local val = arg_values[fixed_count]
            a_scope[key] = val
            l_scope[key] = val
        end
    end

    if has_varargs then
        local extras = {}
        local extra_count = 0
        for i = fixed_count + 1, #arg_values do
            extra_count = extra_count + 1
            local val = arg_values[i]
            a_scope[tostring(extra_count)] = val
            extras[extra_count] = val
        end
        a_scope["0"] = extra_count
        a_scope["000"] = extras
        a_scope["..."] = extras
    else
        a_scope["0"] = 0
        a_scope["000"] = {}
    end

    return l_scope, a_scope
end

Runtime.BuildCallScopes = build_call_scopes

local function strip(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function lstrip(s)
    return tostring(s or ""):gsub("^%s+", "")
end

local function one_line_text(s)
    local text = tostring(s or "")
    text = text:gsub("[\r\n\t]", " ")
    text = text:gsub("%s+", " ")
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function short_text(s, maxlen)
    local text = one_line_text(s)
    local lim = maxlen or 180
    if #text <= lim then
        return text
    end
    return text:sub(1, lim - 3) .. "..."
end

local function script_head_line(script)
    local head = tostring(script or ""):match("([^\r\n]+)")
    return short_text(head or "", 180)
end

local function normalize_origin(origin, state)
    if type(origin) == "string" and origin ~= "" then
        return { kind = origin }
    end
    if type(origin) == "table" then
        return origin
    end
    if type(state) == "table" and type(state.script_ctx) == "string" and state.script_ctx ~= "" then
        return { kind = "sourced-file", source = state.script_ctx }
    end
    return { kind = "runtime" }
end

local function append_ctx(parts, key, value, maxlen)
    if value == nil then
        return
    end
    local text = short_text(value, maxlen or 180)
    if text ~= "" then
        parts[#parts + 1] = key .. "=" .. text
    end
end

local function build_error_context(rt, opts, state, script)
    local origin = normalize_origin(opts and opts.origin, state)
    local cursor = rt and rt:get_exec_cursor()
    local parts = {}

    append_ctx(parts, "kind", origin.kind, 80)
    append_ctx(parts, "event", origin.event, 80)
    append_ctx(parts, "id", origin.id, 40)
    append_ctx(parts, "group", origin.group, 40)
    append_ctx(parts, "api", origin.api, 80)
    append_ctx(parts, "fn", origin.func, 120)
    append_ctx(parts, "caller", origin.caller, 160)
    append_ctx(parts, "source", origin.source, 220)
    append_ctx(parts, "script_ctx", state.script_ctx, 220)

    if cursor and cursor.line then
        append_ctx(parts, "line", cursor.line, 40)
    end
    if cursor and cursor.text and cursor.text ~= "" then
        append_ctx(parts, "ex_cmd", cursor.text, 220)
    else
        append_ctx(parts, "ex_cmd", script_head_line(script), 220)
    end

    if #parts == 0 then
        return ""
    end
    return "ctx{" .. table.concat(parts, ",") .. "}"
end

local function with_context_message(message, rt, opts, state, script)
    local ctx = build_error_context(rt, opts, state, script)
    if ctx == "" then
        return tostring(message or "")
    end
    local base = tostring(message or "")
    if base:find("ctx{", 1, true) then
        return base
    end
    if base == "" then
        return ctx
    end
    return base .. " [" .. ctx .. "]"
end

local function enrich_runtime_error(err, rt, opts, state, script, fallback)
    if Error.IsError(err) then
        if err.code == 0 then
            err.params[1] = with_context_message(err.params[1], rt, opts, state, script)
        end
        return err
    end
    local base = err
    if base == nil then
        base = fallback
    end
    return Error(0, with_context_message(base, rt, opts, state, script))
end

local function log_command_resolution_failure(rt, name, lname, argstr, bang)
    local cursor = rt:get_exec_cursor()
    local line = tostring(cursor.line or "")
    local text = short_text(cursor.text or "", 220)
    local cmd = short_text(cursor.cmd or "", 120)
    local rest = short_text(cursor.rest or "", 220)
    local args = short_text(argstr or "", 220)
    local script_ctx = short_text(rt.state.script_ctx or "", 220)

    LOG_ERROR(
        "excmd resolve failure:"
        .. " name=" .. short_text(name or "", 120)
        .. " lname=" .. short_text(lname or "", 120)
        .. " bang=" .. (bang and "1" or "0")
        .. " args=" .. args
        .. " script_ctx=" .. script_ctx
        .. " cursor_line=" .. line
        .. " cursor_cmd=" .. cmd
        .. " cursor_rest=" .. rest
        .. " cursor_text=" .. text
    )
end

local function split_ws(raw)
    local out = {}
    local buf = {}
    local s = tostring(raw or "")
    local i, n = 1, #s

    local function flush()
        if #buf > 0 then
            out[#out + 1] = table.concat(buf)
            buf = {}
        end
    end

    while i <= n do
        local ch = s:sub(i, i)
        if ch == " " or ch == "\t" or ch == "\r" or ch == "\n" then
            flush()
            i = i + 1
        elseif ch == "\\" then
            if i < n then
                buf[#buf + 1] = s:sub(i + 1, i + 1)
                i = i + 2
            else
                buf[#buf + 1] = ch
                i = i + 1
            end
        else
            buf[#buf + 1] = ch
            i = i + 1
        end
    end

    flush()
    return out
end

local function expand_user_command_template(body, qargs, args, bang, count, line1, line2, range)
    local script = tostring(body or "")
    local fargs_token = "__CCVIM_FARGS__"
    local fargs = {}
    for i = 1, #args do
        fargs[i] = string.format("%q", args[i])
    end
    script = script:gsub("<lt>", "<")
    script = script:gsub("<bar>", "|")
    script = script:gsub("<bang>0", bang and "1" or "0")
    script = script:gsub("<f%-args>", fargs_token)
    script = script:gsub("<q%-args>", string.format("%q", qargs))
    script = script:gsub("<args>", qargs)
    script = script:gsub("<bang>", bang and "!" or "")
    script = script:gsub("<count>", tostring(count or 0))
    script = script:gsub("<line1>", tostring(line1 or 1))
    script = script:gsub("<line2>", tostring(line2 or 1))
    script = script:gsub("<range>", tostring(range or 0))
    if #fargs == 0 then
        script = script:gsub(",%s*" .. fargs_token, "")
        script = script:gsub(fargs_token, "")
    else
        script = script:gsub(fargs_token, table.concat(fargs, ","))
    end
    return script
end

local function split_set_args(s)
    if not s or s == "" then return {} end
    local out, buf, i, n = {}, {}, 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == "\\" and i < n then
            buf[#buf + 1] = s:sub(i, i + 1)
            i = i + 2
        elseif c == "\"" then
            local prev = (i > 1) and s:sub(i - 1, i - 1) or ""
            if i == 1 or prev == " " or prev == "\t" then
                break
            end
            buf[#buf + 1] = c
            i = i + 1
        elseif c == " " or c == "\t" then
            if #buf > 0 then
                out[#out + 1] = table.concat(buf)
                buf = {}
            end
            i = i + 1
            while i <= n and (s:sub(i, i) == " " or s:sub(i, i) == "\t") do
                i = i + 1
            end
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    if #buf > 0 then
        out[#out + 1] = table.concat(buf)
    end
    return out
end

local function strip_trailing_comment(argstr)
    local s = tostring(argstr or "")
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local c = s:sub(i, i)
        if c == "\\" and i < n then
            out[#out + 1] = s:sub(i, i + 1)
            i = i + 2
        elseif c == "\"" then
            break
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    return strip(table.concat(out))
end

local function rejoin_equals(args)
    local out, i = {}, 1
    while i <= #args do
        local tok = args[i]
        local nxt = args[i + 1]
        local n2 = args[i + 2]
        if tok:match("^[%a_]%w*$") and nxt then
            if nxt:match("^[:=]") then
                out[#out + 1] = tok .. "=" .. nxt:sub(2)
                i = i + 2
                goto continue
            elseif nxt == "=" and n2 then
                out[#out + 1] = tok .. "=" .. n2
                i = i + 3
                goto continue
            elseif nxt:match("^[+%^%-]=") then
                out[#out + 1] = tok .. nxt
                i = i + 2
                goto continue
            end
        end
        out[#out + 1] = tok
        i = i + 1
        ::continue::
    end
    return out
end

local MAP_COMMAND_SPECS = Commands.MAP_COMMAND_SPECS
local MENU_COMMAND_SPECS = Commands.MENU_COMMAND_SPECS
local DISPATCH_MIN_ABBREV = Commands.DISPATCH_MIN_ABBREV
local get_command_spec = Commands.get_spec
local resolve_dispatch_name = Commands.resolve_dispatch_name

function Runtime.new(init_state, init_opts)
    local ExMsg
    local function _exmsg()
        ExMsg = ExMsg or loadModule("lib.excmd.exmsg")
        return ExMsg
    end

    local rt = {
        state = ensure_state(init_state),
        opts = init_opts or {},
        Error = Error,
        return_exc = {},
        exec_cursor = {},
    }

    function rt:set_exec_cursor(line, text, cmd, rest)
        self.exec_cursor.line = line
        self.exec_cursor.text = text
        self.exec_cursor.cmd = cmd
        self.exec_cursor.rest = rest
        return true
    end

    function rt:get_exec_cursor()
        return self.exec_cursor
    end

    function rt:push_frame(arg_values, param_names)
        local l_scope, a_scope = build_call_scopes(arg_values, param_names)
        local frame = { l = l_scope, a = a_scope, v = self.state.v }
        local sf = self.state.frames
        sf[#sf + 1] = frame
        return frame
    end

    function rt:pop_frame()
        local sf = self.state.frames
        sf[#sf] = nil
    end

    function rt:call_func(name, args)
        local unpack_fn = table.unpack or unpack

        local function resolve_vlua(callee)
            if callee:sub(1, 6):lower() ~= "v:lua." then return nil end
            local rest = callee:sub(7)

            if rest:sub(1, 7) == "require" then
                local _, mod, func = rest:match([[^require(['"])([^'"]+)%1%.([%w_]+)$]])
                if not mod or not func then
                    error(Error(117, callee))
                end
                local Req = loadModule("lib.luaapi.require")
                local ok, modtbl = pcall(Req, mod)
                if not ok then
                    error(Error(5107, mod))
                end
                local f = modtbl and modtbl[func]
                if type(f) ~= "function" then
                    error(Error(117, callee))
                end
                return f
            end

            local LuaLoader = loadModule("lib.lualoader")
            local ok_eval, cur = LuaLoader.Eval("return " .. rest)
            if not ok_eval then
                error(cur)
            end
            if type(cur) ~= "function" then
                error(Error(117, callee))
            end
            return cur
        end

        if type(name) == "string" and name:sub(1, 6):lower() == "v:lua." then
            local f = resolve_vlua(name)
            local ok, rv = pcall(function()
                return f(unpack_fn(args or {}))
            end)
            if not ok then
                error(Error(5108, tostring(rv)))
            end
            return rv
        end

        local VimFnMod = loadModule("lib.luaapi.fn")
        local f_builtin = VimFnMod.fn[name]
        if type(f_builtin) == "function" then
            return f_builtin(unpack_fn(args or {}))
        end

        local fn = resolve_function_def(name, { state = self.state })
        if not fn and try_autoload_function(name) then
            fn = resolve_function_def(name, { state = self.state })
        end
        if not fn then error(Error(117, name)) end
        args = args or {}
        local prev_script_scope = self.state.s
        local prev_script_sid = self.state.script_sid
        local prev_script_ctx = self.state.script_ctx
        local prev_script_funcs = self.state.funcs
        self.state.s = fn.scope or prev_script_scope
        self.state.script_sid = fn.script_sid or prev_script_sid
        self.state.script_ctx = fn.script_ctx or prev_script_ctx
        self.state.funcs = fn.funcs or prev_script_funcs
        self:push_frame(args, fn.params or {})
        local ok, rv = pcall(fn.body, self)
        self:pop_frame()
        self.state.funcs = prev_script_funcs
        self.state.script_ctx = prev_script_ctx
        self.state.script_sid = prev_script_sid
        self.state.s = prev_script_scope
        if ok then return rv end
        if type(rv) == "table" and rv.__ret then return rv.value end
        error(rv)
    end

    function rt:register_function(name, params, body)
        local def = {
            params = params or {},
            body = body,
            scope = self.state.s,
            funcs = self.state.funcs,
            script_sid = self.state.script_sid,
            script_ctx = self.state.script_ctx,
            kind = "compiled",
        }
        local canon = canonical_function_name(name, { state = self.state })
        def.name = canon or name
        self.state.funcs[name] = def
        self.state.funcs[def.name] = def
        local is_script_local = type(name) == "string" and (name:match("^s:") or name:match("^<SID>"))
        if not is_script_local then
            Runtime._FUNCS[name] = def
        end
        Runtime._FUNCS[def.name] = def
    end

    function rt:eval_expr(expr)
        local state = self.state
        local top = state.frames[#state.frames]
        local scope = {
            g = state.g,
            s = state.s,
            l = top and top.l or state.l,
            a = top and top.a or state.a,
            v = top and top.v or state.v,
        }

        -- Build a callable map for VimExpr that dispatches to runtime:call_func
        -- so script-local definitions (including <SNR> names) are visible.
        local funcs = {}
        local function register(name)
            if not name or funcs[name] then return end
            funcs[name] = function(...) return self:call_func(name, { ... }) end
        end
        if state.funcs then
            for name in pairs(state.funcs) do
                register(name)
            end
        end
        for name in pairs(Runtime._FUNCS) do
            register(name)
        end
        local fallback_wrappers = {}
        setmetatable(funcs, {
            __index = function(_, name)
                if type(name) ~= "string" then
                    return nil
                end
                local wrapper = fallback_wrappers[name]
                if wrapper then
                    return wrapper
                end
                wrapper = function(...)
                    return self:call_func(name, { ... })
                end
                fallback_wrappers[name] = wrapper
                return wrapper
            end,
        })

        local rv = VimExpr.evaluate(expr, {
            scope = scope,
            funcs = funcs,
            script_sid = state.script_sid,
        })
        if Error.IsError(rv) then error(rv:toString()) end
        return rv
    end

    function rt:get_var(name)
        local var = strip(name)
        local scope, key = var:match("^([gslavwb]):(.+)$")
        local top = self.state.frames[#self.state.frames]
        if scope == "g" then return self.state.g[key] end
        if scope == "s" then return self.state.s[key] end
        if scope == "l" then return (top and top.l or self.state.l)[key] end
        if scope == "a" then return (top and top.a or self.state.a)[key] end
        if scope == "v" then return (top and top.v or self.state.v)[key] end
        if scope == "b" then return scopes.b[key] end
        if scope == "w" then return scopes.w[key] end
        if scope == "t" then return scopes.t[key] end
        if top and top.l[var] ~= nil then return top.l[var] end
        return self.state.g[var]
    end

    function rt:get_option(name, mode)
        local win = windows[curwin]
        local buf = win.buffer
        local getlocal = mode == "local"
        local getglobal = mode == "global"
        local val = Options.get(name, win, buf, getlocal, getglobal)
        if type(val) == "boolean" then
            return val and 1 or 0
        end
        return val
    end

    function rt:cmp(a, op, b)
        if op == "==" then return a == b end
        if op == "!=" then return a ~= b end

        local anum = tonumber(a)
        local bnum = tonumber(b)
        if anum ~= nil and bnum ~= nil then
            if op == "<" then return anum < bnum end
            if op == "<=" then return anum <= bnum end
            if op == ">" then return anum > bnum end
            if op == ">=" then return anum >= bnum end
            error("Unknown comparison operator: " .. tostring(op))
        end

        local as = tostring(a or "")
        local bs = tostring(b or "")
        if op == "<" then return as < bs end
        if op == "<=" then return as <= bs end
        if op == ">" then return as > bs end
        if op == ">=" then return as >= bs end
        error("Unknown comparison operator: " .. tostring(op))
    end

    function rt:truthy(v)
        return truthy(v)
    end

    function rt:assign(lhs, value)
        return assign_lhs(lhs, value, self.state)
    end

    function rt:assign_compound(lhs, op, rhs)
        local cur = self:get_var(lhs)
        local value

        if op == ".=" then
            value = tostring(cur or "") .. tostring(rhs or "")
        elseif op == "+=" then
            if type(cur) == "table" then
                local out = cur
                if type(rhs) == "table" then
                    for i = 1, #rhs do
                        out[#out + 1] = rhs[i]
                    end
                else
                    out[#out + 1] = rhs
                end
                value = out
            else
                value = to_number(cur) + to_number(rhs)
            end
        elseif op == "-=" then
            value = to_number(cur) - to_number(rhs)
        elseif op == "*=" then
            value = to_number(cur) * to_number(rhs)
        elseif op == "/=" then
            value = to_number(cur) / to_number(rhs)
        elseif op == "%=" then
            value = to_number(cur) % to_number(rhs)
        else
            return Error(474, "Unsupported let operator: " .. tostring(op))
        end

        return assign_lhs(lhs, value, self.state)
    end

    function rt:unlet(spec, bang)
        return unlet(spec, bang, self.state)
    end

    function rt:iter(val)
        return iter_list(val)
    end

    function rt:_push_script_ctx()
        local state = self.state
        self.__prev_state = Runtime._CURRENT_STATE
        self.__prev_ctrl = Runtime._CURRENT_CTRL
        self.__pushed_ctx = false
        if state.script_ctx and state.script_ctx ~= "" then
            ScriptSource = ScriptSource or loadModule("lib.scriptsource")
            ScriptSource.PushContext(state.script_ctx)
            self.__pushed_ctx = true
        end
        Runtime._CURRENT_STATE = state
        Runtime._CURRENT_CTRL = nil
    end

    function rt:_pop_script_ctx()
        Runtime._CURRENT_STATE = self.__prev_state
        Runtime._CURRENT_CTRL = self.__prev_ctrl
        if self.__pushed_ctx then
            ScriptSource = ScriptSource or loadModule("lib.scriptsource")
            ScriptSource.PopContext()
        end
        self.__pushed_ctx = false
        self.__prev_state = nil
        self.__prev_ctrl = nil
    end

    function rt:_pcall(fn)
        return pcall(fn)
    end

    function rt:return_exc(value)
        return { __ret = true, value = value }
    end

    function rt:break_exc()
        return { __break = true }
    end

    function rt:continue_exc()
        return { __continue = true }
    end

    function rt:catch_matches(err, spec)
        local s = strip(spec or "")
        if s == "" then
            return true
        end

        if #s >= 2 and s:sub(1, 1) == "/" and s:sub(-1) == "/" then
            s = s:sub(2, -2)
        end

        local msg
        if Error.IsError(err) then
            msg = err:toString()
        else
            msg = tostring(err)
        end

        local ecode = s:match("E%d+")
        if ecode and msg:find(ecode, 1, true) then
            return true
        end

        local ok_find, st, _, emsg = pcall(VimRegex.find, msg, s, true)
        if ok_find and not emsg then
            return st ~= nil
        end

        return msg:find(s, 1, true) ~= nil
    end

    local function current_win_buf()
        local win = windows[curwin]
        return win, win.buffer
    end

    function rt:exec_script(script)
        local lazy_block = Options.get("lazyredraw")
        if lazy_block then
            lazyredraw_block = lazyredraw_block + 1
        end

        local ok, rv = pcall(function()
            local code, err = Compiler.compile_script(script, { state = self.state })
            if not code then error(err) end
            local env = setmetatable({ runtime = self, _G = _G }, { __index = _G })
            local chunk, lerr = load(code, "excmd_compiled", "t", env)
            if not chunk then
                local path = ccvim_path .. "/log/excmd_compiled_last.lua"
                local f = fs.open(path, "w")
                if f then
                    f.write(code)
                    f.close()
                end
                LOG_DEBUG("excmd_compiled load error: %s (dumped=%s)", tostring(lerr), path)
                error(lerr)
            end
            local fn = chunk()
            self:_push_script_ctx()
            local fn_ok, fn_rv = pcall(fn, self.state, self)
            self:_pop_script_ctx()
            if not fn_ok then error(fn_rv) end
            return fn_rv
        end)

        if lazy_block then
            lazyredraw_block = lazyredraw_block - 1
        end
        if not ok then error(rv) end
        return rv
    end

    function rt:execute(expr)
        local s = tostring(expr or "")

        local function expand_execute_dollar_single_quoted(input_expr)
            local interpolated = tostring(input_expr or ""):match("^%$'(.*)'$")
            if not interpolated then
                return nil, false
            end

            local out = {}
            local i, n = 1, #interpolated
            while i <= n do
                local ch = interpolated:sub(i, i)
                local nx = (i < n) and interpolated:sub(i + 1, i + 1) or ""

                if ch == "{" and nx == "{" then
                    out[#out + 1] = "{"
                    i = i + 2
                elseif ch == "}" and nx == "}" then
                    out[#out + 1] = "}"
                    i = i + 2
                elseif ch == "{" then
                    local depth = 1
                    local j = i + 1
                    while j <= n do
                        local cj = interpolated:sub(j, j)
                        if cj == "{" then
                            depth = depth + 1
                        elseif cj == "}" then
                            depth = depth - 1
                            if depth == 0 then break end
                        end
                        j = j + 1
                    end
                    if j > n then
                        error(Error(0, "Unterminated interpolation in execute() string"))
                    end
                    local inner = interpolated:sub(i + 1, j - 1)
                    local val = self:eval_expr(inner)
                    out[#out + 1] = tostring(val)
                    i = j + 1
                else
                    out[#out + 1] = ch
                    i = i + 1
                end
            end

            return table.concat(out), true
        end

        -- Support the $'...' single-quoted execute string with
        -- interpolation (pre-JIT behavior).  Match and expand before
        -- feeding the expression parser which would otherwise treat
        -- a leading '$' as an env-var and error on $'...'.
        local line, is_interp = expand_execute_dollar_single_quoted(s)
        if is_interp then
            return self:exec_script(line)
        end

        local exprs = VimExpr.splitExpressions(s)
        if #exprs == 0 then error(Error(471, "Argument required")) end
        local parts = {}
        for i = 1, #exprs do
            local val
            local expanded, expanded_ok = expand_execute_dollar_single_quoted(exprs[i])
            if expanded_ok then
                val = expanded
            else
                val = self:eval_expr(exprs[i])
            end
            parts[#parts + 1] = tostring(val)
        end
        line = table.concat(parts, " ")
        return self:exec_script(line)
    end

    function rt:exec_verbose(level, body)
        level = tonumber(level) or 1
        body = tostring(body or ""):gsub("^%s*", "", 1)
        local prev_verbose = tonumber(Options.get("verbose", nil, nil, false, true)) or 0
        Options.set("verbose", level, false, nil, nil, true)

        local ok, rv = pcall(function()
            if body:match("^exe%c?") or body:match("^execute%s+") then
                body = body:gsub("^exe", "execute", 1)
                body = body:gsub("^execute%s+", "", 1)
                return self:execute(body)
            end
            return self:exec_script(body)
        end)

        Options.set("verbose", prev_verbose, false, nil, nil, true)
        if not ok then
            error(rv)
        end
        return rv
    end

    function rt:exec_silent(rest, is_unsilent, is_bang)
        local inner = tostring(rest or "")
        if inner == "" then
            return true
        end

        local msg = _exmsg()
        if is_unsilent then
            msg.PushUnsilent()
            local ok, rv = pcall(function()
                return self:exec_script(inner)
            end)
            msg.PopSilent()
            if not ok then
                error(rv)
            end
            return rv
        end

        msg.PushSilent({ skip_errors = is_bang, on_error = function(_m) end })
        local ok, rv = pcall(function()
            return self:exec_script(inner)
        end)
        msg.PopSilent()
        if ok then
            return rv
        end

        self.state.v.errmsg = Error.IsError(rv) and rv:toString() or tostring(rv)
        if is_bang then
            LOG_DEBUG("silent! suppressed error: %s (cmd=%s)", tostring(self.state.v.errmsg), tostring(inner))
            local ctx = build_error_context(self, { origin = { kind = "silent!" } }, self.state, inner)
            if ctx ~= "" then
                LOG_DEBUG("silent! vimscript context: %s", ctx)
            end
            return true
        end
        error(rv)
    end

    function rt:set_options(rest, mode)
        local win, buf = current_win_buf()
        mode = mode or "both"
        local args = rejoin_equals(split_set_args(tostring(rest or "")))
        for i = 1, #args do
            local tok = args[i]
            Options.exset_token(tok, mode, win, buf)
        end
        return true
    end

    local ScriptSourceMod
    local Buffer
    local Window
    local VimFn
    local VimFs
    local Tags
    local Highlight
    local LuaLoader
    local Filesystem
    local RuntimePath
    local Pack
    local Command
    local Key
    local Syntax

    local function _scriptsource()
        ScriptSourceMod = ScriptSourceMod or loadModule("lib.scriptsource")
        return ScriptSourceMod
    end

    local function _buffer_mod()
        Buffer = Buffer or loadModule("layout.buffer")
        return Buffer
    end

    local function _window_mod()
        Window = Window or loadModule("layout.window")
        return Window
    end

    local function _vimfn()
        VimFn = VimFn or loadModule("lib.luaapi.fn")
        return VimFn
    end

    local function _vimfs()
        VimFs = VimFs or loadModule("lib.luaapi.fs")
        return VimFs
    end

    local function _tags()
        Tags = Tags or loadModule("lib.tags")
        return Tags
    end

    local function _highlight()
        Highlight = Highlight or loadModule("lib.highlight")
        return Highlight
    end

    local function _lualoader()
        LuaLoader = LuaLoader or loadModule("lib.lualoader")
        return LuaLoader
    end

    local function _filesystem()
        Filesystem = Filesystem or loadModule("lib.filesystem")
        return Filesystem
    end

    local function _runtimepath()
        RuntimePath = RuntimePath or loadModule("lib.runtimepath")
        return RuntimePath
    end

    local function _pack()
        Pack = Pack or loadModule("lib.pack")
        return Pack
    end

    local function _command_mod()
        Command = Command or loadModule("lib.command")
        return Command
    end

    local function _key_mod()
        Key = Key or loadModule("lib.key")
        return Key
    end

    local function _syntax()
        Syntax = Syntax or loadModule("lib.syntax")
        return Syntax
    end

    local function _buf_ctx_from(buf)
        return { bufnr = buf.bufnr, bufname = buf.name }
    end

    local function _switch_current_buffer(win, newbuf, opts)
        opts = opts or {}
        if win.buffer == newbuf then return end
        if not opts.keepalt then
            win.altbuf = win.buffer
        end
        if not opts.skip_leave then
            Autocmd.Run("BufLeave", _buf_ctx_from(win.buffer))
        end
        win.buffer = newbuf
        _syntax().OnWindowBufferChanged(win)
        scopes.w.current_syntax = nil
        if not opts.skip_enter then
            Autocmd.Run("BufEnter", _buf_ctx_from(newbuf))
        end
    end

    local function _resolve_find_name(raw)
        local target = strip(raw)
        if target == "" then
            return nil, Error(471)
        end
        local found = _vimfn().fn.findfile(target)
        if not found or found == "" then
            return nil, Error(484, target)
        end
        return found, nil
    end

    local function _find_window_for_path(target_abs)
        local fsmod = _vimfs()
        for _, win in pairs(windows) do
            local name = win.buffer.name
            if type(name) == "string" and name ~= "" then
                local ok, buf_abs = pcall(fsmod.abspath, name)
                if ok and buf_abs == target_abs then
                    return win
                end
            end
        end
        return nil
    end

    local function _cleanup_failed_split_window(win)
        if not win then
            return
        end
        if windows[win.winnr] == win then
            windows[win.winnr] = nil
        end
        local buf = win.buffer
        buf.refcount = math.max(0, buf.refcount - 1)
    end

    local function _split_preflight(target_winnr, refwin, vertical)
        local tabp = tabpages[curtp]
        if not tabp then
            return false
        end
        local probe = tabp:MakeSplitProbe(refwin)
        return tabp:WinSplit(target_winnr, probe, vertical, { dry_run = true }) == true
    end

    local function _split_real(target_winnr, newwin, vertical)
        local tabp = tabpages[curtp]
        if not tabp then
            _cleanup_failed_split_window(newwin)
            return false
        end
        local ok = tabp:WinSplit(target_winnr, newwin, vertical)
        if not ok then
            _cleanup_failed_split_window(newwin)
            return false
        end
        return true
    end

    local function _edit_buffer_name(win, newname, bang)
        if newname == win.buffer.name or newname == "" then
            _syntax().OnWindowBufferChanged(win)
            scopes.w.current_syntax = nil
            win.buffer:Load(true)
        else
            local status = win.buffer:leave(bang, nil, "autowriteall")
            if status ~= true then
                return status
            end

            local newbuf = _buffer_mod()(true, false)
            newbuf.name = newname
            if newbuf.opts and newbuf.opts.buflisted then
                Autocmd.Run("BufAdd", _buf_ctx_from(newbuf))
            end
            _switch_current_buffer(win, newbuf, { skip_enter = true })
            newbuf:Load(true)
            Autocmd.Run("BufEnter", _buf_ctx_from(newbuf))
        end

        win:cursorSet(1, 1)
        win:mark_redraw()
        return true
    end

    local function _to_string_simple(v)
        local t = type(v)
        if t == "nil" then return "null" end
        if t == "boolean" then return v and "true" or "false" end
        return tostring(v)
    end

    local function _scan_range_prefix(text, line_count, current_line)
        local i, n = 1, #text
        local function skip_ws()
            while i <= n and text:sub(i, i):match("%s") do
                i = i + 1
            end
        end
        local function parse_addr()
            skip_ws()
            local c = text:sub(i, i)
            if c == "%" then
                i = i + 1
                return 1, line_count, true, "%"
            end
            if c == "." then
                i = i + 1
                return current_line, current_line, true, "."
            end
            if c == "$" then
                i = i + 1
                return line_count, line_count, true, "$"
            end
            if c:match("%d") then
                local j = i
                while i <= n and text:sub(i, i):match("%d") do
                    i = i + 1
                end
                local num = tonumber(text:sub(j, i - 1))
                return num, num, true, "number"
            end
            return nil, nil, false, nil
        end

        local l1, l2, ok, kind1 = parse_addr()
        if not ok then
            return nil, nil, false, i, nil, false
        end
        skip_ws()
        local sep = text:sub(i, i)
        if sep == "," or sep == ";" then
            i = i + 1
            local r1, r2, ok2 = parse_addr()
            if ok2 then
                return l1, r2 or r1, true, i, kind1, true
            end
        end
        return l1, l2, true, i, kind1, false
    end

    local function _cursor_parse_head(cursor, win)
        local line_count = win.buffer:line_count(true)
        if line_count < 1 then
            line_count = 1
        end
        local text = lstrip(tostring((cursor and cursor.text) or ""))
        while text:sub(1, 1) == ":" do
            text = lstrip(text:sub(2))
        end
        local l1, l2, has_range, pos = _scan_range_prefix(text, line_count, win.cursory)
        if has_range then
            text = text:sub(pos)
        end
        text = lstrip(text)
        while text:sub(1, 1) == ":" do
            text = lstrip(text:sub(2))
        end
        local raw = text:match("^([%a][%w]*)")
        return raw and raw:lower(), l1, l2, has_range
    end

    local function _structured_range_from_spec(spec)
        if type(spec) ~= "table" then
            return nil, nil, false, nil
        end

        if spec.line1 ~= nil or spec.line2 ~= nil then
            local line1 = tonumber(spec.line1)
            local line2 = tonumber(spec.line2 or spec.line1)
            if not line1 or not line2 then
                return nil, nil, false, "Invalid 'range'"
            end
            return line1, line2, true, nil
        end

        local range = spec.range
        if range == nil then
            return nil, nil, false, nil
        end

        if type(range) == "number" then
            return range, range, true, nil
        end

        if type(range) == "table" then
            if #range == 1 then
                local line = tonumber(range[1])
                if line then
                    return line, line, true, nil
                end
            elseif #range == 2 then
                local line1 = tonumber(range[1])
                local line2 = tonumber(range[2])
                if line1 and line2 then
                    return line1, line2, true, nil
                end
            end
        end

        return nil, nil, false, "Invalid 'range'"
    end

    local function _build_cmd_context(cursor, win, spec)
        local raw_cmd, raw_l1, raw_l2, has_raw_range = _cursor_parse_head(cursor, win)
        local name = tostring((spec and (spec.dispatch or spec.lname or spec.name)) or raw_cmd or ""):lower()
        local cmd_spec = get_command_spec(name)
        local addr_mode = cmd_spec and cmd_spec.addr
        local ctx = {
            raw_cmd = raw_cmd,
            line1 = nil,
            line2 = nil,
            range = 0,
            count = nil,
        }

        if has_raw_range then
            if name == "" then
                ctx.line1 = raw_l1
                ctx.line2 = raw_l2
                ctx.range = (raw_l1 == raw_l2) and 1 or 2
            elseif addr_mode == "none" then
                error(Error(481, tostring((cursor and cursor.text) or "")))
            elseif addr_mode == "count" then
                ctx.count = raw_l2
            else
                ctx.line1 = raw_l1
                ctx.line2 = raw_l2
                ctx.range = (raw_l1 == raw_l2) and 1 or 2
            end
        end

        if type(spec) == "table" then
            if spec.count ~= nil then
                local count = tonumber(spec.count)
                if not count then
                    error("Invalid 'count'")
                end
                if addr_mode == "count" then
                    ctx.count = count
                else
                    error("Command cannot accept count: " .. name)
                end
            end

            local line1, line2, has_structured_range, range_err = _structured_range_from_spec(spec)
            if range_err then
                error(range_err)
            end
            if has_structured_range then
                if addr_mode == "line" then
                    ctx.line1 = line1
                    ctx.line2 = line2
                    ctx.range = (line1 == line2) and 1 or 2
                elseif addr_mode == "count" then
                    ctx.count = line2
                elseif addr_mode == "none" or addr_mode == nil then
                    error("Command cannot accept range: " .. name)
                else
                    error("Invalid 'range'")
                end
            end
        end

        return ctx
    end

    local function _parse_copy_move_target(raw, win)
        local text = lstrip(tostring(raw or ""))
        if text == "" then
            return nil, Error(16)
        end

        local line_count = win.buffer:line_count(true)
        if line_count < 1 then
            line_count = 1
        end

        local c = text:sub(1, 1)
        local target
        if c == "." then
            target = win.cursory
        elseif c == "$" then
            target = line_count
        elseif c:match("%d") then
            local digits = text:match("^(%d+)")
            target = tonumber(digits)
            if target > line_count then
                return nil, Error(16)
            end
        else
            return nil, Error(16)
        end

        if target < 0 then
            return nil, Error(16)
        end
        return target, nil
    end

    local function _delete_suffix_mode(raw_cmd)
        if not raw_cmd or #raw_cmd < 2 then
            return nil
        end
        local tail = raw_cmd:sub(-1)
        if tail ~= "l" and tail ~= "p" then
            return nil
        end
        local base = raw_cmd:sub(1, -2)
        local delete_name = "delete"
        if delete_name:sub(1, #base) == base and delete_name:sub(1, #raw_cmd) ~= raw_cmd then
            if tail == "l" then
                return "list"
            end
            return "print"
        end
        return nil
    end

    local function _parse_delete_args(raw)
        local tokens = split_ws(raw)
        local reg = '"'
        local explicit_reg = false
        local count = nil

        if #tokens == 1 then
            if tokens[1]:match("^%d+$") then
                count = tonumber(tokens[1])
            elseif #tokens[1] == 1 then
                reg = tokens[1]
                explicit_reg = true
            else
                return nil, nil, nil, Error(474, raw)
            end
        elseif #tokens == 2 then
            if #tokens[1] ~= 1 or not tokens[2]:match("^%d+$") then
                return nil, nil, nil, Error(474, raw)
            end
            reg = tokens[1]
            explicit_reg = true
            count = tonumber(tokens[2])
        elseif #tokens > 2 then
            return nil, nil, nil, Error(474, raw)
        end

        if count and count < 1 then
            return nil, nil, nil, Error(474, raw)
        end

        return reg, explicit_reg, count, nil
    end

    local function _store_deleted_lines(reg, explicit_reg, lines)
        local function rotate_numbered()
            for i = 9, 2, -1 do
                registers[i] = registers[i - 1]
            end
            registers[1] = { "linewise", lines }
        end

        if reg == "_" then
            return
        end
        if reg == '"' then
            registers["unnamed"] = { "linewise", lines }
            if not explicit_reg then
                rotate_numbered()
            end
            return
        end
        if reg:match("^%u$") then
            local key = reg:lower()
            local cur = registers[key]
            if type(cur) == "table" and cur[1] == "linewise" and type(cur[2]) == "table" then
                local merged = {}
                for i = 1, #cur[2] do
                    merged[#merged + 1] = cur[2][i]
                end
                for i = 1, #lines do
                    merged[#merged + 1] = lines[i]
                end
                lines = merged
            end
            registers[key] = { "linewise", lines }
            registers["unnamed"] = { "linewise", lines }
            rotate_numbered()
            return
        end
        registers[reg] = { "linewise", lines }
        registers["unnamed"] = { "linewise", lines }
        if explicit_reg and not reg:match("^%d$") and reg ~= "-" then
            rotate_numbered()
        end
    end

    local function _put_register_key(reg)
        if reg == '"' then
            return "unnamed"
        end
        if reg:match("^%a$") then
            return reg:lower()
        end
        if reg:match("^%d$") then
            return tonumber(reg)
        end
        return reg
    end

    local function _copy_lines_from_list(src)
        local out = {}
        for i = 1, #src do
            out[#out + 1] = tostring(src[i] or "")
        end
        return out
    end

    local function _split_text_lines(text)
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

    local function _parse_delimited_part(raw, start_idx, delim)
        local out = {}
        local i = start_idx
        local n = #raw
        while i <= n do
            local ch = raw:sub(i, i)
            if ch == "\\" then
                local nxt = raw:sub(i + 1, i + 1)
                if nxt == "" then
                    out[#out + 1] = "\\"
                    i = i + 1
                elseif nxt == delim then
                    out[#out + 1] = nxt
                    i = i + 2
                elseif nxt == "\\" then
                    out[#out + 1] = "\\"
                    i = i + 2
                else
                    out[#out + 1] = "\\"
                    out[#out + 1] = nxt
                    i = i + 2
                end
            elseif ch == delim then
                return table.concat(out), i + 1, nil
            else
                out[#out + 1] = ch
                i = i + 1
            end
        end
        return nil, start_idx, Error(474, raw)
    end

    local function _parse_global_pattern_and_cmd(raw)
        local s = lstrip(tostring(raw or ""))
        local delim = s:sub(1, 1)
        if delim == "" or delim:match("[%w%s]") or delim == "\\" or delim == '"' or delim == "|" or delim == "!" then
            return nil, nil, Error(474, raw)
        end

        local pat, next_idx, perr = _parse_delimited_part(s, 2, delim)
        if Error.IsError(perr) then
            return nil, nil, perr
        end
        local cmd = strip(s:sub(next_idx))
        return pat, cmd, nil
    end

    local SUB_FLAG_ALLOWED = {
        ["&"] = true,
        c = true,
        e = true,
        g = true,
        i = true,
        I = true,
        n = true,
        p = true,
        ["#"] = true,
        l = true,
        r = true,
    }

    local function _parse_substitute_flag_count(tail)
        local s = lstrip(tostring(tail or ""))
        local flags = {}
        local i = 1
        local n = #s

        if i <= n and s:sub(i, i) == "&" then
            flags[#flags + 1] = "&"
            i = i + 1
        end

        while i <= n do
            local ch = s:sub(i, i)
            if not SUB_FLAG_ALLOWED[ch] or ch == "&" then
                break
            end
            flags[#flags + 1] = ch
            i = i + 1
        end

        local rest = strip(s:sub(i))
        local count = nil
        if rest ~= "" then
            if not rest:match("^%d+$") then
                return nil, nil, Error(474, tail)
            end
            count = tonumber(rest)
            if count < 1 then
                return nil, nil, Error(474, tail)
            end
        end

        return table.concat(flags), count, nil
    end

    local function _parse_substitute_args(raw)
        local s = lstrip(tostring(raw or ""))
        if s == "" then
            return {
                repeat_last = true,
                flags = "",
                keep_flags = false,
                count = nil,
            }, nil
        end

        local delim = s:sub(1, 1)
        if delim == "" then
            return nil, Error(474, raw)
        end

        local is_delimiter = (not delim:match("[%w%s]")) and delim ~= "\\" and delim ~= '"' and delim ~= "|"
        if not is_delimiter then
            local rep_flags, rep_count, ferr = _parse_substitute_flag_count(s)
            if Error.IsError(ferr) then
                return nil, ferr
            end
            local keep_prev = rep_flags:sub(1, 1) == "&"
            local flags = keep_prev and rep_flags:sub(2) or rep_flags
            return {
                repeat_last = true,
                flags = flags,
                keep_flags = keep_prev,
                count = rep_count,
            }, nil
        end

        local pattern, after_pat, perr = _parse_delimited_part(s, 2, delim)
        if Error.IsError(perr) then
            pattern = s:sub(2)
            after_pat = #s + 1
        end

        local replacement, after_repl, rerr = _parse_delimited_part(s, after_pat, delim)
        if Error.IsError(rerr) then
            replacement = s:sub(after_pat)
            after_repl = #s + 1
        end

        local flag_str, count, ferr = _parse_substitute_flag_count(s:sub(after_repl))
        if Error.IsError(ferr) then
            return nil, ferr
        end
        local keep_prev = flag_str:sub(1, 1) == "&"
        local flags = keep_prev and flag_str:sub(2) or flag_str

        if pattern == "" then
            pattern = Runtime._LAST_SEARCH_PATTERN
            if pattern == "" then
                pattern = Runtime._LAST_SUBSTITUTE_PATTERN
            end
        end

        return {
            repeat_last = false,
            pattern = pattern,
            replacement = replacement,
            flags = flags,
            keep_flags = keep_prev,
            count = count,
        }, nil
    end

    local function _substitute_case_sensitive(flags)
        local case_sensitive = not truthy(Options.get("ignorecase"))
        for i = 1, #flags do
            local ch = flags:sub(i, i)
            if ch == "i" then
                case_sensitive = false
            elseif ch == "I" then
                case_sensitive = true
            end
        end
        return case_sensitive
    end

    local function _expand_substitute_replacement(replacement, match_text, caps)
        local out = {}
        local i = 1
        local n = #replacement
        while i <= n do
            local ch = replacement:sub(i, i)
            if ch == "&" then
                out[#out + 1] = match_text
                i = i + 1
            elseif ch == "\\" then
                local nxt = replacement:sub(i + 1, i + 1)
                if nxt == "" then
                    out[#out + 1] = "\\"
                    i = i + 1
                elseif nxt:match("%d") then
                    local idx = tonumber(nxt)
                    if idx == 0 then
                        out[#out + 1] = match_text
                    elseif type(caps) == "table" and caps[idx] ~= nil then
                        out[#out + 1] = tostring(caps[idx])
                    end
                    i = i + 2
                elseif nxt == "&" then
                    out[#out + 1] = "&"
                    i = i + 2
                elseif nxt == "n" then
                    out[#out + 1] = "\n"
                    i = i + 2
                elseif nxt == "r" then
                    out[#out + 1] = "\r"
                    i = i + 2
                elseif nxt == "t" then
                    out[#out + 1] = "\t"
                    i = i + 2
                else
                    out[#out + 1] = nxt
                    i = i + 2
                end
            else
                out[#out + 1] = ch
                i = i + 1
            end
        end
        return table.concat(out)
    end

    local function _substitute_line(compiled, text, replacement, case_sensitive, do_global)
        local line = tostring(text or "")
        local out = {}
        local next_pos = 1
        local subs = 0
        local line_len = #line

        while next_pos <= line_len + 1 do
            local s, e, caps, emsg = VimRegex.find_compiled_with_caps(line, compiled, case_sensitive, nil, next_pos)
            if emsg then
                return nil, subs, Error(474, emsg)
            end
            if not s then
                out[#out + 1] = line:sub(next_pos)
                break
            end

            if s > next_pos then
                out[#out + 1] = line:sub(next_pos, s - 1)
            end

            local match_text = line:sub(s, e)
            out[#out + 1] = _expand_substitute_replacement(replacement, match_text, caps)
            subs = subs + 1

            if not do_global then
                out[#out + 1] = line:sub(e + 1)
                break
            end

            local advance = e + 1
            if advance <= s then
                if s <= line_len then
                    out[#out + 1] = line:sub(s, s)
                    advance = s + 1
                else
                    advance = line_len + 1
                end
            end
            next_pos = advance
        end

        return table.concat(out), subs, nil
    end

    local function _read_put_register_lines(self, reg)
        if reg == "%" then
            return { tostring(windows[curwin].buffer.name or "") }, nil
        end
        if reg == "#" then
            local alt = windows[curwin].altbuf
            if type(alt) == "number" then
                alt = buffers[alt]
            end
            if type(alt) == "table" then
                return { tostring(alt.name or "") }, nil
            end
            return { "" }, nil
        end
        if reg == ":" then
            local cursor = self:get_exec_cursor()
            return { tostring((cursor and cursor.text) or "") }, nil
        end

        local key = _put_register_key(reg)
        local regval = registers[key]
        if regval == nil then
            return nil, Error(353, reg)
        end

        if type(regval) ~= "table" then
            return _split_text_lines(tostring(regval)), nil
        end

        local kind = regval[1]
        local payload = regval[2]
        if (kind == "linewise" or kind == "inline") and type(payload) == "table" then
            return _copy_lines_from_list(payload), nil
        end
        if kind == "charwise" and type(payload) == "string" then
            return _split_text_lines(payload), nil
        end
        if type(payload) == "table" then
            return _copy_lines_from_list(payload), nil
        end
        return _split_text_lines(tostring(payload or "")), nil
    end

    function rt:put(argstr, bang, cmdctx)
        local raw = strip(argstr)
        local source_kind = "register"
        local reg = '"'
        local expr = nil

        if raw ~= "" then
            if raw:sub(1, 1) == "=" then
                source_kind = "expr"
                expr = strip(raw:sub(2))
            elseif #raw == 1 then
                reg = raw
            else
                return Error(488, raw)
            end
        else
            local reg_default = '"'
            if Options.resolve_abbrev("clipboard") then
                local cb = tostring(Options.get("clipboard") or "")
                if cb:find("unnamedplus", 1, true) then
                    reg_default = "+"
                elseif cb:find("unnamed", 1, true) then
                    reg_default = "*"
                end
            end
            reg = reg_default
        end

        local lines
        if source_kind == "expr" then
            local put_expr = expr
            if put_expr == "" then
                put_expr = Runtime._LAST_PUT_EXPR
            else
                Runtime._LAST_PUT_EXPR = put_expr
            end

            local value = ""
            if put_expr ~= "" then
                value = self:eval_expr(put_expr)
            end

            if type(value) == "table" and not value.__call then
                lines = _copy_lines_from_list(value)
            else
                lines = _split_text_lines(tostring(value or ""))
            end
        else
            local reg_lines, rerr = _read_put_register_lines(self, reg)
            if Error.IsError(rerr) then
                return rerr
            end
            lines = reg_lines
        end

        if #lines == 0 then
            return true
        end

        local win = windows[curwin]
        local buf = win.buffer
        local line = cmdctx.line2 or win.cursory
        local insert_before = bang and line or (line + 1)
        if insert_before < 1 then
            insert_before = 1
        end

        local start0 = insert_before - 1
        buf:set_lines(start0, start0, false, lines)
        local target_line = insert_before + #lines - 1
        if target_line < 1 then
            target_line = 1
        end
        win:cursorSet(1, target_line)
        win:mark_redraw()
        return true
    end

    function rt:substitute(argstr, _bang, cmdctx)
        local spec, perr = _parse_substitute_args(argstr)
        if Error.IsError(perr) then
            return perr
        end

        local pattern
        local replacement
        local flags = spec.flags or ""
        local count
        if spec.repeat_last then
            pattern = Runtime._LAST_SUBSTITUTE_PATTERN
            replacement = Runtime._LAST_SUBSTITUTE_REPL
            if spec.keep_flags then
                flags = tostring(Runtime._LAST_SUBSTITUTE_FLAGS or "") .. flags
            end
            count = spec.count
        else
            pattern = spec.pattern
            replacement = spec.replacement
            if spec.keep_flags then
                flags = tostring(Runtime._LAST_SUBSTITUTE_FLAGS or "") .. flags
            end
            count = spec.count
        end

        if pattern == "" then
            pattern = Runtime._LAST_SEARCH_PATTERN
        end
        if pattern == "" then
            pattern = Runtime._LAST_SUBSTITUTE_PATTERN
        end
        if pattern == "" then
            return Error(486, "")
        end

        Runtime._LAST_SUBSTITUTE_PATTERN = pattern
        Runtime._LAST_SUBSTITUTE_REPL = replacement
        Runtime._LAST_SUBSTITUTE_FLAGS = flags
        Runtime._LAST_SEARCH_PATTERN = pattern

        local win = windows[curwin]
        local buf = win.buffer
        local line_count = buf:line_count(true)
        if line_count < 1 then
            line_count = 1
        end
        local line1 = cmdctx.line1 or win.cursory
        local line2 = cmdctx.line2 or line1

        if count then
            line2 = line1 + count - 1
        end

        if line1 < 1 then line1 = 1 end
        if line1 > line_count then line1 = line_count end
        if line2 < 1 then line2 = 1 end
        if line2 > line_count then line2 = line_count end
        if line2 < line1 then line2 = line1 end

        local compiled, emsg = VimRegex.compile(pattern)
        if not compiled then
            return Error(474, emsg or pattern)
        end
        if replacement:find("\\%d") ~= nil then
            local vm_compiled = select(1, VimRegex.compile_vm(pattern))
            if vm_compiled then
                compiled = vm_compiled
            end
        end

        local do_global = truthy(Options.get("gdefault"))
        for i = 1, #flags do
            if flags:sub(i, i) == "g" then
                do_global = not do_global
            end
        end
        local suppress_not_found = flags:find("e", 1, true) ~= nil
        local count_only = flags:find("n", 1, true) ~= nil
        local case_sensitive = _substitute_case_sensitive(flags)

        local new_lines = {}
        local changed = false
        local total_subs = 0
        for i = line1, line2 do
            local current = buf:get_line(i, true) or ""
            local next_line, subs, lerr = _substitute_line(compiled, current, replacement, case_sensitive, do_global)
            if Error.IsError(lerr) then
                return lerr
            end
            total_subs = total_subs + subs
            if count_only then
                new_lines[#new_lines + 1] = current
            else
                new_lines[#new_lines + 1] = next_line
                if subs > 0 and next_line ~= current then
                    changed = true
                end
            end
        end

        if total_subs == 0 and not suppress_not_found then
            return Error(486, pattern)
        end

        if (not count_only) and changed then
            buf:set_lines(line1 - 1, line2, false, new_lines)
            win:mark_redraw()
        end
        return true
    end

    function rt:global(argstr, bang, cmdctx)
        local pattern, cmd, perr = _parse_global_pattern_and_cmd(argstr)
        if Error.IsError(perr) then
            return perr
        end

        if pattern == "" then
            pattern = Runtime._LAST_SEARCH_PATTERN
        end
        if pattern == "" then
            return Error(486, "")
        end
        Runtime._LAST_SEARCH_PATTERN = pattern
        Runtime._LAST_SUBSTITUTE_PATTERN = pattern

        local compiled, emsg = VimRegex.compile(pattern)
        if not compiled then
            return Error(474, emsg or pattern)
        end

        local win = windows[curwin]
        local buf = win.buffer
        local line_count = buf:line_count(true)
        if line_count < 1 then
            line_count = 1
        end
        local line1 = cmdctx.line1 or 1
        local line2 = cmdctx.line2 or line_count
        if line1 < 1 then line1 = 1 end
        if line1 > line_count then line1 = line_count end
        if line2 < 1 then line2 = 1 end
        if line2 > line_count then line2 = line_count end
        if line2 < line1 then line2 = line1 end

        local case_sensitive = not truthy(Options.get("ignorecase"))
        local matched_lines = {}
        for i = line1, line2 do
            local s = VimRegex.find_compiled(buf:get_line(i, true) or "", compiled, case_sensitive)
            local matched = s ~= nil
            if bang then
                matched = not matched
            end
            if matched then
                matched_lines[#matched_lines + 1] = i
            end
        end

        local line_bias = 0
        local inner = cmd
        for i = 1, #matched_lines do
            local line_no = matched_lines[i] + line_bias
            local before = buf:line_count(true)
            if before < 1 then
                before = 1
            end
            if line_no < 1 then
                line_no = 1
            end
            if line_no > before then
                line_no = before
            end

            win:cursorSet(win.cursorx, line_no)
            if inner == "" then
                _exmsg().echo(buf:get_line(line_no, true) or "")
            else
                local ok, rv = pcall(function()
                    return self:exec_script(inner)
                end)
                if not ok then
                    self.state.v.errmsg = Error.IsError(rv) and rv:toString() or tostring(rv)
                end
            end

            local after = buf:line_count(true)
            line_bias = line_bias + (after - before)
        end

        return true
    end

    function rt:sort(argstr, bang, cmdctx)
        local raw = strip(argstr)
        local ignorecase = false
        local numeric = false
        local reverse = not not bang

        for i = 1, #raw do
            local ch = raw:sub(i, i)
            if ch == "i" then
                ignorecase = true
            elseif ch == "n" then
                numeric = true
            elseif ch == "r" then
                reverse = true
            else
                error(("Unknown ch in sort! CH=%s INPUT=%s"):format(ch, raw))
            end
        end

        local win = windows[curwin]
        local buf = win.buffer
        local line_count = buf:line_count(true)
        if line_count < 1 then
            line_count = 1
        end

        local line1 = cmdctx.line1 or 1
        local line2 = cmdctx.line2 or line_count
        if line1 < 1 then line1 = 1 end
        if line1 > line_count then line1 = line_count end
        if line2 < 1 then line2 = 1 end
        if line2 > line_count then line2 = line_count end
        if line2 < line1 then
            line1, line2 = line2, line1
        end

        local rows = {}
        for i = line1, line2 do
            local text = tostring(buf:get_line(i, true) or "")
            local key = text
            local nkey = nil
            if numeric then
                local m = text:match("^%s*([+-]?%d+%.?%d*)")
                nkey = tonumber(m) or 0
            elseif ignorecase then
                key = key:lower()
            end
            rows[#rows + 1] = {
                line = text,
                key = key,
                nkey = nkey,
                idx = i,
            }
        end

        table.sort(rows, function(a, b)
            if numeric then
                if a.nkey ~= b.nkey then
                    if reverse then
                        return a.nkey > b.nkey
                    end
                    return a.nkey < b.nkey
                end
            else
                if a.key ~= b.key then
                    if reverse then
                        return a.key > b.key
                    end
                    return a.key < b.key
                end
            end
            return a.idx < b.idx
        end)

        local out = {}
        for i = 1, #rows do
            out[i] = rows[i].line
        end

        buf:set_lines(line1 - 1, line2, false, out)
        win:cursorSet(1, line1)
        win:mark_redraw()
        return true
    end

    local function _file_display_name(name, bang)
        local display = name
        if display == "" then
            return "[No Name]"
        end
        if bang then
            return display
        end
        local shortmess = tostring(Options.get("shortmess") or "")
        if shortmess:find("t", 1, true) then
            local width = screen.width
            local max_len = math.max(20, width - 2)
            if #display > max_len then
                display = "<" .. display:sub(#display - max_len + 2)
            end
        end
        return display
    end

    local function _file_status_message(win, bang)
        local buf = win.buffer
        local shortmess = tostring(Options.get("shortmess") or "")
        local out = { '"' .. _file_display_name(buf.name, bang) .. '"' }
        if Options.get("readonly", nil, buf) then
            out[#out + 1] = shortmess:find("r", 1, true) and "[RO]" or "[readonly]"
        end
        if buf.opts.modified then
            out[#out + 1] = shortmess:find("m", 1, true) and "[+]" or "[Modified]"
        end
        local line_count = buf:line_count(true)
        if line_count > 0 then
            if shortmess:find("l", 1, true) then
                out[#out + 1] = tostring(line_count) .. "L"
            else
                out[#out + 1] = tostring(line_count) .. " line" .. (line_count == 1 and "" or "s")
            end
            out[#out + 1] = "--" .. tostring(math.floor(win.cursory / line_count * 100)) .. "%--"
        else
            out[#out + 1] = "--No lines in buffer--"
        end
        return table.concat(out, " ")
    end

    local function _delete_list_text(line)
        local text = tostring(line or "")
        local out = { ">" }
        local col = 2
        for i = 1, #text do
            local ch = text:sub(i, i)
            if ch == "\t" then
                local spaces = 8 - ((col - 1) % 8)
                out[#out + 1] = string.rep(" ", spaces)
                col = col + spaces
            else
                out[#out + 1] = ch
                col = col + 1
            end
        end
        return table.concat(out)
    end

    local function _delete_print_text(line)
        local text = tostring(line or "")
        local out = {}
        local col = 1
        for i = 1, #text do
            local ch = text:sub(i, i)
            if ch == "\t" then
                local spaces = 8 - ((col - 1) % 8)
                out[#out + 1] = string.rep(" ", spaces)
                col = col + spaces
            else
                out[#out + 1] = ch
                col = col + 1
            end
        end
        return table.concat(out)
    end

    local function _csv_first(value)
        return strip((tostring(value or ""):match("^([^,]+)") or ""))
    end

    local function _parse_redir_spec(raw)
        local s = strip(raw)
        if s == "" then
            return nil, Error(471)
        end
        if s:upper() == "END" then
            return { kind = "end" }, nil
        end

        if s:sub(1, 3) == "=>>" then
            local name = strip(s:sub(4))
            if name == "" then
                return nil, Error(471)
            end
            return { kind = "var", append = true, name = name }, nil
        end
        if s:sub(1, 2) == "=>" then
            local name = strip(s:sub(3))
            if name == "" then
                return nil, Error(471)
            end
            return { kind = "var", append = false, name = name }, nil
        end

        if s:sub(1, 2) == ">>" then
            local path = strip(s:sub(3))
            if path == "" then
                return nil, Error(471)
            end
            return { kind = "file", append = true, path = path }, nil
        end
        if s:sub(1, 1) == ">" then
            local path = strip(s:sub(2))
            if path == "" then
                return nil, Error(471)
            end
            return { kind = "file", append = false, path = path }, nil
        end

        if s:sub(1, 1) == "@" then
            local tail = strip(s:sub(2))
            if tail == "" then
                return nil, Error(471)
            end
            local reg = tail:sub(1, 1)
            local rest = strip(tail:sub(2))
            local append = reg:match("^%u$") ~= nil

            if rest == "" or rest == ">" then
                return { kind = "register", append = append, reg = reg }, nil
            end
            if rest == ">>" then
                return { kind = "register", append = true, reg = reg }, nil
            end
            return nil, Error(488, rest)
        end

        return nil, Error(474, raw)
    end

    local function _redir_register_key(reg)
        if reg == '"' then
            return "unnamed"
        end
        if reg:match("^%a$") then
            return reg:lower()
        end
        if reg:match("^%d$") then
            return tonumber(reg)
        end
        return reg
    end

    local function _redir_register_text(reg)
        local key = _redir_register_key(reg)
        local rv = registers[key]
        if rv == nil then
            return ""
        end
        if type(rv) == "table" then
            local payload = rv[2]
            if type(payload) == "table" then
                return table.concat(payload, "\n")
            end
            if type(payload) == "string" then
                return payload
            end
            return tostring(payload)
        end
        return tostring(rv)
    end

    local function _redir_text_to_lines(text)
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

    local function _eval_expr_for_cmd(expr_str)
        return rt:eval_expr(expr_str)
    end

    local MAP_ARG_OPTIONS = {
        buffer = true,
        silent = true,
        expr = true,
        script = true,
        unique = true,
        nowait = true,
        special = true,
    }

    local function _map_command_opts(opts)
        if opts and opts.buffer then
            return { buffer_local = true }
        end
        return nil
    end

    local function _consume_map_options(raw)
        local opts = {}
        local i, n = 1, #raw

        while true do
            while i <= n and raw:sub(i, i):match("%s") do i = i + 1 end
            local consumed = false

            while i <= n and raw:sub(i, i) == "<" do
                local j = raw:find(">", i + 1, true)
                if not j then break end
                local name = raw:sub(i + 1, j - 1):lower()
                if not MAP_ARG_OPTIONS[name] then break end
                opts[name] = true
                i = j + 1
                consumed = true
                while i <= n and raw:sub(i, i):match("%s") do i = i + 1 end
            end

            if not consumed then break end
        end

        return opts, raw:sub(i)
    end

    local function _parse_map_lhs_rhs(raw)
        local opts, tail = _consume_map_options(raw)
        tail = lstrip(tail)
        if tail == "" then return { lhs = nil, rhs = nil, opts = opts } end
        local lhs, rhs = tail:match("^(%S+)%s*(.*)$")
        if not lhs or lhs == "" then
            return nil, Error(474, "Argument required")
        end
        if rhs == "" then
            return { lhs = lhs, rhs = nil, opts = opts }
        end
        return { lhs = lhs, rhs = rhs, opts = opts }
    end

    local function _parse_unmap_lhs(raw)
        local opts, tail = _consume_map_options(raw)
        tail = lstrip(tail)
        if tail == "" then
            return nil, Error(474, "Argument required")
        end
        local lhs = tail:match("^(%S+)")
        if not lhs or lhs == "" then
            return nil, Error(474, "Argument required")
        end
        return lhs, nil, opts
    end

    local function _strtoseq_tolerant(s)
        local KeyMod = _key_mod()
        local seq = {}
        local i, n = 1, #s

        local function append_seq(src)
            for j = 1, #src do
                seq[#seq + 1] = src[j]
            end
        end

        while i <= n do
            local ch = s:sub(i, i)
            if ch ~= "<" then
                local j = s:find("<", i, true) or (n + 1)
                local ok, part = pcall(KeyMod.strtoseq, s:sub(i, j - 1))
                if not ok then
                    return nil, Error(474, tostring(part))
                end
                append_seq(part)
                i = j
            else
                local j = s:find(">", i + 1, true)
                if not j then
                    local ok, part = pcall(KeyMod.strtoseq, "<lt>")
                    if not ok then
                        return nil, Error(474, tostring(part))
                    end
                    append_seq(part)
                    i = i + 1
                else
                    local token = s:sub(i, j)
                    local ok, part = pcall(KeyMod.strtoseq, token)
                    if ok then
                        append_seq(part)
                    else
                        local literal = "<lt>" .. s:sub(i + 1, j)
                        local ok2, part2 = pcall(KeyMod.strtoseq, literal)
                        if not ok2 then
                            return nil, Error(474, tostring(part2))
                        end
                        append_seq(part2)
                    end
                    i = j + 1
                end
            end
        end

        return seq, nil
    end

    local function _strtoseq_normal_literal(s)
        local KeyMod = _key_mod()
        local escaped = tostring(s or ""):gsub("<", "<lt>")
        local ok, seq = pcall(KeyMod.strtoseq, escaped)
        if not ok then
            return nil, Error(474, tostring(seq))
        end
        return seq, nil
    end

    local function _expand_map_sid(text)
        if type(text) ~= "string" or text == "" then
            return text, nil
        end
        if not text:lower():find("<sid>", 1, true) then
            return text, nil
        end

        local sid = script_sid_for_state(rt.state)
        if not sid then
            return nil, Error(81, "Using <SID> not in a script context")
        end
        local snr_prefix = "<SNR>" .. tostring(sid) .. "_"
        return (text:gsub("<[sS][iI][dD]>", snr_prefix)), nil
    end

    local function _run_map_ex_command(cmd_name, argstr, bang)
        local spec = MAP_COMMAND_SPECS[cmd_name]
        local modes = spec.modes
        if bang then
            if not spec.bang_modes then
                return Error(474, "No ! allowed")
            end
            modes = spec.bang_modes
        end

        local CommandMod = _command_mod()
        local raw = strip(argstr)

        if spec.action == "clear" then
            local opts = _consume_map_options(raw)
            CommandMod.clear_mappings(modes, _map_command_opts(opts))
            return true
        end

        if spec.action == "unmap" then
            local lhs, perr, opts = _parse_unmap_lhs(raw)
            if Error.IsError(perr) then return perr end
            local lhs_expanded, serr = _expand_map_sid(lhs)
            if Error.IsError(serr) then return serr end
            local lhs_seq, lerr = _strtoseq_tolerant(lhs_expanded)
            if Error.IsError(lerr) then return lerr end
            CommandMod.unmap_keys(modes, lhs_seq, _map_command_opts(opts))
            return true
        end

        if raw == "" then
            return true
        end

        local parsed, perr = _parse_map_lhs_rhs(raw)
        if Error.IsError(perr) then return perr end
        if not parsed or not parsed.lhs or parsed.rhs == nil then
            return true
        end

        local lhs_expanded, lserr = _expand_map_sid(parsed.lhs)
        if Error.IsError(lserr) then return lserr end
        local rhs_expanded, rserr = _expand_map_sid(parsed.rhs)
        if Error.IsError(rserr) then return rserr end

        local lhs_seq, lerr = _strtoseq_tolerant(lhs_expanded)
        if Error.IsError(lerr) then return lerr end
        local rhs_seq, rerr = _strtoseq_tolerant(rhs_expanded)
        if Error.IsError(rerr) then return rerr end

        local map_opts = _map_command_opts(parsed.opts)
        if spec.recursive then
            CommandMod.remap_keys(modes, lhs_seq, rhs_seq, map_opts)
        else
            CommandMod.noremap_keys(modes, lhs_seq, rhs_seq, map_opts)
        end
        return true
    end

    local function _menu_state()
        local menus = rt.state.menus
        if type(menus) ~= "table" then
            menus = {}
            rt.state.menus = menus
        end
        menus.items = menus.items or {}
        menus.tooltips = menus.tooltips or {}
        menus.translations = menus.translations or {}
        return menus
    end

    local function _menu_mode_bucket(modes)
        local menus = _menu_state()
        local key = tostring(modes or "")
        local bucket = menus.items[key]
        if type(bucket) ~= "table" then
            bucket = {}
            menus.items[key] = bucket
        end
        return bucket
    end

    local function _menu_path_matches(name, pat)
        if pat == "*" then
            return true
        end
        if pat:sub(-2) == ".*" then
            pat = pat:sub(1, -3)
            if pat == "" then
                return true
            end
        end
        if name == pat then
            return true
        end
        return name:sub(1, #pat + 1) == pat .. "."
    end

    local function _menu_translate_name(name)
        local menus = _menu_state()
        local translated = menus.translations[name]
        if translated then
            return translated
        end
        local out = {}
        local changed = false
        for part in tostring(name or ""):gmatch("([^.]+)") do
            local p = menus.translations[part]
            if p then
                out[#out + 1] = p
                changed = true
            else
                out[#out + 1] = part
            end
        end
        if changed then
            return table.concat(out, ".")
        end
        return name
    end

    local function _split_menu_path(name)
        local out = {}
        for part in tostring(name or ""):gmatch("([^.]+)") do
            out[#out + 1] = part
        end
        return out
    end

    local function _menu_validate_path(name)
        name = tostring(name or "")
        if name == "" or name:sub(1, 1) == "." or name:sub(-1) == "." or name:find("%.%.", 1, true) then
            return nil, Error(475, name)
        end
        return _split_menu_path(name), nil
    end

    local function _menu_has_prefix(modes, prefix)
        local bucket = _menu_mode_bucket(modes)
        for _, item in pairs(bucket) do
            local raw = item.name
            local translated = item.translated
            if raw == prefix or raw:sub(1, #prefix + 1) == prefix .. "." then
                return true
            end
            if translated and (translated == prefix or translated:sub(1, #prefix + 1) == prefix .. ".") then
                return true
            end
        end
        return false
    end

    local function _menu_missing_segment(modes, name)
        local parts, perr = _menu_validate_path(name)
        if Error.IsError(perr) then
            return nil, perr
        end
        if #parts == 1 and parts[1] == "*" then
            return nil, nil
        end

        local prefix = ""
        for i = 1, #parts do
            local seg = parts[i]
            if seg == "*" then
                return nil, nil
            end
            local next_prefix = (prefix == "") and seg or (prefix .. "." .. seg)
            if not _menu_has_prefix(modes, next_prefix) then
                return seg, nil
            end
            prefix = next_prefix
        end
        return nil, nil
    end

    local function _menu_tooltip_has_prefix(prefix)
        local menus = _menu_state()
        for key in pairs(menus.tooltips) do
            if key == prefix or key:sub(1, #prefix + 1) == prefix .. "." then
                return true
            end
        end
        return false
    end

    local function _menu_tooltip_missing_segment(name)
        local parts, perr = _menu_validate_path(name)
        if Error.IsError(perr) then
            return nil, perr
        end
        if #parts == 1 and parts[1] == "*" then
            return nil, nil
        end

        local prefix = ""
        for i = 1, #parts do
            local seg = parts[i]
            if seg == "*" then
                return "*", nil
            end
            local next_prefix = (prefix == "") and seg or (prefix .. "." .. seg)
            if not _menu_tooltip_has_prefix(next_prefix) then
                return seg, nil
            end
            prefix = next_prefix
        end
        return nil, nil
    end

    local function _menu_item_matches(name, item, pat)
        if _menu_path_matches(name, pat) then
            return true
        end
        local translated = item and item.translated
        if translated and _menu_path_matches(translated, pat) then
            return true
        end
        return false
    end

    local function _consume_menu_options(args, idx)
        local out = {}
        while idx <= #args do
            local tok = args[idx]
            local bracket = tok:match("^<([^>]+)>$")
            if bracket then
                out[bracket:lower()] = true
                idx = idx + 1
            else
                local k, v = tok:match("^([%a_][%w_]*)=(.*)$")
                if not k then
                    break
                end
                out[k:lower()] = v
                idx = idx + 1
            end
        end
        return idx, out
    end

    local function _is_menu_priority(tok)
        return type(tok) == "string" and tok:match("^%d+([.]%d+)*$") ~= nil
    end

    local function _menu_set_enabled(modes, pat, enabled)
        local bucket = _menu_mode_bucket(modes)
        local changed = 0
        for name, item in pairs(bucket) do
            if _menu_item_matches(name, item, pat) then
                item.enabled = enabled and true or false
                changed = changed + 1
            end
        end
        return changed
    end

    local function _menu_remove(modes, pat)
        local bucket = _menu_mode_bucket(modes)
        local changed = 0
        for name, item in pairs(bucket) do
            if _menu_item_matches(name, item, pat) then
                bucket[name] = nil
                changed = changed + 1
            end
        end
        return changed
    end

    local function _menu_find_item(name)
        local menus = _menu_state()
        local lookup_order = { "a", "nvo", "n", "vs", "x", "s", "o", "i", "c", "tl" }
        for i = 1, #lookup_order do
            local bucket = menus.items[lookup_order[i]]
            local item = bucket and bucket[name]
            if item then
                return item
            end
            if bucket then
                for _, v in pairs(bucket) do
                    if v.translated == name then
                        return v
                    end
                end
            end
        end
        for _, bucket in pairs(menus.items) do
            local item = bucket and bucket[name]
            if item then
                return item
            end
        end
        return nil
    end

    local function _run_menu_ex_command(cmd_name, argstr, bang)
        local spec = MENU_COMMAND_SPECS[cmd_name]
        if not spec then
            return Error(492, cmd_name)
        end
        if bang then
            return Error(474, "No ! allowed")
        end

        local raw = strip(argstr)
        local args = split_ws(raw)
        local idx = 1
        local menu_opts
        idx, menu_opts = _consume_menu_options(args, idx)

        if spec.action == "translate" then
            local menus = _menu_state()
            local from = args[idx]
            if not from then
                return true
            end
            if from:lower() == "clear" and idx == #args then
                menus.translations = {}
                return true
            end
            local to = table.concat(args, " ", idx + 1)
            if to == "" then
                return true
            end
            menus.translations[from] = to
            return true
        end

        if spec.action == "tooltip" then
            local priority
            if _is_menu_priority(args[idx]) then
                priority = args[idx]
                idx = idx + 1
            end
            local name = args[idx]
            if not name then
                return true
            end
            idx = idx + 1
            local text = table.concat(args, " ", idx)
            local menus = _menu_state()
            menus.tooltips[name] = {
                name = name,
                text = text,
                priority = priority,
            }
            return true
        end

        if spec.action == "tooltip_remove" then
            local name = args[idx]
            if not name then
                return true
            end
            local menus = _menu_state()
            local missing, merr = _menu_tooltip_missing_segment(name)
            if Error.IsError(merr) then
                return merr
            end
            if missing then
                return Error(329, missing)
            end
            if name == "*" then
                menus.tooltips = {}
                return true
            end

            for key in pairs(menus.tooltips) do
                if key == name or key:sub(1, #name + 1) == name .. "." then
                    menus.tooltips[key] = nil
                end
            end
            return true
        end

        if spec.action == "remove" then
            local name = args[idx]
            if not name then
                return true
            end
            local missing, merr = _menu_missing_segment(spec.modes, name)
            if Error.IsError(merr) then
                return merr
            end
            if missing then
                return Error(329, missing)
            end
            local changed = _menu_remove(spec.modes, name)
            if changed == 0 and name ~= "*" then
                local root = name:match("^[^.]+") or name
                return Error(329, root)
            end
            return true
        end

        if spec.action == "execute" then
            local name = args[idx]
            if not name then
                return true
            end
            local item = _menu_find_item(name)
            if not item then
                return Error(334, name)
            end
            local rhs = tostring(item.rhs or "")
            if rhs == "" then
                return true
            end

            local run
            local low = rhs:lower()
            if low:sub(1, 5) == "<cmd>" then
                run = rhs:sub(6)
                run = run:gsub("<[cC][rR]>%s*$", "")
                run = strip(run)
                if run == "" then
                    return true
                end
                return rt:exec_script(run)
            end
            if rhs:sub(1, 1) == ":" then
                run = rhs:sub(2)
                run = run:gsub("<[cC][rR]>%s*$", "")
                run = strip(run)
                if run == "" then
                    return true
                end
                return rt:exec_script(run)
            end
            return rt:exec_script(rhs)
        end

        if spec.action == "define" then
            local operation
            local token = args[idx] and args[idx]:lower()
            if token == "enable" or token == "disable" then
                operation = token
                idx = idx + 1
            end

            local priority
            if not operation and _is_menu_priority(args[idx]) then
                priority = args[idx]
                idx = idx + 1
            end

            if not operation then
                token = args[idx] and args[idx]:lower()
                if token == "enable" or token == "disable" then
                    operation = token
                    idx = idx + 1
                end
            end

            local name = args[idx]
            if not name then
                if operation then
                    return Error(329, operation)
                end
                return true
            end
            idx = idx + 1

            if operation then
                local missing, merr = _menu_missing_segment(spec.modes, name)
                if Error.IsError(merr) then
                    return merr
                end
                if missing then
                    return Error(329, missing)
                end
                local changed = _menu_set_enabled(spec.modes, name, operation == "enable")
                if changed == 0 and name ~= "*" then
                    local root = name:match("^[^.]+") or name
                    return Error(329, root)
                end
                return true
            end

            local rhs = table.concat(args, " ", idx)
            local rhs_expanded, serr = _expand_map_sid(rhs)
            if Error.IsError(serr) then
                return serr
            end

            local bucket = _menu_mode_bucket(spec.modes)
            if bucket[name] and menu_opts.unique then
                return Error(474, "Menu exists: " .. name)
            end

            bucket[name] = {
                name = name,
                translated = _menu_translate_name(name),
                rhs = rhs_expanded or "",
                priority = priority,
                enabled = true,
                recursive = spec.recursive and true or false,
                modes = spec.modes,
                opts = menu_opts,
            }
            return true
        end

        return Error(474, "Unsupported menu action: " .. tostring(spec.action))
    end

    local function _split_csv(s)
        local t = {}
        for part in tostring(s or ""):gmatch("([^,]+)") do
            t[#t + 1] = strip(part)
        end
        return t
    end

    local function _is_event_spec(s)
        if not s or s == "" then return false end
        if s == "*" then return true end
        for part in tostring(s):gmatch("([^,]+)") do
            local p = strip(part)
            if p ~= "*" and not Autocmd.IsValidEvent(p) then
                return false
            end
        end
        return true
    end

    local function _consume_autocmd_header(args)
        local i, n = 1, #args
        local group_name, group_id
        local group_specified = false

        local function _looks_like_group(tok, nexttok)
            if not tok then return false end
            if _is_event_spec(tok) then return false end
            if Autocmd.GetAugroupId(tok) then return true end
            if nexttok and _is_event_spec(nexttok) then return true end
            return false
        end

        if _looks_like_group(args[i], args[i + 1]) then
            group_name = args[i]
            group_id = Autocmd.GetAugroupId(group_name)
            group_specified = true
            i = i + 1
        else
            group_id = Autocmd.GetCurrentGroup() or 1
        end

        local events_raw = args[i]
        if not events_raw then
            return {
                group_name = group_name,
                group_id = group_id,
                group_specified = group_specified,
                events_raw = nil,
                events = nil,
                patterns = nil,
                once = false,
                nested = false,
                desc = nil,
                payload = "",
            }
        end
        i = i + 1
        local events = (events_raw == "*") and { "*" } or _split_csv(events_raw)

        local patterns
        if i <= n and not args[i]:match("^%+%+") then
            patterns = _split_csv(args[i])
            i = i + 1
        end

        local once, nested, desc = false, false, nil
        while i <= n and args[i]:sub(1, 2) == "++" do
            local k, v = args[i]:match("^%+%+([^=]+)=(.*)$")
            k = (k or args[i]:sub(3)):lower()
            if k == "once" then
                once = true
            elseif k == "nested" then
                nested = true
            elseif k == "desc" then
                desc = v or ""
            else
                return nil, Error(475, args[i])
            end
            i = i + 1
        end

        local payload = table.concat(args, " ", i)

        return {
            group_name = group_name,
            group_id = group_id,
            group_specified = group_specified,
            events_raw = events_raw,
            events = events,
            patterns = patterns,
            once = once,
            nested = nested,
            desc = desc,
            payload = payload,
        }
    end

    function rt:define_autocmd(rest, bang)
        local args = split_ws(rest)
        local H, err = _consume_autocmd_header(args)
        if Error.IsError(err) then
            error(err)
        end

        local gid = H.group_id
        local function ensure_group()
            if gid then return gid end
            if H.group_specified and H.group_name then
                gid = Autocmd.CreateAugroup(H.group_name, false)
                return gid
            end
            gid = Autocmd.GetCurrentGroup() or 1
            return gid
        end

        if bang then
            if H.payload ~= "" then
                if (not H.patterns or #H.patterns == 0) or (H.events_raw == "*") then
                    error(Error(471))
                end
                gid = ensure_group()
                Autocmd.RemoveAutocommands(gid, (H.events_raw == "*" and nil or H.events), H.patterns)
                return Autocmd.CreateAutocommand(H.events, H.patterns, H.payload, nil, gid, H.once, H.nested, H.desc,
                    self.state.script_ctx)
            end

            if H.events_raw == nil then
                if H.group_specified and not gid then return true end
                Autocmd.RemoveAutocommands(gid, nil, nil)
                return true
            end
            if H.events_raw == "*" then
                if H.group_specified and not gid then return true end
                Autocmd.RemoveAutocommands(gid, nil, H.patterns)
                return true
            end
            if not H.patterns then
                if H.group_specified and not gid then return true end
                Autocmd.RemoveAutocommands(gid, H.events, nil)
                return true
            end
            if H.group_specified and not gid then return true end
            Autocmd.RemoveAutocommands(gid, H.events, H.patterns)
            return true
        end

        if H.payload == "" then
            Autocmd.List({
                group = H.group_name,
                events = (H.events_raw == "*" and nil or H.events),
                pattern = H.patterns,
            })
            return true
        end
        if (H.events_raw == "*") or (not H.patterns or #H.patterns == 0) then
            error(Error(471))
        end
        gid = ensure_group()
        return Autocmd.CreateAutocommand(H.events, H.patterns, H.payload, nil, gid, H.once, H.nested, H.desc,
            self.state.script_ctx)
    end

    function rt:doautoall(rest)
        local event = tostring(rest or ""):match("^(%S+)")
        if not event then error(Error(474, "Argument required")) end
        local win = windows[curwin]
        local curbuf = win.buffer
        local bufs = {}
        for _, b in pairs(buffers) do
            if b and b.bufnr then bufs[#bufs + 1] = b end
        end
        table.sort(bufs, function(a, b) return (a.bufnr or 0) < (b.bufnr or 0) end)
        local ordered = {}
        for _, b in ipairs(bufs) do if b ~= curbuf then ordered[#ordered + 1] = b end end
        if curbuf then ordered[#ordered + 1] = curbuf end

        for _, b in ipairs(ordered) do
            local ctx = { bufnr = b.bufnr, bufname = b.name }
            local canon = Autocmd.NormalizeEvent(event)
            if canon == "FileType" then
                local ft = Options.get("filetype", nil, b, true)
                if ft == "" then
                    goto continue
                end
                ctx.pattern = ft
            else
                ctx.pattern = b.name
            end
            Autocmd.Run(event, ctx)
            ::continue::
        end
        return true
    end

    function rt:doautocmd(rest)
        local raw = strip(rest)
        if raw == "" then
            error(Error(474, "Argument required"))
        end
        local args = split_ws(raw)
        local group
        local event_spec = args[1]
        local file_arg = args[2]
        if Autocmd.GetAugroupId(event_spec) and args[2] then
            group = event_spec
            event_spec = args[2]
            file_arg = args[3]
        end
        if not event_spec or event_spec == "" then
            error(Error(474, "Event required"))
        end
        local ctx = {}
        if group then ctx.group = group end
        if file_arg and file_arg ~= "" then
            ctx.bufname = file_arg
            ctx.pattern = file_arg
        end
        for ev in tostring(event_spec):gmatch("([^,]+)") do
            Autocmd.Run(ev, ctx)
        end
        return true
    end

    function rt:augroup(raw, bang)
        local arg = strip(raw)
        if arg == "" then
            return true
        end
        if arg:lower() == "end" then
            if bang then
                error(Error(367, arg))
            end
            Autocmd.SetCurrentGroup(1)
            return true
        end
        if bang then
            local ok, err = Autocmd.DeleteAugroup(arg)
            if not ok then error(err) end
            Autocmd.SetCurrentGroup(1)
            return true
        end
        Autocmd.SetCurrentGroup(Autocmd.CreateAugroup(arg, false))
        return true
    end

    function rt:delcommand(raw)
        local args = split_ws(raw)
        if #args == 0 then error(Error(474, "Argument required")) end
        local name = args[1]
        if name == "-buffer" and args[2] then
            name = args[2]
        end
        Runtime._USER_COMMANDS[tostring(name):lower()] = nil
        self.state.commands[tostring(name):lower()] = nil
        return true
    end

    function rt:comclear()
        Runtime._USER_COMMANDS = {}
        self.state.commands = {}
        return true
    end

    local function _filetype_detection_on()
        local gid = Autocmd.GetAugroupId("filetypedetect")
        if not gid then
            return false
        end
        return Autocmd.GroupHasAutocommands(gid)
    end

    local function _filetype_enable_detection()
        if _filetype_detection_on() then
            return true
        end
        local ss = _scriptsource()
        local had = scopes.g.did_load_filetypes ~= nil
        if had then
            scopes.g.did_load_filetypes = nil
        end
        local ok, err = ss.source_runtime("filetype.lua")
        if not ok then
            return err
        end
        ok, err = ss.source_runtime("filetype.vim")
        if not ok then
            return err
        end
        return true
    end

    local function _filetype_disable_detection()
        local gid = Autocmd.GetAugroupId("filetypedetect")
        if gid then
            Autocmd.RemoveAutocommands(gid, nil, nil)
        end
        return true
    end

    local function _filetype_enable_plugin()
        local ok, err = _scriptsource().source_runtime("ftplugin.vim")
        if not ok then
            return err
        end
        return true
    end

    local function _filetype_disable_plugin()
        local ok, err = _scriptsource().source_runtime("ftplugof.vim")
        if not ok then
            return err
        end
        return true
    end

    local function _filetype_enable_indent()
        local ok, err = _scriptsource().source_runtime("indent.vim")
        if not ok then
            return err
        end
        return true
    end

    local function _filetype_disable_indent()
        local ok, err = _scriptsource().source_runtime("indoff.vim")
        if not ok then
            return err
        end
        return true
    end

    function rt:filetype(argstr)
        local args = split_ws(argstr)
        if #args == 0 then
            local detect = _filetype_detection_on() and "ON" or "OFF"
            local plugin = (scopes.g.did_load_ftplugin ~= nil) and "ON" or "OFF"
            local indent = (scopes.g.did_indent_on ~= nil) and "ON" or "OFF"
            _exmsg().echo("filetype detection:" .. detect .. "  plugin:" .. plugin .. "  indent:" .. indent)
            return true
        end

        if #args == 1 and args[1]:lower() == "detect" then
            local ok = _filetype_enable_detection()
            if Error.IsError(ok) then return ok end
            local buf = windows[curwin].buffer
            local ctx = _buf_ctx_from(buf)
            Autocmd.Run("BufRead", ctx)
            Autocmd.Run("BufNewFile", ctx)
            if buf.name == "" then
                Autocmd.Run("StdinReadPost", ctx)
            end
            return true
        end

        local want_plugin = false
        local want_indent = false
        local mode = nil

        for _, raw in ipairs(args) do
            local tok = raw:lower()
            if tok == "plugin" then
                want_plugin = true
            elseif tok == "indent" then
                want_indent = true
            elseif tok == "on" or tok == "off" then
                if mode then
                    return Error(474, raw)
                end
                mode = tok
            elseif tok == "detect" then
                return Error(474, raw)
            else
                return Error(474, raw)
            end
        end

        if not mode then
            return Error(471)
        end

        if mode == "on" then
            if want_plugin or want_indent then
                local ok = _filetype_enable_detection()
                if Error.IsError(ok) then return ok end
            end
            if want_plugin then
                local ok = _filetype_enable_plugin()
                if Error.IsError(ok) then return ok end
            end
            if want_indent then
                local ok = _filetype_enable_indent()
                if Error.IsError(ok) then return ok end
            end
            if not want_plugin and not want_indent then
                local ok = _filetype_enable_detection()
                if Error.IsError(ok) then return ok end
            end
        else
            if want_plugin then
                local ok = _filetype_disable_plugin()
                if Error.IsError(ok) then return ok end
            end
            if want_indent then
                local ok = _filetype_disable_indent()
                if Error.IsError(ok) then return ok end
            end
            if not want_plugin and not want_indent then
                local ok = _filetype_disable_detection()
                if Error.IsError(ok) then return ok end
            end
        end

        return true
    end

    function rt:define_command(rest, bang)
        local nargs = 0
        local name
        local body
        local parts = {}
        for tok in tostring(rest or ""):gmatch("%S+") do parts[#parts + 1] = tok end
        local idx = 1
        while idx <= #parts do
            local tok = parts[idx]
            if tok:match("^%-nargs=") then
                local v = tok:sub(8)
                nargs = (v == "*" or v == "?" or v == "+") and v or tonumber(v) or 0
                idx = idx + 1
            elseif tok:match("^%-") then
                idx = idx + 1
            else
                name = tok
                idx = idx + 1
                break
            end
        end
        if not name then error(Error(474, "Missing command name")) end
        local key = name:lower()
        body = table.concat(parts, " ", idx)
        if (not bang) and (self.state.commands[key] or Runtime._USER_COMMANDS[key]) then
            error(Error(474, "Command exists"))
        end
        local def = { body = body, nargs = nargs }
        self.state.commands[key] = def
        Runtime._USER_COMMANDS[key] = def
        return true
    end

    function rt:_invoke_builtin(cmd, argstr, bang, cmdctx)
        if MAP_COMMAND_SPECS[cmd] then
            local rv = _run_map_ex_command(cmd, argstr, bang)
            if Error.IsError(rv) then error(rv) end
            return rv
        end
        if MENU_COMMAND_SPECS[cmd] then
            local rv = _run_menu_ex_command(cmd, argstr, bang)
            if Error.IsError(rv) then error(rv) end
            return rv
        end

        if cmd == "write" then
            local status = windows[curwin].buffer:write(bang, argstr)
            if status ~= true then error(status) end
            return true
        elseif cmd == "silent" then
            return self:exec_silent(argstr, false, bang)
        elseif cmd == "unsilent" then
            return self:exec_silent(argstr, true, false)
        elseif cmd == "keepjumps" or cmd == "keeppatterns" then
            if argstr == "" then error(Error(474, "Argument required")) end
            return self:exec_script(argstr)
        elseif cmd == "keepalt" then
            if argstr == "" then error(Error(474, "Argument required")) end
            local win = windows[curwin]
            local saved_alt = win.altbuf
            local ok, rv = pcall(function()
                return self:exec_script(argstr)
            end)
            win.altbuf = saved_alt
            if not ok then error(rv) end
            return rv
        elseif cmd == "wq" then
            local status = windows[curwin].buffer:write(bang, argstr)
            if status ~= true then error(status) end
            local q = tabpages[curtp]:close(windows[curwin], bang)
            if q ~= true then error(q) end
            return true
        elseif cmd == "finish" then
            error(self:return_exc(nil))
        elseif cmd == "quit" then
            Autocmd.Run("QuitPre", _buf_ctx_from(windows[curwin].buffer))
            local q = tabpages[curtp]:close(windows[curwin], bang, nil, "autowriteall")
            if q ~= true then error(q) end
            return true
        elseif cmd == "close" then
            local target = windows[curwin]
            if cmdctx.count ~= nil then
                local count = tonumber(cmdctx.count)
                if count < 1 then
                    error(Error(16))
                end
                local target_win = tabpages[curtp].windows[count]
                if not target_win then
                    error(Error(16))
                end
                target = target_win
            end

            if #tabpages[curtp].windows == 1 then
                error(Error(444))
            end

            local q = tabpages[curtp]:close(target, bang, nil, "autowriteall")
            if q ~= true then error(q) end
            return true
        elseif cmd == "source" then
            local ok, err = _scriptsource().source(strip_trailing_comment(argstr))
            if not ok then error(err) end
            return true
        elseif cmd == "setglobal" then
            return self:set_options(argstr, "global")
        elseif cmd == "setlocal" then
            return self:set_options(argstr, "local")
        elseif cmd == "sign" then
            local tokens = split_ws(argstr)
            if #tokens == 0 then
                error(Error(471))
            end

            local function parse_kv(start_idx)
                local kv = {}
                local plain = {}
                for i = start_idx, #tokens do
                    local k, v = tokens[i]:match("^([^=]+)=(.*)$")
                    if k then
                        kv[k:lower()] = v
                    else
                        plain[#plain + 1] = tokens[i]
                    end
                end
                return kv, plain
            end

            local function resolve_buf_arg(kv)
                if kv.buffer ~= nil then
                    return tonumber(kv.buffer) or kv.buffer
                end
                if kv.file ~= nil then
                    return kv.file
                end
                return 0
            end

            local function resolve_sign_sub(prefix)
                local defs = {
                    { name = "define", min = 2 },
                    { name = "undefine", min = 2 },
                    { name = "list", min = 2 },
                    { name = "place", min = 2 },
                    { name = "unplace", min = 3 },
                    { name = "jump", min = 2 },
                }
                prefix = tostring(prefix or ""):lower()
                local match = nil
                for i = 1, #defs do
                    local d = defs[i]
                    if #prefix >= d.min and d.name:sub(1, #prefix) == prefix then
                        if match then
                            return nil
                        end
                        match = d.name
                    end
                end
                return match
            end

            local function echo_defs(defs)
                local msg = _exmsg()
                for i = 1, #defs do
                    local d = defs[i]
                    local parts = {
                        "sign " .. tostring(d.name),
                    }
                    if d.text ~= nil then parts[#parts + 1] = "text=" .. tostring(d.text) end
                    if d.linehl ~= nil then parts[#parts + 1] = "linehl=" .. tostring(d.linehl) end
                    if d.numhl ~= nil then parts[#parts + 1] = "numhl=" .. tostring(d.numhl) end
                    if d.texthl ~= nil then parts[#parts + 1] = "texthl=" .. tostring(d.texthl) end
                    if d.culhl ~= nil then parts[#parts + 1] = "culhl=" .. tostring(d.culhl) end
                    if d.priority ~= nil then parts[#parts + 1] = "priority=" .. tostring(d.priority) end
                    msg.echo(table.concat(parts, " "))
                end
            end

            local function echo_placed(placed)
                local msg = _exmsg()
                for i = 1, #placed do
                    local item = placed[i]
                    msg.echo(("--- Signs for buffer=%s ---"):format(tostring(item.bufnr)))
                    local signs = item.signs or {}
                    for j = 1, #signs do
                        local s = signs[j]
                        msg.echo((
                            "id=%s group=%s line=%s name=%s priority=%s"
                        ):format(
                            tostring(s.id),
                            tostring(s.group),
                            tostring(s.lnum),
                            tostring(s.name),
                            tostring(s.priority)
                        ))
                    end
                end
            end

            local sub = resolve_sign_sub(tokens[1])
            if not sub then
                error(Error(474, argstr))
            end

            if sub == "define" then
                local name = tokens[2]
                if not name then
                    error(Error(471))
                end
                local kv = parse_kv(3)
                local dict = {}
                if kv.icon ~= nil then dict.icon = kv.icon end
                if kv.linehl ~= nil then dict.linehl = kv.linehl end
                if kv.numhl ~= nil then dict.numhl = kv.numhl end
                if kv.text ~= nil then dict.text = kv.text end
                if kv.texthl ~= nil then dict.texthl = kv.texthl end
                if kv.culhl ~= nil then dict.culhl = kv.culhl end
                if kv.priority ~= nil then dict.priority = tonumber(kv.priority) end
                local rv = _vimfn().fn.sign_define(name, dict)
                if rv ~= 0 then
                    error(Error(474, argstr))
                end
                return true
            elseif sub == "undefine" then
                local rv = _vimfn().fn.sign_undefine(tokens[2])
                if rv ~= 0 and rv ~= nil then
                    error(Error(474, argstr))
                end
                return true
            elseif sub == "list" then
                local defs = _vimfn().fn.sign_getdefined(tokens[2])
                echo_defs(defs)
                return true
            elseif sub == "place" then
                local first = tokens[2]
                local first_num = tonumber(first)
                local first_is_kv = first and first:find("=", 1, true) ~= nil

                if first_num and not first_is_kv then
                    local kv = parse_kv(3)
                    if kv.name then
                        local opts = {}
                        if kv.line ~= nil then opts.lnum = tonumber(kv.line) end
                        if kv.lnum ~= nil then opts.lnum = tonumber(kv.lnum) end
                        if kv.priority ~= nil then opts.priority = tonumber(kv.priority) end
                        if next(opts) == nil then opts = nil end
                        local rv = _vimfn().fn.sign_place(
                            first_num,
                            kv.group or "",
                            kv.name,
                            resolve_buf_arg(kv),
                            opts
                        )
                        if rv == -1 then
                            error(Error(474, argstr))
                        end
                        return true
                    end
                end

                local start_idx = 2
                local dict = {}
                if first_num and not first_is_kv then
                    dict.id = first_num
                    start_idx = 3
                end
                local kv = parse_kv(start_idx)
                if kv.group ~= nil then dict.group = kv.group end
                if kv.id ~= nil then dict.id = tonumber(kv.id) end
                if kv.line ~= nil then dict.lnum = tonumber(kv.line) end
                if kv.lnum ~= nil then dict.lnum = tonumber(kv.lnum) end
                if next(dict) == nil then dict = nil end
                local placed = _vimfn().fn.sign_getplaced(resolve_buf_arg(kv), dict)
                echo_placed(placed)
                return true
            elseif sub == "unplace" then
                local first = tokens[2]
                local first_is_kv = first and first:find("=", 1, true) ~= nil
                local first_num = tonumber(first)

                if not first then
                    local win = windows[curwin]
                    local curbuf = win.buffer.bufnr
                    local curline = win.cursory
                    local placed = _vimfn().fn.sign_getplaced(curbuf, { group = "*", lnum = curline })
                    if #placed > 0 and #placed[1].signs > 0 then
                        local top = placed[1].signs[1]
                        _vimfn().fn.sign_unplace(top.group, { buffer = curbuf, id = top.id })
                    end
                    return true
                end

                local start_idx = 2
                local id = nil
                if (not first_is_kv) and first ~= "*" and first_num then
                    id = first_num
                    start_idx = 3
                elseif (not first_is_kv) and first == "*" then
                    start_idx = 3
                end

                local kv = parse_kv(start_idx)
                local group = kv.group
                if not group then
                    group = (first == "*") and "*" or ""
                end
                local opts = {}
                if kv.buffer ~= nil then opts.buffer = tonumber(kv.buffer) or kv.buffer end
                if kv.file ~= nil then opts.buffer = kv.file end
                if kv.id ~= nil then opts.id = tonumber(kv.id) end
                if id ~= nil then opts.id = id end
                if next(opts) == nil then opts = nil end
                local rv = _vimfn().fn.sign_unplace(group, opts)
                if rv == -1 then
                    error(Error(474, argstr))
                end
                return true
            elseif sub == "jump" then
                local id = tonumber(tokens[2])
                if not id then
                    error(Error(474, argstr))
                end
                local kv = parse_kv(3)
                local lnum = _vimfn().fn.sign_jump(id, kv.group or "", resolve_buf_arg(kv))
                if lnum == -1 then
                    error(Error(474, argstr))
                end
                return true
            end
            error(Error(474, argstr))
        elseif cmd == "normal" then
            local keys_text = tostring(argstr or "")
            if keys_text == "" then
                error(Error(471))
            end

            local seq, kerr = _strtoseq_normal_literal(keys_text)
            if Error.IsError(kerr) then
                error(kerr)
            end

            local CommandMod = _command_mod()
            local win = windows[curwin]
            local l1 = cmdctx.line1
            local l2 = cmdctx.line2
            local function normal_is_undo_like(seq_keys)
                if not seq_keys or #seq_keys == 0 then
                    return false
                end
                local last = seq_keys[#seq_keys]
                local last_num = last and last.numeric
                local is_undo_key = (
                    last_num == keys.u or
                    last_num == bit32.bor(keys.u, 8192) or
                    last_num == bit32.bor(keys.r, 4096)
                )
                if not is_undo_key then
                    return false
                end
                for i = 1, #seq_keys - 1 do
                    if seq_keys[i]:ToDigit() == nil then
                        return false
                    end
                end
                return true
            end
            local normal_pause_batch = normal_is_undo_like(seq)

            local function run_normal_once()
                local prev_mode = vimmode
                vimmode = "normal"
                local ok, rv = pcall(CommandMod.execute_normal_keys, seq, { remap = not bang })
                vimmode = prev_mode
                if not ok then
                    error(rv)
                end
                return rv
            end

            if normal_pause_batch then
                runtime_undo_batch_pause()
            end
            if l1 ~= nil and l2 ~= nil then
                local line_count = win.buffer:line_count(true)
                if line_count < 1 then line_count = 1 end
                local first = tonumber(l1 or win.cursory or 1) or (win.cursory or 1)
                local last = tonumber(l2 or first) or first
                if first > last then
                    first, last = last, first
                end
                if first < 1 then first = 1 end
                if last > line_count then last = line_count end
                for line = first, last do
                    win:cursorSet(1, line)
                    run_normal_once()
                end
                if normal_pause_batch then
                    runtime_undo_batch_resume()
                end
                return true
            end

            run_normal_once()
            if normal_pause_batch then
                runtime_undo_batch_resume()
            end
            return true
        elseif cmd == "undo" then
            runtime_undo_batch_pause()
            local win = windows[curwin]
            local raw = strip(argstr)
            if raw == "" then
                win.buffer:undo(win, 1)
            else
                local parsed = tonumber(raw)
                if not parsed then
                    error(Error(474, argstr))
                end
                local ok = win.buffer:undo_change(win, math.floor(parsed))
                if not ok then
                    error(Error(474, argstr))
                end
            end
            win:mark_redraw()
            runtime_undo_batch_resume()
            return true
        elseif cmd == "redo" then
            runtime_undo_batch_pause()
            local win = windows[curwin]
            local raw = strip(argstr)
            local count = 1
            if raw ~= "" then
                local parsed = tonumber(raw)
                if not parsed then
                    error(Error(474, argstr))
                end
                count = math.max(0, math.floor(parsed))
            end
            if count > 0 then
                win.buffer:redo(win, count)
                win:mark_redraw()
            end
            runtime_undo_batch_resume()
            return true
        elseif cmd == "undojoin" then
            if not windows[curwin].buffer:undojoin() then
                error(Error(790))
            end
            return true
        elseif cmd == "put" then
            local rv = self:put(argstr, bang, cmdctx)
            if Error.IsError(rv) then error(rv) end
            return rv
        elseif cmd == "substitute" then
            local rv = self:substitute(argstr, bang, cmdctx)
            if Error.IsError(rv) then error(rv) end
            return rv
        elseif cmd == "global" then
            local rv = self:global(argstr, bang, cmdctx)
            if Error.IsError(rv) then error(rv) end
            return rv
        elseif cmd == "v" or cmd == "vglobal" then
            local rv = self:global(argstr, true, cmdctx)
            if Error.IsError(rv) then error(rv) end
            return rv
        elseif cmd == "sort" then
            local rv = self:sort(argstr, bang, cmdctx)
            if Error.IsError(rv) then error(rv) end
            return rv
        elseif cmd == "lcd" then
            windows[curwin].curdir = argstr
            return true
        elseif cmd == "tcd" then
            tabpages[curtp].curdir = argstr
            return true
        elseif cmd == "lua" then
            local ok, rv = _lualoader().Eval(argstr)
            if not ok then
                _exmsg().echoerr(rv:toString())
                return nil
            end
            return rv
        elseif cmd == "messages" then
            local msg = _exmsg()
            for i = 1, #msg.messages do
                msg._writeWithHL(msg.messages[i][2], msg.messages[i][1])
            end
            return true
        elseif cmd == "mode" or cmd == "redraw" then
            what_redraw["all"] = true
            need_redraw = true
            lazyredraw_force = true
            return true
        elseif cmd == "redrawstatus" then
            if bang then
                for _, win in pairs(windows) do
                    win.need_redraw = true
                end
                what_redraw["windows"] = true
            else
                local win = windows[curwin]
                if win then
                    win.need_redraw = true
                end
            end
            -- Also refresh commandline display (ruler/showcmd content).
            what_redraw["commandline"] = true
            need_redraw = true
            lazyredraw_force = true
            return true
        elseif cmd == "redrawtabline" then
            what_redraw["tabline"] = true
            need_redraw = true
            lazyredraw_force = true
            return true
        elseif cmd == "redir" then
            local spec, perr = _parse_redir_spec(argstr)
            if Error.IsError(perr) then error(perr) end

            local msg = _exmsg()
            local ok_end, end_err = msg.EndRedir()
            if not ok_end then
                if Error.IsError(end_err) then
                    error(end_err)
                end
                error(tostring(end_err))
            end

            if spec.kind == "end" then
                return true
            end

            local on_close
            if spec.kind == "file" then
                local path = spec.path
                local abspath = _vimfs().abspath(path)
                if (not spec.append) and (not bang) and fs.exists(abspath) then
                    error(Error(474, "File exists: " .. path))
                end
                local mode = spec.append and "a" or "w"
                on_close = function(text)
                    local h = fs.open(abspath, mode)
                    if not h then
                        return Error(212, path)
                    end
                    h.write(text)
                    h.close()
                    return true
                end
            elseif spec.kind == "register" then
                local key = _redir_register_key(spec.reg)
                on_close = function(text)
                    local base = spec.append and _redir_register_text(spec.reg) or ""
                    registers[key] = { "inline", _redir_text_to_lines(base .. text) }
                    return true
                end
            elseif spec.kind == "var" then
                local name = spec.name
                if spec.append then
                    local cur = self:get_var(name)
                    if type(cur) ~= "string" then
                        error(Error(474, "Only string variables can be used"))
                    end
                else
                    local set_ok = self:assign(name, "")
                    if Error.IsError(set_ok) then error(set_ok) end
                end

                on_close = function(text)
                    local cur = self:get_var(name)
                    if type(cur) ~= "string" then
                        return Error(474, "Only string variables can be used")
                    end
                    local base = spec.append and cur or ""
                    local set_ok = self:assign(name, base .. text)
                    if Error.IsError(set_ok) then
                        return set_ok
                    end
                    return true
                end
            else
                error(Error(474, argstr))
            end

            msg.StartRedir(on_close)
            return true
        elseif cmd == "runtime" then
            local args = split_ws(argstr)
            if #args == 0 then
                error(Error(471))
            end
            if args[1] == "START" or args[1] == "OPT" or args[1] == "PACK" or args[1] == "ALL" then
                error("UNHANDLED: runtime " .. args[1])
            end
            local fsmod = _filesystem()
            local rtp = _runtimepath().get_search_list()
            local ss = _scriptsource()
            for _, base in ipairs(rtp) do
                for i = 1, #args do
                    local matches = fsmod.ExpandWildcards(base .. "/" .. args[i])
                    if #matches ~= 0 then
                        for _, m in ipairs(matches) do
                            if fs.isDir(m) then
                                _exmsg().echo("Cannot source a directory: " .. m)
                            else
                                local ok, err = ss.source(m)
                                if not ok then
                                    _exmsg().echoerr((Error.IsError(err) and err:toString()) or tostring(err))
                                end
                            end
                        end
                    end
                end
            end
            return true
        elseif cmd == "packadd" then
            local name = strip(argstr)
            if name == "" then error(Error(471)) end
            local ok, err = _pack().add(name, { no_load = bang })
            if not ok then error(err) end
            return true
        elseif cmd == "buffer" then
            local args = split_ws(argstr)
            if #args ~= 1 then error(Error(474, "Argument required")) end
            local target = args[1]
            local win = windows[curwin]
            local curbuf = win.buffer
            local target_buf = nil
            if target:match("^%d+$") then
                target_buf = buffers[tonumber(target)]
            end
            if not target_buf then
                for _, b in pairs(buffers) do
                    if b.name == target then
                        target_buf = b
                        break
                    end
                end
            end
            if not target_buf then error(Error(86, target)) end
            if target_buf == curbuf then return true end
            local ok = curbuf:leave(bang, nil, "autowrite")
            if ok ~= true then error(ok) end
            if target_buf.loaded ~= true then
                target_buf:Load(true)
            end
            _switch_current_buffer(win, target_buf)
            target_buf.refcount = target_buf.refcount + 1
            win:cursorSet(1, 1)
            win:mark_redraw()
            return true
        elseif cmd == "edit" then
            local win = windows[curwin]
            local newname = (#split_ws(argstr) == 0) and "" or argstr
            local rv = _edit_buffer_name(win, newname, bang)
            if rv ~= true then error(rv) end
            return true
        elseif cmd == "file" then
            local target = strip(argstr)
            local win = windows[curwin]
            local remove_name = (cmdctx.line1 == 0 and cmdctx.line2 == 0) and target == ""
            if target == "" and not remove_name then
                _exmsg().echo(_file_status_message(win, bang))
                return true
            end
            local oldname = win.buffer.name
            if oldname ~= target then
                if oldname ~= "" then
                    local oldbuf = _buffer_mod()(false, false)
                    oldbuf.name = oldname
                    oldbuf.opts.buflisted = false
                    win.altbuf = oldbuf
                end
                win.buffer.name = target
            end
            _exmsg().echo(_file_status_message(win, bang))
            win:mark_redraw()
            return true
        elseif cmd == "delete" then
            local win = windows[curwin]
            local buf = win.buffer
            local reg, explicit_reg, count, perr = _parse_delete_args(argstr)
            if Error.IsError(perr) then error(perr) end
            local post_mode = _delete_suffix_mode(cmdctx.raw_cmd)
            local line1 = cmdctx.line1 or win.cursory
            local line2 = cmdctx.line2 or line1
            if count then
                line2 = line1 + count - 1
            end
            local line_count = buf:line_count(true)
            if line_count < 1 then
                line_count = 1
            end
            if line1 < 1 then line1 = 1 end
            if line2 > line_count then line2 = line_count end
            if line2 < line1 then line2 = line1 end

            local removed = {}
            for i = line1, line2 do
                removed[#removed + 1] = buf:get_line(i, true) or ""
            end
            buf:set_lines(line1 - 1, line2, false, {})
            _store_deleted_lines(reg, explicit_reg, removed)

            local target_line = line1
            if target_line > buf:line_count(true) then
                target_line = buf:line_count(true)
            end
            if target_line < 1 then
                target_line = 1
            end
            win:cursorSet(win.cursorx, target_line)
            if post_mode == "print" then
                _exmsg().echo("\n" .. _delete_print_text(buf:get_line(target_line, true) or ""))
            elseif post_mode == "list" then
                _exmsg().echo("\n" .. _delete_list_text(buf:get_line(target_line, true) or ""))
            end
            win:mark_redraw()
            return true
        elseif cmd == "mark" then
            local char = strip(argstr)
            if char == "" then
                error(Error(471))
            end
            if not char:match("^[a-zA-Z'\".]$") then
                error(Error(191))
            end
            local win = windows[curwin]
            local buf = win.buffer
            local lnum = cmdctx.line2 or win.cursory
            local col = win.cursorx
            if char:match("^[A-Z]$") then
                global_marks[char] = { bufnr = buf.bufnr, lnum = lnum, col = col }
            else
                buf.marks[char] = { lnum = lnum, col = col }
            end
            return true
        elseif cmd == "copy" or cmd == "t" then
            local win = windows[curwin]
            local buf = win.buffer
            local target, terr = _parse_copy_move_target(argstr, win)
            if Error.IsError(terr) then error(terr) end

            local line1 = cmdctx.line1 or win.cursory
            local line2 = cmdctx.line2 or line1
            local line_count = buf:line_count(true)
            if line_count < 1 then
                line_count = 1
            end
            if line1 < 1 then line1 = 1 end
            if line2 > line_count then line2 = line_count end
            if line2 < line1 then line2 = line1 end

            local lines = {}
            for i = line1, line2 do
                lines[#lines + 1] = buf:get_line(i, true) or ""
            end

            local insert_at = target + 1
            local start0 = insert_at - 1
            buf:set_lines(start0, start0, false, lines)
            local target_line = insert_at + #lines - 1
            win:cursorSet(1, target_line)
            win:mark_redraw()
            return true
        elseif cmd == "move" then
            local win = windows[curwin]
            local buf = win.buffer
            local target, terr = _parse_copy_move_target(argstr, win)
            if Error.IsError(terr) then error(terr) end

            local line1 = cmdctx.line1 or win.cursory
            local line2 = cmdctx.line2 or line1
            local line_count = buf:line_count(true)
            if line_count < 1 then
                line_count = 1
            end
            if line1 < 1 then line1 = 1 end
            if line2 > line_count then line2 = line_count end
            if line2 < line1 then line2 = line1 end

            if target >= line1 and target < line2 then
                error(Error(134))
            end

            local target_line = line2
            if target ~= (line1 - 1) and target ~= line2 then
                local lines = {}
                for i = line1, line2 do
                    lines[#lines + 1] = buf:get_line(i, true) or ""
                end
                local moved_count = #lines
                buf:set_lines(line1 - 1, line2, false, {})

                local insert_after = target
                if target > line2 then
                    insert_after = target - moved_count
                end
                local insert_at = insert_after + 1
                buf:set_lines(insert_at - 1, insert_at - 1, false, lines)
                target_line = insert_at + moved_count - 1
            end

            win:cursorSet(1, target_line)
            win:mark_redraw()
            return true
        elseif cmd == "enew" then
            if strip(argstr) ~= "" then
                error(Error(488, argstr))
            end

            local win = windows[curwin]
            local curbuf = win.buffer
            local leave = curbuf:leave(bang, nil, "autowriteall")
            if leave ~= true then
                error(leave)
            end

            local newbuf = _buffer_mod()(true, false)
            newbuf.name = ""
            _switch_current_buffer(win, newbuf, { skip_enter = true })

            local ff = Options.get("fileformat", win, curbuf)
            local ffs = _csv_first(Options.get("fileformats", win, curbuf))
            if ffs ~= "" then
                ff = ffs
            end
            newbuf.opts.fileformat = ff

            newbuf:Load(true)
            Autocmd.Run("BufEnter", _buf_ctx_from(newbuf))
            win:cursorSet(1, 1)
            win:mark_redraw()
            return true
        elseif cmd == "find" then
            local found, err = _resolve_find_name(argstr)
            if not found then error(err) end
            local rv = _edit_buffer_name(windows[curwin], found, bang)
            if rv ~= true then error(rv) end
            return true
        elseif cmd == "sfind" then
            local found, err = _resolve_find_name(argstr)
            if not found then error(err) end
            local refwin = windows[curwin]
            if not _split_preflight(0, refwin, false) then
                error(Error(36))
            end
            local targetbuf = _buffer_mod()(true, false)
            targetbuf.name = found
            targetbuf:Load(true)
            local newwin = _window_mod()(targetbuf, refwin)
            if not _split_real(0, newwin, false) then
                error(Error(36))
            end
            enterWindow(newwin.winnr)
            newwin:cursorSet(1, 1)
            return true
        elseif cmd == "tabfind" then
            local found, err = _resolve_find_name(argstr)
            if not found then error(err) end
            local rv = _edit_buffer_name(windows[curwin], found, bang)
            if rv ~= true then error(rv) end
            return true
        elseif cmd == "drop" then
            local args = split_ws(argstr)
            if #args == 0 then error(Error(471)) end
            local target_raw = args[1]
            local target_abs = _vimfs().abspath(target_raw)
            local win = _find_window_for_path(target_abs)
            if win then
                enterWindow(win.winnr)
                return true
            end
            local curwin_obj = windows[curwin]
            local ok = _edit_buffer_name(curwin_obj, target_raw, bang)
            if Error.IsError(ok) then
                if ok.code ~= 37 then error(ok) end
                if not _split_preflight(0, curwin_obj, false) then
                    error(Error(36))
                end
                local newbuf = _buffer_mod()(true, false)
                newbuf.name = target_raw
                newbuf:Load(true)
                local newwin = _window_mod()(newbuf, curwin_obj)
                if not _split_real(0, newwin, false) then
                    error(Error(36))
                end
                enterWindow(newwin.winnr)
                newwin:cursorSet(1, 1)
                return true
            end
            return true
        elseif cmd == "split" then
            local refwin = windows[curwin]
            if not _split_preflight(0, refwin, false) then
                error(Error(36))
            end

            local targetbuf = refwin.buffer
            if #split_ws(argstr) ~= 0 then
                targetbuf = _buffer_mod()(true, false)
                targetbuf.name = argstr
                targetbuf:Load(true)
            end
            local newwin = _window_mod()(targetbuf, refwin)
            if not _split_real(0, newwin, false) then
                error(Error(36))
            end
            enterWindow(newwin.winnr)
            return true
        elseif cmd == "vsplit" then
            local refwin = windows[curwin]
            if not _split_preflight(0, refwin, true) then
                error(Error(36))
            end

            local targetbuf = refwin.buffer
            if #split_ws(argstr) ~= 0 then
                targetbuf = _buffer_mod()(true, false)
                targetbuf.name = argstr
                targetbuf:Load(true)
            end
            local newwin = _window_mod()(targetbuf, refwin)
            if not _split_real(0, newwin, true) then
                error(Error(36))
            end
            enterWindow(newwin.winnr)
            return true
        elseif cmd == "wincmd" then
            local args = split_ws(argstr)
            local key = args[1]
            local count = cmdctx.count

            if key and key:match("^%d+$") then
                if count == nil then
                    count = tonumber(key)
                end
                key = args[2]
            elseif key then
                local inline_count, inline_key = key:match("^(%d+)(.+)$")
                if inline_count and inline_key ~= "" then
                    if count == nil then
                        count = tonumber(inline_count)
                    end
                    key = inline_key
                end
            end

            local rv = windows[curwin]:wincmd(key, count)
            if Error.IsError(rv) then
                error(rv)
            end
            return rv
        elseif cmd == "windo" then
            local cmdline = argstr
            if cmdline == "" then error(Error(474, "Argument required")) end
            local cur = curwin
            for _, win in ipairs(tabpages[curtp].windows) do
                enterWindow(win.winnr)
                self:exec_script(cmdline)
            end
            enterWindow(cur)
            return true
        elseif cmd == "augroup" then
            return self:augroup(argstr, bang)
        elseif cmd == "doautocmd" then
            return self:doautocmd(argstr)
        elseif cmd == "doautoall" then
            return self:doautoall(argstr)
        elseif cmd == "command" then
            return self:define_command(argstr, bang)
        elseif cmd == "delcommand" then
            return self:delcommand(argstr)
        elseif cmd == "comclear" then
            return self:comclear()
        elseif cmd == "echo" or cmd == "echoerr" or cmd == "echomsg" or cmd == "echon" then
            local results = {}
            local exprs = VimExpr.splitExpressions(argstr)
            for _, expr_str in ipairs(exprs) do
                local res = _eval_expr_for_cmd(expr_str)
                results[#results + 1] = _to_string_simple(res)
            end
            local line = table.concat(results, " ")
            local msg = _exmsg()
            if cmd == "echo" then msg.echo(line)
            elseif cmd == "echoerr" then msg.echoerr(line)
            elseif cmd == "echomsg" then msg.echomsg(line)
            else msg.echon(line) end
            return true
        elseif cmd == "echohl" then
            _exmsg().echohl(argstr)
            return true
        elseif cmd == "syntax" then
            local raw = strip(argstr)
            local head = raw:match("^(%S+)")
            local syn = _syntax()
            local win = windows[curwin]
            if not head or head == "" then
                return syn.ExecuteCommand(win, raw)
            end
            local h = head:lower()
            if h == "on" or h == "enable" then
                local ok, err = _scriptsource().source_runtime("syntax/syntax.vim")
                if not ok then error(err) end
                return true
            elseif h == "off" then
                local ok, err = _scriptsource().source_runtime("syntax/nosyntax.vim")
                if not ok then error(err) end
                return true
            elseif h == "manual" then
                local ok, err = _scriptsource().source_runtime("syntax/manual.vim")
                if not ok then error(err) end
                return true
            elseif h == "reset" then
                local ok, err = _scriptsource().source_runtime("syntax/syntax.vim")
                if not ok then error(err) end
                return true
            end
            return syn.ExecuteCommand(win, raw)
        elseif cmd == "syntime" then
            local head = (strip(argstr):match("^(%S+)") or ""):lower()
            local syn = _syntax()
            local win = windows[curwin]
            if head == "" or head == "report" then
                local lines = syn.SyntimeReport(win)
                for i = 1, #lines do _exmsg().echo(lines[i]) end
                return true
            elseif head == "on" then
                syn.SyntimeSet(win, true)
                return true
            elseif head == "off" then
                syn.SyntimeSet(win, false)
                return true
            elseif head == "clear" then
                syn.SyntimeClear(win)
                syn.SyntimeSet(win, true)
                return true
            end
            error(Error(474, argstr))
        elseif cmd == "ownsyntax" then
            local synname = strip(argstr):match("^(%S+)")
            if not synname or synname == "" then error(Error(471)) end
            local win = windows[curwin]
            _syntax().OwnSyntax(win, synname)
            scopes.w.current_syntax = synname
            what_redraw["windows"] = true
            need_redraw = true
            return true
        elseif cmd == "match" then
            local win = windows[curwin]
            local slot = 1
            local l1 = cmdctx.line1
            local l2 = cmdctx.line2
            if l1 ~= nil and l2 ~= nil and l1 == l2 and l1 >= 1 and l1 <= 3 then
                slot = l1
            end

            local raw = strip(argstr)
            if raw ~= "" and raw:lower() ~= "none" then
                local group = raw:match("^(%S+)")
                if not _highlight().HasGroup(group) then
                    error(Error(474, argstr))
                end
            end

            local ok, emsg = _syntax().MatchCommand(win, slot, argstr)
            if not ok then
                error(Error(474, emsg or argstr))
            end

            what_redraw["windows"] = true
            need_redraw = true
            return true
        elseif cmd == "setfiletype" then
            local args = split_ws(argstr)
            if #args == 0 then error(Error(471)) end
            local buf = windows[curwin].buffer
            local Scopes = loadModule("lib.luaapi.scopes")
            if args[1] == "FALLBACK" then
                local ft = args[2]
                if not ft or ft == "" then return true end
                local bnr = buf.bufnr
                local bt = Scopes._b_by_buf[bnr]
                local already = (bt and bt.did_filetype) or (Options.get("filetype", nil, buf) ~= "")
                if already then return true end
                Options.set("filetype", ft, nil, nil, buf)
                Scopes.b.did_filetype = 1
                return true
            end
            if #args > 1 then return true end
            Options.set("filetype", args[1], nil, nil, buf)
            Scopes.b.did_filetype = 1
            return true
        elseif cmd == "filetype" then
            local rv = self:filetype(argstr)
            if Error.IsError(rv) then error(rv) end
            return rv
        elseif cmd == "help" then
            local target = strip(argstr)
            if target == "" then target = "help.txt" end
            local match = _tags().SearchFile(ccvim_path .. "/runtime/doc/tags", target)
            if not match then error(Error(149, target)) end

            local function help_jump_pos(buf, tag, exaddr)
                local lines = buf:lines_ref(true)
                local line_count = #lines

                local function find_plain(needle)
                    if needle == "" then
                        return nil, nil
                    end
                    for ln = 1, line_count do
                        local text = lines[ln] or ""
                        local byte_idx = text:find(needle, 1, true)
                        if byte_idx then
                            local col = Utf8.col_from_byte(text, byte_idx) or 1
                            return ln, col
                        end
                    end
                    return nil, nil
                end

                local resolved_tag = tostring(tag or "")
                if resolved_tag ~= "" then
                    local ln, col = find_plain("*" .. resolved_tag .. "*")
                    if ln then
                        return ln, col
                    end
                end

                local addr = tostring(exaddr or "")
                local lnum = tonumber(addr)
                if lnum then
                    lnum = math.max(1, math.min(line_count, math.floor(lnum)))
                    return lnum, 1
                end

                if addr ~= "" then
                    local d = addr:sub(1, 1)
                    if d == "/" or d == "?" then
                        addr = addr:sub(2)
                    end
                    addr = addr:gsub("\\(.)", "%1")
                    local ln, col = find_plain(addr)
                    if ln then
                        return ln, col
                    end
                end

                return 1, 1
            end

            local target_win
            for _, tabwin in ipairs(tabpages[curtp].windows) do
                if tabwin.buffer.opts.buftype == "help" then
                    target_win = tabwin
                end
            end
            if not target_win and not _split_preflight(-1, nil, false) then
                error(Error(36))
            end
            local newbuf = _buffer_mod()(true, false)
            newbuf.opts.buftype = "help"
            newbuf.opts.readonly = true
            newbuf.opts.modifiable = false
            newbuf.name = ccvim_path .. "/runtime/doc/" .. match[2]
            newbuf:Load(true)
            Options.set("filetype", "help", true, nil, newbuf)
            local jumpline, jumpcol = help_jump_pos(newbuf, match[1], match[3])
            if target_win then
                target_win.buffer = newbuf
            else
                target_win = _window_mod()(newbuf)
                if not _split_real(-1, target_win, false) then
                    error(Error(36))
                end
            end
            enterWindow(target_win.winnr)
            target_win:cursorSet(jumpcol, jumpline)
            return true
        elseif cmd == "highlight" then
            local args = split_ws(argstr)
            local changed = false
            local hl = _highlight()
            if #args == 0 then return true end
            if args[1] == "clear" then
                hl.Clear(args[2])
                changed = true
            elseif args[2] == "NONE" then
                hl.Clear(args[1])
                changed = true
            else
                local is_default = false
                if args[1] == "default" or args[1] == "def" then
                    is_default = true
                    table.remove(args, 1)
                end
                if args[1] == "link" then
                    if #args ~= 3 then error(Error(471)) end
                    local from, to = args[2], args[3]
                    if is_default and hl.HasGroup(from) then return true end
                    local rv = hl.Link(from, to)
                    if Error.IsError(rv) then
                        if is_default and rv.code == 414 then return true end
                        error(rv)
                    end
                    changed = true
                else
                    local params = {}
                    for i = 2, #args do
                        local idx = args[i]:find("=")
                        if not idx then error(Error(416, args[i])) end
                        params[string.sub(args[i], 1, idx - 1)] = string.sub(args[i], idx + 1)
                    end
                    for k, v in pairs(params) do
                        if k == "guifg" and v:match("^#%x%x%x%x%x%x$") then
                            hl.SetGroupColor(args[1], "fg", tonumber("0x" .. v:sub(2)))
                            changed = true
                        elseif k == "guibg" and v:match("^#%x%x%x%x%x%x$") then
                            hl.SetGroupColor(args[1], "bg", tonumber("0x" .. v:sub(2)))
                            changed = true
                        end
                    end
                end
            end
            if changed then
                what_redraw["windows"] = true
                need_redraw = true
            end
            return true
        elseif cmd == "pwd" then
            local exmsg = _exmsg()

            local verb = Options.get("verbose")
            local msg = Builtins.fn.getcwd()

            if verb > 0 then
                if windows[curwin].curdir then
                    msg = "[window] " .. msg
                elseif tabpages[curtp].curdir then
                    msg = "[tabpage] " .. msg
                else
                    msg = "[global] " .. msg
                end
            end

            exmsg.echo(msg)
        end

        return nil
    end

    function rt:invoke_compiled_command(spec)
        spec = spec or {}
        local name = tostring(spec.name or "")
        local lname = tostring(spec.lname or "")
        if lname == "" then
            lname = name:lower()
        end
        local qargs = tostring(spec.qargs or "")
        local bang = not not spec.bang
        local win = windows[curwin]
        local cmdctx = _build_cmd_context(self:get_exec_cursor(), win, spec)

        if name == "" then
            if cmdctx.raw_cmd == nil and cmdctx.line2 ~= nil then
                local line_count = win.buffer:line_count(true)
                if line_count < 1 then
                    line_count = 1
                end
                local target = tonumber(cmdctx.line2 or cmdctx.line1 or win.cursory or 1) or (win.cursory or 1)
                if target < 1 then
                    target = 1
                elseif target > line_count then
                    target = line_count
                end
                win:cursorSet(1, target)
            end
            return true
        end

        local args = spec.ws_args
        local function ensure_args()
            if type(args) ~= "table" then
                args = split_ws(qargs)
            end
            return args
        end

        local line1 = cmdctx.line1 or win.cursory
        local line2 = cmdctx.line2 or line1
        local range = cmdctx.range or 0
        local count = cmdctx.count or cmdctx.line2 or 0

        local def = self.state.commands[lname]
        if def then
            local script = expand_user_command_template(
                def.body,
                qargs,
                ensure_args(),
                bang,
                count,
                line1,
                line2,
                range
            )
            return self:exec_script(script)
        end

        local dispatch_cmd = spec.dispatch
        if not dispatch_cmd then
            if DISPATCH_MIN_ABBREV[lname] or MAP_COMMAND_SPECS[lname] or MENU_COMMAND_SPECS[lname] then
                dispatch_cmd = lname
            else
                dispatch_cmd = resolve_dispatch_name(lname)
                if Error.IsError(dispatch_cmd) then
                    error(dispatch_cmd)
                end
            end
        end
        if dispatch_cmd then
            local rv = self:_invoke_builtin(dispatch_cmd, qargs, bang, cmdctx)
            if rv == nil then return true end
            return rv
        end

        local global = Runtime._USER_COMMANDS[lname]
        if not global then
            log_command_resolution_failure(self, name, lname, qargs, bang)
            error(Error(492, name))
        end
        if type(global.body) == "string" then
            local script = expand_user_command_template(
                global.body,
                qargs,
                ensure_args(),
                bang,
                count,
                line1,
                line2,
                range
            )
            return self:exec_script(script)
        end
        if type(global.handler) == "function" then
            return global.handler({
                cmd = name,
                args = qargs,
                fargs = ensure_args(),
                _ccvim = { raw_args = qargs },
                bang = bang,
                count = count,
                line1 = line1,
                line2 = line2,
                range = range,
            })
        end
        if type(global.command) == "string" then
            local script = expand_user_command_template(
                global.command,
                qargs,
                ensure_args(),
                bang,
                count,
                line1,
                line2,
                range
            )
            return self:exec_script(script)
        end
        return true
    end

    function rt:invoke_command(name, argstr, bang)
        return self:invoke_compiled_command({
            name = name,
            qargs = argstr,
            bang = bang,
        })
    end

    return setmetatable(rt, { __index = Runtime })
end

Runtime.create = Runtime.new

function Runtime.CanonicalFunctionName(name, opts)
    return canonical_function_name(name, opts)
end

function Runtime.CurrentScriptSid()
    return script_sid_for_state(Runtime._CURRENT_STATE)
end

function Runtime.ResolveFunctionDef(name, opts)
    return resolve_function_def(name, opts)
end

function Runtime.TryAutoloadFunction(name)
    return try_autoload_function(name)
end

function Runtime.RegisterUserCommand(name, def)
    Runtime._USER_COMMANDS[tostring(name):lower()] = def
end

function Runtime.DeleteUserCommand(name)
    Runtime._USER_COMMANDS[tostring(name):lower()] = nil
end

function Runtime.CaptureDurableScriptState(opts)
    opts = opts or {}
    local state = opts.state or Runtime._CURRENT_STATE
    local script_ctx = opts.script_ctx
    if type(script_ctx) ~= "string" or script_ctx == "" then
        script_ctx = nil
    end

    if type(state) ~= "table" then
        if not script_ctx then
            return nil
        end
        return {
            g = scopes._g or {},
            s = {},
            funcs = {},
            script_ctx = script_ctx,
            script_sid = script_sid_for_ctx(script_ctx),
        }
    end

    local durable = {
        g = state.g or scopes._g or {},
        s = state.s or {},
        funcs = state.funcs or {},
        menus = state.menus or {},
        script_ctx = state.script_ctx,
        script_sid = state.script_sid,
    }
    if script_ctx then
        durable.script_ctx = script_ctx
    end
    if not durable.script_sid then
        if durable.script_ctx then
            durable.script_sid = script_sid_for_ctx(durable.script_ctx)
        else
            durable.script_sid = script_sid_for_scope(durable.s)
        end
    end
    return durable
end

function Runtime.MakeRuntimeState(durable, extra_v)
    durable = durable or {}
    local state = {
        g = type(durable.g) == "table" and durable.g or scopes._g or {},
        s = type(durable.s) == "table" and durable.s or {},
        funcs = type(durable.funcs) == "table" and durable.funcs or {},
        menus = type(durable.menus) == "table" and durable.menus or {},
        v = fresh_v(extra_v),
        l = {},
        a = {},
        frames = {},
        commands = {},
    }
    if type(durable.script_ctx) == "string" and durable.script_ctx ~= "" then
        state.script_ctx = durable.script_ctx
    end
    if type(durable.script_sid) == "number" then
        state.script_sid = durable.script_sid
    end
    script_sid_for_state(state)
    return state
end

function Runtime.EvalExpression(expr, opts)
    opts = opts or {}
    local state = opts.state
    if type(state) ~= "table" then
        if type(opts.durable) == "table" then
            state = Runtime.MakeRuntimeState(opts.durable, opts.v)
        else
            state = ensure_state({ v = fresh_v(opts.v) })
        end
    end
    state = ensure_state(state)
    if type(opts.script_ctx) == "string" and opts.script_ctx ~= "" then
        state.script_ctx = opts.script_ctx
    end
    if opts.v and type(opts.v) == "table" then
        state.v = state.v or fresh_v()
        for k, val in pairs(opts.v) do
            state.v[k] = val
        end
    end
    local ctrl = opts.ctrl or {}

    local rt = Runtime.new(state)
    rt:_push_script_ctx()
    Runtime._CURRENT_STATE = state
    Runtime._CURRENT_CTRL = ctrl
    local ok, rv = pcall(function()
        return rt:eval_expr(tostring(expr or ""))
    end)
    Runtime._CURRENT_STATE = nil
    Runtime._CURRENT_CTRL = nil
    rt:_pop_script_ctx()

    if not ok then
        local err = enrich_runtime_error(rv, rt, opts, state, nil, "Runtime.EvalExpresion(...)")
        return false, err
    end
    if Error.IsError(rv) then
        return false, enrich_runtime_error(rv, rt, opts, state, nil, "Runtime.EvalExpresion(...)")
    end
    return true, rv
end

function Runtime.run(script, opts)
    opts = opts or {}
    local state = opts.state
    if type(state) ~= "table" then
        if type(opts.durable) == "table" then
            state = Runtime.MakeRuntimeState(opts.durable, opts.v)
        else
            state = ensure_state({ v = fresh_v(opts.v) })
        end
    end
    state = ensure_state(state)
    if type(opts.script_ctx) == "string" and opts.script_ctx ~= "" then
        state.script_ctx = opts.script_ctx
    end

    local prev_state = Runtime._CURRENT_STATE
    local prev_ctrl = Runtime._CURRENT_CTRL
    Runtime._CURRENT_STATE = state
    Runtime._CURRENT_CTRL = opts.ctrl or {}

    local rt = Runtime.new(state)
    runtime_undo_batch_depth = runtime_undo_batch_depth + 1
    if runtime_undo_batch_depth == 1 then
        runtime_undo_batch_begin()
    end
    local ok, rv = pcall(function()
        return rt:exec_script(tostring(script or ""))
    end)
    if runtime_undo_batch_depth == 1 then
        runtime_undo_batch_end()
    end
    runtime_undo_batch_depth = runtime_undo_batch_depth - 1

    Runtime._CURRENT_STATE = prev_state
    Runtime._CURRENT_CTRL = prev_ctrl

    if not ok then
        local err = enrich_runtime_error(rv, rt, opts, state, script, "Runtime.run(...) returned nil!")
        return false, err
    end
    return true, rv
end

return Runtime
