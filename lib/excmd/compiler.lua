-- vim.lib.excmd.compiler
local Compiler = {}

local Error = loadModule("lib.error")
local Commands = loadModule("lib.excmd.commands")
local VimExpr = loadModule("lib.excmd.vimxpr")

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function resolve_cmd_name(raw)
    return Commands.resolve_parse_name(raw)
end

local function _cmd_mode_and_bar(cmd_raw)
    return Commands.mode_and_bar(cmd_raw)
end

local DISPATCH_MIN_ABBREV = Commands.DISPATCH_MIN_ABBREV
local MAP_COMMAND_SPECS = Commands.MAP_COMMAND_SPECS
local resolve_dispatch_name = Commands.resolve_dispatch_name
local parse_cmd_head

local COMMAND_WRAPPERS = {
    silent = true,
    unsilent = true,
    keepalt = true,
    keepjumps = true,
    noautocmd = true,
    verbose = true,
    leftabove = true,
    aboveleft = true,
    rightbelow = true,
    belowright = true,
    topleft = true,
    botright = true,
    vertical = true,
    horizontal = true,
}

local function _expr_head_only_before_quote(head)
    local s = tostring(head or "")
    s = s:gsub("^%s*:?%s*", "")
    s = s:gsub("^[%a]+!?", "", 1)
    return s:match("^%s*$") ~= nil
end

local function split_commands(script)
    script = tostring(script or ""):gsub("\n%s*\\", " ")
    local out, buf = {}, {}
    local in_s, in_d, esc = false, false, false
    local in_comment = false
    local seg_cmd_known = false
    local seg_mode = "commentable"
    local seg_no_bar = false
    local cmd_buf = ""
    local seg_leading = true

    local function get_prev_nonspace()
        local i = #buf
        while i > 0 do
            local ch = buf[i]
            if not (ch == " " or ch == "\t" or ch == "\r" or ch == "\n" or ch == "\f" or ch == "\v") then return ch end
            i = i - 1
        end
        return nil
    end

    local function flush_segment()
        local seg = trim(table.concat(buf))
        if #seg > 0 then
            out[#out + 1] = seg
        end
        buf = {}
        in_s, in_d, esc, in_comment = false, false, false, false
        seg_cmd_known = false
        seg_mode = "commentable"
        seg_no_bar = false
        cmd_buf = ""
        seg_leading = true
    end

    local i, n = 1, #script
    while i <= n do
        local c = script:sub(i, i)

        if in_comment then
            if c == "\n" then
                flush_segment()
            end
            i = i + 1; goto continue
        else
            if c == "\n" then
                flush_segment(); i = i + 1; goto continue
            elseif not in_s and not in_d and c == "|" and not seg_no_bar and not esc then
                local head = trim(table.concat(buf))
                if head ~= "" then
                    local cmd, rest = parse_cmd_head(head)
                    local guard = 0
                    while type(cmd) == "string" and COMMAND_WRAPPERS[cmd] and guard < 8 do
                        head = trim(rest or "")
                        if head == "" then
                            break
                        end
                        cmd, rest = parse_cmd_head(head)
                        guard = guard + 1
                    end
                    if type(cmd) == "string" and cmd ~= "" then
                        local _, nested_no_bar = _cmd_mode_and_bar(cmd)
                        if nested_no_bar then
                            buf[#buf + 1] = c; i = i + 1; goto continue
                        end
                    end
                end
                local prevc = (i > 1) and script:sub(i - 1, i - 1) or ""
                if prevc == "\\" then
                    buf[#buf + 1] = c; i = i + 1; goto continue
                end
                if seg_mode == "expr" then
                    local nextc = (i < n) and script:sub(i + 1, i + 1) or ""
                    if prevc == "|" or nextc == "|" then
                        buf[#buf + 1] = c; i = i + 1; goto continue
                    end
                end
                flush_segment(); i = i + 1; goto continue
            end
        end

        if esc then
            buf[#buf + 1] = c; esc = false; i = i + 1; goto continue
        end
        if c == "\\" then
            if in_s then
                buf[#buf + 1] = c; i = i + 1; goto continue
            end
            esc = true; buf[#buf + 1] = c; i = i + 1; goto continue
        end

        if not in_d and c == "'" then
            in_s = not in_s
            buf[#buf + 1] = c; i = i + 1; goto continue
        end

        if not in_s and c == '"' then
            if seg_mode == "commentable" then
                in_comment = true
                i = i + 1; goto continue
            elseif seg_mode == "expr" then
                if not in_d then
                    local prev = get_prev_nonspace()
                    local start_string = false
                    if not prev then
                        start_string = true
                    elseif
                        prev:match("[=,:%(%[%{%+%-%*/%%<>~%^&|?#%.]")
                        or _expr_head_only_before_quote(table.concat(buf))
                    then
                        start_string = true
                    end
                    if not start_string then
                        in_comment = true
                        i = i + 1; goto continue
                    end
                end
                in_d = not in_d
                buf[#buf + 1] = c; i = i + 1; goto continue
            else
                buf[#buf + 1] = c; i = i + 1; goto continue
            end
        end

        if not seg_cmd_known and not in_s and not in_d then
            if seg_leading then
                if c == ":" or c == " " or c == "\t" or c == "\r" or c == "\n" or c == "\f" or c == "\v" then
                    buf[#buf + 1] = c
                    if c ~= ":" then seg_leading = false end
                    i = i + 1; goto continue
                else
                    seg_leading = false
                end
            end
            if #cmd_buf == 0 then
                local b = c:byte()
                if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) then
                    cmd_buf = c
                else
                    buf[#buf + 1] = c; i = i + 1; goto continue
                end
            else
                local b = c:byte()
                if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
                    cmd_buf = cmd_buf .. c
                elseif c == "!" then
                    cmd_buf = cmd_buf .. c
                    local mode, no_bar = _cmd_mode_and_bar(cmd_buf)
                    seg_mode = mode
                    seg_no_bar = no_bar
                    seg_cmd_known = true
                elseif c == " " or c == "\t" or c == "\r" or c == "\n" or c == "\f" or c == "\v" then
                    local mode, no_bar = _cmd_mode_and_bar(cmd_buf)
                    seg_mode = mode
                    seg_no_bar = no_bar
                    seg_cmd_known = true
                    buf[#buf + 1] = c; i = i + 1; goto continue
                else
                    local mode, no_bar = _cmd_mode_and_bar(cmd_buf)
                    seg_mode = mode
                    seg_no_bar = no_bar
                    seg_cmd_known = true
                    buf[#buf + 1] = c; i = i + 1; goto continue
                end
            end
        end

        buf[#buf + 1] = c
        i = i + 1
        ::continue::
    end

    local tail = trim(table.concat(buf))
    if #tail > 0 then
        out[#out + 1] = tail
    end
    return out
end

local function _is_ident(seg)
    return seg:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function _validate_name(full)
    local scope, rest = full:match("^([gsalv]):(.+)$")
    if not scope then rest = full end
    if rest:match("^[%w_%.#]+$") == nil then return false end
    if rest:match("^[%.#]") or rest:match("[%.#]$") or rest:match("[%.#][%.#]") then return false end
    for seg in rest:gmatch("[^%.#]+") do
        if not _is_ident(seg) then return false end
    end
    return true
end

local function parse_function_head(rest)
    local s = trim(rest or "")
    local lp = s:find("%(")
    if not lp then return nil end
    local name = trim(s:sub(1, lp - 1))
    local rp = s:find("%)", lp + 1)
    if not rp then return nil end
    local params = s:sub(lp + 1, rp - 1)
    local attrstr = trim(s:sub(rp + 1))
    if not _validate_name(name) then return nil end
    return name, params, attrstr
end

local function strip_range_prefix(s)
    local i, n = 1, #s
    local function skip_ws()
        while i <= n do
            local c = s:sub(i, i)
            if not (c == " " or c == "\t" or c == "\r" or c == "\n" or c == "\f" or c == "\v") then break end
            i = i + 1
        end
    end
    local function skip_addr()
        skip_ws()
        local c = s:sub(i, i)
        if c == "" then return false end
        if c == "%" or c == "." or c == "$" then
            i = i + 1; return true
        end
        if c == "'" then
            if i + 1 <= n then i = i + 2; return true end
            return false
        end
        local b = c:byte()
        if b and b >= 48 and b <= 57 then
            while i <= n do
                local db = s:byte(i)
                if not db or db < 48 or db > 57 then break end
                i = i + 1
            end
            return true
        end
        return false
    end

    skip_ws()
    local start = i
    if not skip_addr() then return s end
    skip_ws()
    local sep = s:sub(i, i)
    if sep == "," or sep == ";" then
        i = i + 1
        skip_addr()
        skip_ws()
    end
    if start == i then
        return s
    end
    return s:sub(i)
end

function parse_cmd_head(line)
    local s = tostring(line or ""):gsub("^%s+", "")
    while true do
        local c = s:sub(1, 1)
        if c == ":" then
            s = s:sub(2):gsub("^%s+", "")
        else
            break
        end
    end

    local count_prefix = s:match("^(%d+)")
    if count_prefix then
        local after_count = s:sub(#count_prefix + 1)
        local tail = after_count:gsub("^%s+", "")
        local base = tail:match("^([%a][%w]*)")
        if base then
            local resolved, rerr = resolve_cmd_name(base)
            if not Error.IsError(rerr) and resolved == "verbose" then
                local raw_base = base
                local bang = tail:sub(#base + 1, #base + 1) == "!"
                local rest = tail:sub(#base + (bang and 2 or 1)):gsub("^%s+", "")
                return resolved, rest, nil, bang, raw_base, tonumber(count_prefix)
            end
        end
    end

    s = strip_range_prefix(s)
    while true do
        local c = s:sub(1, 1)
        if c == ":" then
            s = s:sub(2):gsub("^%s+", "")
        else
            break
        end
    end
    local base = s:match("^([%a][%w]*)")
    if not base then return nil, s end
    local raw_base = base
    local bang = s:sub(#base + 1, #base + 1) == "!"
    local rest = s:sub(#base + (bang and 2 or 1)):gsub("^%s+", "")

    local resolved, rerr = resolve_cmd_name(base)
    if Error.IsError(rerr) then
        return nil, rest, rerr, bang, raw_base
    end
    return resolved, rest, nil, bang, raw_base, nil
end

local function lua_string(s)
    return string.format("%q", s or "")
end

local function lua_literal(v)
    if type(v) == "number" then
        return tostring(v)
    elseif type(v) == "boolean" then
        return v and "true" or "false"
    end
    return lua_string(v)
end

local function split_ws_static(raw)
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

local function lua_string_list(items)
    local out = {}
    for i = 1, #items do
        out[#out + 1] = lua_string(items[i])
    end
    return "{ " .. table.concat(out, ", ") .. " }"
end

local function resolve_dispatch_for_node(node)
    local lname = node.cmd:lower()
    if lname == "" then
        return nil
    end
    if DISPATCH_MIN_ABBREV[lname] or MAP_COMMAND_SPECS[lname] or Commands.MENU_COMMAND_SPECS[lname] then
        return lname
    end
    local resolved = resolve_dispatch_name(lname)
    if not Error.IsError(resolved) then
        return resolved
    end
    return nil
end

local function compile_invocation_spec(node)
    local cmd = node.cmd
    local rest = node.rest
    local lname = cmd:lower()
    local ws_args = node.ws_args or split_ws_static(rest)

    local fields = {
        "name = " .. lua_string(cmd),
        "lname = " .. lua_string(lname),
        "qargs = " .. lua_string(rest),
        "bang = " .. (node.bang and "true" or "false"),
        "ws_args = " .. lua_string_list(ws_args),
    }

    local dispatch = node.dispatch or resolve_dispatch_for_node(node)
    if dispatch then
        fields[#fields + 1] = "dispatch = " .. lua_string(dispatch)
    end

    return "{ " .. table.concat(fields, ", ") .. " }"
end

local function build_precompiled_node(node, include_spec)
    local fields = {
        "line = " .. tostring(node.line),
        "text = " .. lua_string(node.text),
        "cmd = " .. lua_string(node.cmd),
        "rest = " .. lua_string(node.rest),
    }
    if include_spec then
        fields[#fields + 1] = "spec = " .. compile_invocation_spec(node)
    end
    return "{ " .. table.concat(fields, ", ") .. " }"
end

local function split_params(param_str)
    local out = {}
    param_str = tostring(param_str or "")
    for p in param_str:gmatch("([^,]+)") do
        local trimmed = p:gsub("^%s+", ""):gsub("%s+$", "")
        if #trimmed > 0 then
            out[#out + 1] = trimmed
        end
    end
    return out
end

local function split_top_args(arg_str)
    local s = tostring(arg_str or "")
    local out, buf = {}, {}
    local depth_p, depth_c, depth_s = 0, 0, 0
    local in_s, in_d, esc = false, false, false
    local i, n = 1, #s

    local function flush()
        local seg = table.concat(buf):gsub("^%s+", ""):gsub("%s+$", "")
        if #seg > 0 then
            out[#out + 1] = seg
        end
        buf = {}
    end

    while i <= n do
        local c = s:sub(i, i)
        if esc then
            buf[#buf + 1] = c
            esc = false
        elseif c == "\\" then
            if not in_s then esc = true end
            buf[#buf + 1] = c
        elseif not in_d and c == "'" then
            in_s = not in_s
            buf[#buf + 1] = c
        elseif not in_s and c == '"' then
            in_d = not in_d
            buf[#buf + 1] = c
        elseif not in_s and not in_d then
            if c == "(" then
                depth_p = depth_p + 1
                buf[#buf + 1] = c
            elseif c == ")" then
                depth_p = math.max(0, depth_p - 1)
                buf[#buf + 1] = c
            elseif c == "{" then
                depth_c = depth_c + 1
                buf[#buf + 1] = c
            elseif c == "}" then
                depth_c = math.max(0, depth_c - 1)
                buf[#buf + 1] = c
            elseif c == "[" then
                depth_s = depth_s + 1
                buf[#buf + 1] = c
            elseif c == "]" then
                depth_s = math.max(0, depth_s - 1)
                buf[#buf + 1] = c
            elseif c == "," and depth_p == 0 and depth_c == 0 and depth_s == 0 then
                flush()
            else
                buf[#buf + 1] = c
            end
        else
            buf[#buf + 1] = c
        end
        i = i + 1
    end

    if #buf > 0 then
        flush()
    end
    return out
end

local function split_let_assignment(rest)
    local s = tostring(rest or "")
    local in_s, in_d, esc = false, false, false
    local depth_p, depth_c, depth_b = 0, 0, 0
    local i, n = 1, #s
    while i <= n do
        local ch = s:sub(i, i)
        if esc then
            esc = false
        elseif ch == "\\" then
            if not in_s then esc = true end
        elseif not in_d and ch == "'" then
            in_s = not in_s
        elseif not in_s and ch == '"' then
            in_d = not in_d
        elseif not in_s and not in_d then
            if ch == "(" then depth_p = depth_p + 1
            elseif ch == ")" then depth_p = math.max(0, depth_p - 1)
            elseif ch == "{" then depth_c = depth_c + 1
            elseif ch == "}" then depth_c = math.max(0, depth_c - 1)
            elseif ch == "[" then depth_b = depth_b + 1
            elseif ch == "]" then depth_b = math.max(0, depth_b - 1)
            elseif depth_p == 0 and depth_c == 0 and depth_b == 0 then
                local two = s:sub(i, i + 1)
                if two == "+=" or two == "-=" or two == "*=" or two == "/=" or two == "%=" or two == ".=" then
                    return trim(s:sub(1, i - 1)), two, trim(s:sub(i + 2))
                elseif ch == "=" then
                    return trim(s:sub(1, i - 1)), "=", trim(s:sub(i + 1))
                end
            end
        end
        i = i + 1
    end
    return nil
end

local function split_set_args_static(s)
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

local function rejoin_equals_static(args)
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

local function parse_command_definition(rest)
    local parts = split_ws_static(rest)
    local nargs = 0
    local name
    local body_index = #parts + 1
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
            body_index = idx + 1
            break
        end
    end
    return {
        kind = "command",
        parts = parts,
        nargs = nargs,
        name = name,
        body_index = body_index,
    }
end

local function build_ir(script)
    local cmds = split_commands(script or "")
    local ir = {}
    local idx = 1
    while idx <= #cmds do
        local line = cmds[idx]
        local marker
        local rhs = line:match("^let!?%s+.-=(.+)$")
        if rhs then
            local hd = trim(rhs):match("^<<%s*(.+)$")
            if hd then
                marker = trim(hd:match("(%S+)%s*$") or "")
                if marker == "" then
                    marker = nil
                end
            end
        end

        if marker then
            local j = idx + 1
            while j <= #cmds do
                if trim(cmds[j]) == marker then
                    break
                end
                j = j + 1
            end
            if j > #cmds then
                return nil, Error(488, marker)
            end
            local lhs = trim(line:match("^let!?%s+(.-)=<<") or "")
            if lhs == "" then
                return nil, Error(474, "Malformed heredoc :let")
            end
            local items = {}
            for k = idx + 1, j - 1 do
                local v = tostring(cmds[k] or ""):gsub("'", "''")
                items[#items + 1] = "'" .. v .. "'"
            end
            local heredoc_value = "[" .. table.concat(items, ", ") .. "]"
            ir[#ir + 1] = {
                cmd = "let",
                rest = lhs .. " = " .. heredoc_value,
                bang = false,
                raw = "let",
                verbose_count = nil,
                line = idx,
                text = line,
            }
            idx = j + 1
        else
            local cmd, rest, perr, bang, raw, verbose_count = parse_cmd_head(line)
            if Error.IsError(perr) then
                return nil, perr
            end
            cmd = cmd or ""
            ir[#ir + 1] = {
                cmd = cmd,
                rest = rest or "",
                bang = not not bang,
                raw = raw or cmd,
                verbose_count = verbose_count,
                line = idx,
                text = line,
            }
            idx = idx + 1
        end
    end
    return ir
end

local SIMPLE_VAR_PATTERN = "^[A-Za-z_][A-Za-z0-9_]*$"
local DIRECT_SCOPES = { g = "__g", s = "__s", v = "__v" }
local SHARED_SCOPES = { b = true, w = true, t = true }
local LUA_KEYWORDS = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["goto"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true,
}

local function lua_key(name)
    if type(name) == "string" and name:match(SIMPLE_VAR_PATTERN) and not LUA_KEYWORDS[name] then
        return "." .. name
    end
    return "[" .. lua_string(name) .. "]"
end

local function scoped_table(scope, ctx)
    if scope == "l" then
        return "((__frame and __frame.l) or __state.l)"
    elseif scope == "a" then
        return "((__frame and __frame.a) or __state.a)"
    elseif DIRECT_SCOPES[scope] then
        return DIRECT_SCOPES[scope]
    elseif SHARED_SCOPES[scope] then
        return "__scopes." .. scope
    end
    if ctx and ctx.in_function then
        return nil
    end
    return "__g"
end

local function var_read_code(scope, name, ctx)
    if not scope and ctx and ctx.local_vars and ctx.local_vars[name] then
        return "__l_" .. tostring(name)
    end
    if not scope then
        return "((__frame and __frame.l[" .. lua_string(name) .. "] ~= nil) and __frame.l[" .. lua_string(name) .. "] or __g" .. lua_key(name) .. ")"
    end
    local tbl = scoped_table(scope, ctx)
    if not tbl then
        return "runtime:get_var(" .. lua_string(scope .. ":" .. tostring(name)) .. ")"
    end
    return tbl .. lua_key(name)
end

local function var_write_code(scope, name, value_code, ctx)
    if not scope and ctx and ctx.local_vars and ctx.local_vars[name] then
        return "__l_" .. tostring(name) .. " = " .. value_code
    end
    if not scope then
        if ctx and ctx.in_function then
            return "((__frame and __frame.l) or __state.l)" .. lua_key(name) .. " = " .. value_code
        end
        return "((__frame and __frame.l) or __g)" .. lua_key(name) .. " = " .. value_code
    end
    local tbl = scoped_table(scope, ctx)
    if not tbl then
        return "runtime:assign(" .. lua_string(scope .. ":" .. tostring(name)) .. ", " .. value_code .. ")"
    end
    return tbl .. lua_key(name) .. " = " .. value_code
end

local function parse_static_lvalue(lhs)
    local s = trim(lhs)
    local scope, name = s:match("^([gslavbtw]):([A-Za-z_][A-Za-z0-9_]*)$")
    if scope then
        return { scope = scope, name = name }
    end
    if s:match(SIMPLE_VAR_PATTERN) then
        return { scope = nil, name = s }
    end
    if s:find("{", 1, true) then
        local ast = VimExpr.parse(s)
        if ast and (ast.kind == "curlyvar" or ast.kind == "varcurly") then
            return { dynamic = ast }
        end
    end
    return nil
end

local function compile_ast(node, ctx)
    if type(node) ~= "table" then
        return nil
    end
    local k = node.kind
    if k == "num" then
        return { code = tostring(node.val), kind = "number" }
    elseif k == "str" then
        return { code = lua_string(node.val), kind = "string" }
    elseif k == "var" then
        if node.name == nil then return nil end
        return { code = var_read_code(node.scope, node.name, ctx), kind = "unknown" }
    elseif k == "scope" then
        local tbl = scoped_table(node.scope, ctx)
        if not tbl then return nil end
        return { code = tbl, kind = "table" }
    elseif k == "opt" then
        local mode = "auto"
        if node.scope == "g" then mode = "global"
        elseif node.scope == "l" then mode = "local"
        elseif node.scope and node.scope ~= "" then return nil end
        return { code = string.format("runtime:get_option(%q, %q)", node.name, mode), kind = "unknown" }
    elseif k == "env" then
        return { code = "__ops.env(" .. lua_string(node.name) .. ")", kind = "string" }
    elseif k == "reg" then
        return { code = "__ops.reg(" .. lua_string(node.name) .. ")", kind = "string" }
    elseif k == "lastline" then
        return { code = "runtime:call_func(" .. lua_string("line") .. ", { " .. lua_string("$") .. " })", kind = "number" }
    elseif k == "curlyvar" then
        local inner = compile_ast(node.inner, ctx)
        if not inner then return nil end
        return {
            code = "__ops.var(__ops.name_part(" .. inner.code .. ") .. " .. lua_string(node.suffix) .. ", __state, __frame, __scopes)",
            kind = "unknown",
        }
    elseif k == "varcurly" then
        local parts = {}
        for i = 1, #node.parts do
            local part = node.parts[i]
            if part.kind == "lit" then
                parts[#parts + 1] = lua_string(part.val)
            else
                local compiled_part = compile_ast(part.val, ctx)
                if not compiled_part then return nil end
                parts[#parts + 1] = "__ops.name_part(" .. compiled_part.code .. ")"
            end
        end
        return {
            code = "__ops.var(" .. table.concat(parts, " .. ") .. ", __state, __frame, __scopes)",
            kind = "unknown",
        }
    elseif k == "list" then
        local items = {}
        for i = 1, #node.items do
            local item = compile_ast(node.items[i], ctx)
            if not item then return nil end
            items[#items + 1] = item.code
        end
        return { code = "__ops.list({ " .. table.concat(items, ", ") .. " })", kind = "table" }
    elseif k == "dict" then
        local entries = {}
        for i = 1, #node.entries do
            local pair = node.entries[i]
            local value = compile_ast(pair.v, ctx)
            if not value then return nil end
            entries[#entries + 1] = "[" .. lua_string(pair.k) .. "] = " .. value.code
        end
        return { code = "__ops.dict({ " .. table.concat(entries, ", ") .. " })", kind = "table" }
    elseif k == "index" then
        local container = compile_ast(node.a, ctx)
        local idx = compile_ast(node.idx, ctx)
        if not container or not idx then return nil end
        return { code = "__ops.index(" .. container.code .. ", " .. idx.code .. ")", kind = "unknown" }
    elseif k == "slice" then
        local container = compile_ast(node.a, ctx)
        if not container then return nil end
        local first = node.first and compile_ast(node.first, ctx) or { code = "nil" }
        local last = node.last and compile_ast(node.last, ctx) or { code = "nil" }
        if not first or not last then return nil end
        return { code = "__ops.slice(" .. container.code .. ", " .. first.code .. ", " .. last.code .. ")", kind = "unknown" }
    elseif k == "unary" then
        local a = compile_ast(node.a, ctx)
        if not a then return nil end
        if node.op == "!" then
            return { code = "(__ops.truthy(" .. a.code .. ") and 0 or 1)", kind = "number" }
        elseif node.op == "+" then
            return { code = "__ops.to_number(" .. a.code .. ")", kind = "number" }
        elseif node.op == "-" then
            return { code = "(-__ops.to_number(" .. a.code .. "))", kind = "number" }
        end
    elseif k == "binop" then
        local a = compile_ast(node.a, ctx)
        local b = compile_ast(node.b, ctx)
        if not a or not b then return nil end
        local op = node.op
        if op == "||" then
            return { code = "(__ops.truthy(" .. a.code .. ") and 1 or (__ops.truthy(" .. b.code .. ") and 1 or 0))", kind = "number" }
        elseif op == "&&" then
            return { code = "(__ops.truthy(" .. a.code .. ") and (__ops.truthy(" .. b.code .. ") and 1 or 0) or 0)", kind = "number" }
        elseif op == "+" then
            return { code = "__ops.add(" .. a.code .. ", " .. b.code .. ")", kind = "number" }
        elseif op == "-" or op == "*" or op == "/" or op == "%" then
            return { code = "(__ops.to_number(" .. a.code .. ") " .. op .. " __ops.to_number(" .. b.code .. "))", kind = "number" }
        elseif op == "." or op == ".." then
            return { code = "(__ops.to_string(" .. a.code .. ") .. __ops.to_string(" .. b.code .. "))", kind = "string" }
        elseif op:match("^[=!<>]=?[#?]?$") then
            return { code = string.format("runtime:cmp(%s, %q, %s)", a.code, op, b.code), kind = "boolean" }
        elseif op:match("^is[#?]?$") or op:match("^isnot[#?]?$") then
            local suffix = op:match("([#?])$")
            local base = op:gsub("[#?]$", "")
            local cmpop = (base == "isnot") and "!=" or "=="
            if suffix then cmpop = cmpop .. suffix end
            return { code = string.format("runtime:cmp(%s, %q, %s)", a.code, cmpop, b.code), kind = "boolean" }
        elseif op:match("^!?~[#?]?$") or op:match("^=~[#?]?$") then
            return { code = "__ops.match_op(" .. a.code .. ", " .. lua_string(op) .. ", " .. b.code .. ")", kind = "number" }
        end
        return nil
    elseif k == "ternary" then
        local cond = compile_ast(node.cond, ctx)
        local tv = compile_ast(node.t, ctx)
        local fv = compile_ast(node.f, ctx)
        if not cond or not tv or not fv then return nil end
        return { code = "(__ops.truthy(" .. cond.code .. ") and " .. tv.code .. " or " .. fv.code .. ")", kind = "unknown" }
    elseif k == "lambda" then
        local body = compile_ast(node.body, ctx)
        if not body then return nil end
        local lines = {
            "(function(...)",
            "local __argv = { ... }",
            "local __frame = { l = {}, a = {}, v = __state.v }",
            "__frame.a[" .. lua_string("0") .. "] = select('#', ...)",
        }
        for i = 1, #node.params do
            local name = tostring(node.params[i])
            lines[#lines + 1] = "__frame.l[" .. lua_string(name) .. "] = __argv[" .. tostring(i) .. "]"
            lines[#lines + 1] = "__frame.a[" .. lua_string(name) .. "] = __argv[" .. tostring(i) .. "]"
        end
        lines[#lines + 1] = "return " .. body.code
        lines[#lines + 1] = "end)"
        return { code = table.concat(lines, "; "), kind = "function" }
    elseif k == "call" then
        local fname
        if node.scope == "v" and node.name == "lua" and node.lua_path then
            fname = "v:lua." .. node.lua_path
        elseif node.scope then
            fname = node.scope .. ":" .. tostring(node.name)
        else
            fname = tostring(node.name)
        end
        local args = {}
        for i = 1, #node.args do
            local arg = compile_ast(node.args[i], ctx)
            if not arg then return nil end
            args[#args + 1] = arg.code
        end
        return { code = "runtime:call_func(" .. lua_string(fname) .. ", { " .. table.concat(args, ", ") .. " })", kind = "unknown" }
    end
    return nil
end

local function _compile_expr_typed(expr, ctx)
    ctx = ctx or {}
    if not ctx.direct_backend then
        return { code = string.format("runtime:eval_expr(%q)", tostring(expr or "")), kind = "unknown" }
    end
    local ast, parse_err
    if type(expr) == "table" and expr.kind then
        ast = expr
    else
        ast, parse_err = VimExpr.parse(expr)
    end
    if not ast then
        error(Error(474, "Unsupported expression: " .. tostring(expr or "") .. " (" .. tostring(parse_err) .. ")"))
    end
    local compiled = compile_ast(ast, ctx)
    if compiled then
        return compiled
    end
    error(Error(474, "Unsupported expression: " .. tostring(expr or "")))
end

local function dynamic_lvalue_name_code(node, ctx)
    if node.kind == "curlyvar" then
        local inner = compile_ast(node.inner, ctx)
        if not inner then return nil end
        return "__ops.name_part(" .. inner.code .. ") .. " .. lua_string(node.suffix)
    elseif node.kind == "varcurly" then
        local parts = {}
        for i = 1, #node.parts do
            local part = node.parts[i]
            if part.kind == "lit" then
                parts[#parts + 1] = lua_string(part.val)
            else
                local compiled_part = compile_ast(part.val, ctx)
                if not compiled_part then return nil end
                parts[#parts + 1] = "__ops.name_part(" .. compiled_part.code .. ")"
            end
        end
        return table.concat(parts, " .. ")
    end
    return nil
end

local function lvalue_read_code(target, ctx)
    if target.dynamic then
        local name_code = dynamic_lvalue_name_code(target.dynamic, ctx)
        if not name_code then
            error(Error(474, "Unsupported lvalue"))
        end
        return "__ops.var(" .. name_code .. ", __state, __frame, __scopes)"
    end
    return var_read_code(target.scope, target.name, ctx)
end

local function lvalue_write_code(target, value_code, ctx)
    if target.dynamic then
        local name_code = dynamic_lvalue_name_code(target.dynamic, ctx)
        if not name_code then
            error(Error(474, "Unsupported lvalue"))
        end
        return "__ops.set_var(" .. name_code .. ", " .. value_code .. ", __state, __frame, __scopes)"
    end
    return var_write_code(target.scope, target.name, value_code, ctx)
end

local function _compile_condition(expr, ctx)
    local c = _compile_expr_typed(expr, ctx)
    if c.kind == "boolean" then
        return c.code
    end
    return "__ops.truthy(" .. c.code .. ")"
end

function Compiler.compile_expr(expr, ctx)
    return _compile_expr_typed(expr, ctx).code
end

function Compiler.compile_command(node, ctx)
    local cmd = node.cmd:lower()
    local arg = node.arg

    if cmd == "let" then
        local lhs, op, rhs = arg.lhs, arg.op, arg.rhs
        local static_lhs = parse_static_lvalue(lhs)
        local rhs_code = Compiler.compile_expr(arg.rhs_ast, ctx)
        if op == "=" then
            if static_lhs then
                return { code = lvalue_write_code(static_lhs, rhs_code, ctx) }
            end
            return { code = string.format("runtime:assign(%s, %s)", lua_string(lhs), rhs_code) }
        end

        if op ~= "+=" and op ~= "-=" and op ~= "*=" and op ~= "/=" and op ~= "%=" and op ~= ".=" then
            error(Error(474, "let"))
        end
        if static_lhs then
            local cur_code = lvalue_read_code(static_lhs, ctx)
            local value_code
            if op == "+=" then
                value_code = "__ops.add(" .. cur_code .. ", " .. rhs_code .. ")"
            elseif op == ".=" then
                value_code = "(__ops.to_string(" .. cur_code .. ") .. __ops.to_string(" .. rhs_code .. "))"
            else
                local binop = op:sub(1, 1)
                value_code = "(__ops.to_number(" .. cur_code .. ") " .. binop .. " __ops.to_number(" .. rhs_code .. "))"
            end
            return { code = lvalue_write_code(static_lhs, value_code, ctx) }
        end
        return {
            code = string.format(
                "do local __rv=runtime:assign_compound(%s,%s,%s); if Error.IsError(__rv) then error(__rv) end end",
                lua_string(lhs),
                lua_string(op),
                rhs_code
            ),
        }
    elseif cmd == "unlet" then
        return { code = string.format("runtime:unlet({ names = %s },%s)", lua_string_list(arg.names), node.bang and "true" or "false") }
    elseif cmd == "break" then
        return { code = "error(runtime:break_exc())" }
    elseif cmd == "continue" then
        if not ctx.loop_continue then
            return { code = "error('continue outside loop')" }
        end
        return { code = "error(runtime:continue_exc())" }
    elseif cmd == "execute" then
        if not arg.dynamic then
            local values = {}
            for i = 1, #arg.exprs do
                values[#values + 1] = Compiler.compile_expr(arg.exprs[i].ast, ctx)
            end
            return { code = "runtime:execute_values({ " .. table.concat(values, ", ") .. " })" }
        end
        return { code = string.format("runtime:execute(%s)", lua_string(node.rest)) }
    elseif cmd == "put" then
        local spec = compile_invocation_spec(node)
        if arg.source == "default" then
            return { code = "runtime:put_compiled({ source = 'default' }, " .. (node.bang and "true" or "false") .. ", " .. spec .. ")" }
        elseif arg.source == "register" then
            return { code = "runtime:put_compiled({ source = 'register', reg = " .. lua_string(arg.reg) .. " }, " .. (node.bang and "true" or "false") .. ", " .. spec .. ")" }
        elseif arg.source == "expr_reuse" then
            return { code = "runtime:put_compiled({ source = 'expr_reuse' }, " .. (node.bang and "true" or "false") .. ", " .. spec .. ")" }
        elseif arg.source == "expr" then
            return {
                code = "runtime:put_compiled({ source = 'expr', expr = " .. lua_string(arg.expr) .. ", value = "
                    .. Compiler.compile_expr(arg.expr_ast, ctx) .. " }, "
                    .. (node.bang and "true" or "false") .. ", " .. spec .. ")",
            }
        end
        return { code = "error(Error(488, " .. lua_string(arg.raw) .. "))" }
    elseif cmd == "verbose" then
        local level = tonumber(node.verbose_count) or 1
        return { code = string.format("runtime:exec_verbose(%d, %s)", level, lua_string(node.rest)) }
    elseif cmd == "echo" or cmd == "echoerr" or cmd == "echomsg" or cmd == "echon" then
        if node.text:match("^%s*:?[%%%.%$%'%d]") then
            return { code = "error(Error(481))" }
        end
        local values = {}
        for i = 1, #arg.exprs do
            values[#values + 1] = Compiler.compile_expr(arg.exprs[i].ast, ctx)
        end
        return { code = "runtime:echo_values(" .. lua_string(cmd) .. ", { " .. table.concat(values, ", ") .. " })" }
    elseif cmd == "call" then
        return { code = "do local __rv = " .. Compiler.compile_expr(arg.expr_ast, ctx) .. " end" }
    elseif cmd == "return" then
        local val = "nil"
        if node.rest ~= "" then
            val = Compiler.compile_expr(arg.expr_ast, ctx)
        end
        return { code = string.format("error(runtime:return_exc(%s))", val) }
    elseif cmd == "finish" then
        return { code = "error(runtime:return_exc(nil))" }
    elseif cmd == "set" or cmd == "setglobal" or cmd == "setlocal" then
        local scope = (cmd == "setglobal" and "global") or (cmd == "setlocal" and "local") or "both"
        return { code = string.format("runtime:set_options({ tokens = %s }, %s)", lua_string_list(arg.tokens), lua_string(scope)) }
    elseif cmd == "autocmd" then
        return { code = string.format("runtime:define_autocmd({ args = %s }, %s)", lua_string_list(arg.args), node.bang and "true" or "false") }
    elseif cmd == "doautoall" then
        return { code = string.format("runtime:doautoall({ event = %s })", lua_string(arg.event)) }
    elseif cmd == "command" then
        return {
            code = string.format(
                "runtime:define_command({ parts = %s, nargs = %s, name = %s, body_index = %d }, %s)",
                lua_string_list(arg.parts),
                lua_literal(arg.nargs),
                lua_string(arg.name),
                arg.body_index,
                node.bang and "true" or "false"
            ),
        }
    end

    local spec = compile_invocation_spec(node)
    if Commands.get_spec(cmd) then
        return { code = "runtime:invoke_compiled_builtin_command(" .. lua_string(cmd) .. ", " .. spec .. ")" }
    end
    return { code = "runtime:invoke_compiled_command(" .. spec .. ")" }
end

local function slice_ir(seq, first, last)
    local out = {}
    for i = first, last do
        out[#out + 1] = seq[i]
    end
    return out
end

local BLOCK_CLOSERS = {
    ["if"] = "endif",
    ["while"] = "endwhile",
    ["for"] = "endfor",
    ["try"] = "endtry",
    ["function"] = "endfunction",
}

local find_matching_end

local function analyze_control_flow(seq)
    local stack = {}

    local function top()
        return stack[#stack]
    end

    local function push(entry)
        stack[#stack + 1] = entry
    end

    local function pop(expected, code, arg)
        local entry = top()
        if not entry or entry.kind ~= expected then
            return nil, Error(code, arg)
        end
        stack[#stack] = nil
        return entry
    end

    for i = 1, #seq do
        local node = seq[i]
        local cmd = node.cmd

        if cmd == "if" then
            push({ kind = "if", saw_else = false })
        elseif cmd == "elseif" then
            local entry = top()
            if not entry or entry.kind ~= "if" or entry.saw_else then
                return nil, Error(581)
            end
        elseif cmd == "else" then
            local entry = top()
            if not entry or entry.kind ~= "if" or entry.saw_else then
                return nil, Error(581)
            end
            entry.saw_else = true
        elseif cmd == "endif" then
            local _, err = pop("if", 580)
            if err then
                return nil, err
            end
        elseif cmd == "while" then
            push({ kind = "while" })
        elseif cmd == "endwhile" then
            local _, err = pop("while", 588)
            if err then
                return nil, err
            end
        elseif cmd == "for" then
            local lhs, rhs = node.rest:match("^(.-)%s+in%s+(.+)$")
            lhs = trim(lhs or "")
            if lhs == "" then
                return nil, Error(474, "for")
            end
            node.iter_lhs = lhs
            node.iter_rhs = rhs
            push({ kind = "for" })
        elseif cmd == "endfor" then
            local _, err = pop("for", 474, "endfor")
            if err then
                return nil, err
            end
        elseif cmd == "try" then
            push({
                kind = "try",
                start_idx = i,
                marks = {},
                saw_finally = false,
            })
        elseif cmd == "catch" then
            local entry = top()
            if not entry or entry.kind ~= "try" or entry.saw_finally then
                return nil, Error(603)
            end
            entry.marks[#entry.marks + 1] = {
                idx = i,
                kind = "catch",
                rest = node.rest,
            }
        elseif cmd == "finally" then
            local entry = top()
            if not entry or entry.kind ~= "try" or entry.saw_finally then
                return nil, Error(606)
            end
            entry.saw_finally = true
            entry.marks[#entry.marks + 1] = {
                idx = i,
                kind = "finally",
                rest = node.rest,
            }
        elseif cmd == "endtry" then
            local entry, err = pop("try", 602)
            if err then
                return nil, err
            end

            local try_body_end = (#entry.marks > 0) and (entry.marks[1].idx - 1) or (i - 1)
            local region = {
                end_idx = i,
                try_body = slice_ir(seq, entry.start_idx + 1, try_body_end),
                catches = {},
                finally_body = nil,
            }

            for mark_idx = 1, #entry.marks do
                local mark = entry.marks[mark_idx]
                local next_idx = (mark_idx < #entry.marks) and entry.marks[mark_idx + 1].idx or i
                local body = slice_ir(seq, mark.idx + 1, next_idx - 1)
                if mark.kind == "catch" then
                    region.catches[#region.catches + 1] = {
                        rest = mark.rest,
                        body = body,
                    }
                else
                    region.finally_body = body
                end
            end

            seq[entry.start_idx].try_region = region
        elseif cmd == "function" then
            local fname, params = parse_function_head(node.rest)
            if not fname then
                return nil, Error(474, "function")
            end
            node.func_name = fname
            node.func_params = split_params(params)
            push({
                kind = "function",
                start_idx = i,
            })
        elseif cmd == "endfunction" then
            local entry, err = pop("function", 474, "endfunction")
            if err then
                return nil, err
            end
            seq[entry.start_idx].function_region = {
                end_idx = i,
                body = slice_ir(seq, entry.start_idx + 1, i - 1),
            }
        end
    end

    if #stack > 0 then
        return nil, Error(474, BLOCK_CLOSERS[stack[#stack].kind])
    end

    return true
end

local function ast_is_static(ast)
    local function walk(node)
        if type(node) ~= "table" then return false end
        local k = node.kind
        if k == "call" or k == "curlyvar" or k == "varcurly" or k == "lambda" or k == "env" or k == "reg" then
            return false
        elseif k == "num" or k == "str" or k == "var" or k == "scope" or k == "opt" then
            return true
        elseif k == "list" then
            for i = 1, #node.items do
                if not walk(node.items[i]) then return false end
            end
            return true
        elseif k == "dict" then
            for i = 1, #node.entries do
                if not walk(node.entries[i].v) then return false end
            end
            return true
        elseif k == "index" then
            return walk(node.a) and walk(node.idx)
        elseif k == "slice" then
            return walk(node.a)
                and (not node.first or walk(node.first))
                and (not node.last or walk(node.last))
        elseif k == "unary" then
            return walk(node.a)
        elseif k == "binop" then
            return walk(node.a) and walk(node.b)
        elseif k == "ternary" then
            return walk(node.cond) and walk(node.t) and walk(node.f)
        end
        return false
    end
    return walk(ast)
end

local function expr_is_static(expr)
    return ast_is_static(expr)
end

local function parse_expr_for_node(node, field, expr)
    if expr == nil or expr == "" then
        return true
    end
    local ast, parse_err = VimExpr.parse(expr)
    if not ast then
        return nil, Error(474, "Unsupported expression: " .. tostring(expr or "") .. " (" .. tostring(parse_err) .. ")")
    end
    node[field] = ast
    return true
end

local function parse_command_payloads(seq)
    for i = 1, #seq do
        local node = seq[i]
        local cmd = node.cmd
        if cmd == "let" then
            local lhs, op, rhs = split_let_assignment(node.rest)
            if not lhs or not op then
                return nil, Error(474, "let")
            end
            local arg = {
                kind = "let",
                lhs = trim(lhs),
                op = op,
                rhs = trim(rhs),
            }
            node.arg = arg
            local ok, err = parse_expr_for_node(arg, "rhs_ast", arg.rhs)
            if err then return nil, err end
        elseif cmd == "if" or cmd == "elseif" or cmd == "while" then
            local arg = { kind = "expr", expr = node.rest }
            node.arg = arg
            local ok, err = parse_expr_for_node(arg, "expr_ast", arg.expr)
            if err then return nil, err end
        elseif cmd == "for" then
            local arg = {
                kind = "for",
                lhs = node.iter_lhs,
                rhs = node.iter_rhs,
            }
            node.arg = arg
            local ok, err = parse_expr_for_node(arg, "rhs_ast", arg.rhs)
            if err then return nil, err end
        elseif cmd == "call" or (cmd == "return" and node.rest ~= "") then
            local arg = { kind = "expr", expr = node.rest }
            node.arg = arg
            local ok, err = parse_expr_for_node(arg, "expr_ast", arg.expr)
            if err then return nil, err end
        elseif cmd == "echo" or cmd == "echoerr" or cmd == "echomsg" or cmd == "echon" then
            local exprs = VimExpr.splitExpressionAsts(node.rest)
            for j = 1, #exprs do
                if not exprs[j].ast then
                    return nil, Error(474, "Unsupported expression: " .. tostring(exprs[j].text))
                end
            end
            node.arg = {
                kind = "expr_list",
                exprs = exprs,
            }
        elseif cmd == "unlet" then
            node.arg = {
                kind = "unlet",
                names = split_ws_static(node.rest),
            }
        elseif cmd == "set" or cmd == "setglobal" or cmd == "setlocal" then
            node.arg = {
                kind = "set",
                tokens = rejoin_equals_static(split_set_args_static(node.rest)),
            }
        elseif cmd == "execute" then
            local exprs = VimExpr.splitExpressionAsts(node.rest)
            node.arg = {
                kind = "execute",
                exprs = exprs,
                dynamic = #exprs == 0 or node.rest:find("$'", 1, true) ~= nil,
            }
            for j = 1, #exprs do
                if not exprs[j].ast then
                    node.arg.dynamic = true
                    break
                end
            end
        elseif cmd == "put" then
            local raw = trim(node.rest)
            if raw == "" then
                node.arg = { kind = "put", source = "default" }
            elseif raw:sub(1, 1) == "=" then
                local expr = trim(raw:sub(2))
                node.arg = { kind = "put", source = (expr == "" and "expr_reuse" or "expr"), expr = expr }
                if expr ~= "" then
                    local ok, err = parse_expr_for_node(node.arg, "expr_ast", expr)
                    if err then return nil, err end
                end
            elseif #raw == 1 then
                node.arg = { kind = "put", source = "register", reg = raw }
            else
                node.arg = { kind = "put", source = "invalid", raw = raw }
            end
        elseif cmd == "autocmd" then
            node.arg = {
                kind = "autocmd",
                args = split_ws_static(node.rest),
            }
        elseif cmd == "command" then
            node.arg = parse_command_definition(node.rest)
        elseif cmd == "doautoall" then
            local ws_args = split_ws_static(node.rest)
            node.arg = {
                kind = "doautoall",
                event = ws_args[1],
            }
        end
    end
    return true
end

local function infer_function_locals(seq)
    local locals = {}
    local safe = true
    local i = 1
    while i <= #seq do
        local node = seq[i]
        local cmd = node.cmd
        if cmd == "function" then
            i = find_matching_end(seq, i, "function", "endfunction") + 1
            goto continue
        elseif cmd == "let" then
            local let_arg = node.arg
            local target = parse_static_lvalue(let_arg.lhs)
            if not target or target.scope ~= nil or not expr_is_static(let_arg.rhs_ast) then
                safe = false
                break
            end
            locals[target.name] = true
        elseif cmd == "for" then
            local for_arg = node.arg
            local target = parse_static_lvalue(for_arg.lhs)
            if not target or target.scope ~= nil or not expr_is_static(for_arg.rhs_ast) then
                safe = false
                break
            end
            locals[target.name] = true
        elseif cmd == "if" or cmd == "elseif" or cmd == "while" or cmd == "return" then
            local expr_arg = node.arg
            if node.rest ~= "" and not expr_is_static(expr_arg.expr_ast) then
                safe = false
                break
            end
        elseif cmd == "else" or cmd == "endif" or cmd == "endwhile" or cmd == "endfor"
            or cmd == "try" or cmd == "catch" or cmd == "finally" or cmd == "endtry"
            or cmd == "break" or cmd == "continue" or cmd == "finish" then
            -- Structured control-flow nodes do not expose l: by themselves.
        else
            safe = false
            break
        end
        i = i + 1
        ::continue::
    end
    if not safe then
        return nil
    end
    return locals
end

local function annotate_function_locals(seq)
    local i = 1
    while i <= #seq do
        local node = seq[i]
        if node.cmd == "function" then
            local region = node.function_region
            annotate_function_locals(region.body)
            node.local_vars = infer_function_locals(region.body)
            i = find_matching_end(seq, i, "function", "endfunction") + 1
        else
            i = i + 1
        end
    end
end

local function new_script_emitter()
    local emitter = {
        static_nodes = {},
        body_lines = {},
    }

    function emitter:emit(line)
        self.body_lines[#self.body_lines + 1] = line
    end

    function emitter:intern_node(node, include_spec)
        self.static_nodes[#self.static_nodes + 1] = build_precompiled_node(node, include_spec)
        return "__nodes[" .. tostring(#self.static_nodes) .. "]"
    end

    return emitter
end

local function emit_loop_error_guard(emitter, indent, ok_name, err_name, label)
    emitter:emit(indent .. "if not " .. ok_name .. " then")
    emitter:emit(indent .. "  if type(" .. err_name .. ") == 'table' and " .. err_name .. ".__continue then goto " .. label .. " end")
    emitter:emit(indent .. "  if type(" .. err_name .. ") == 'table' and " .. err_name .. ".__break then break end")
    emitter:emit(indent .. "  if type(" .. err_name .. ") == 'table' and " .. err_name .. ".__ret then error(" .. err_name .. ") end")
    emitter:emit(indent .. "  error(" .. err_name .. ")")
    emitter:emit(indent .. "end")
end

function find_matching_end(seq, start_idx, open_cmd, close_cmd)
    local depth = 0
    for i = start_idx, #seq do
        local cmd = seq[i].cmd
        if cmd == open_cmd then
            depth = depth + 1
        elseif cmd == close_cmd then
            depth = depth - 1
            if depth == 0 then
                return i
            end
        end
    end
    return nil
end

local function merged_ctx(base, state, loop_stack)
    local ctx = {}
    if base then
        for k, v in pairs(base) do ctx[k] = v end
    end
    ctx.state = state
    ctx.direct_backend = true
    ctx.loop_continue = loop_stack[#loop_stack]
    return ctx
end

local function emit_regular_node(emitter, node, state, loop_stack, indent, compile_ctx)
    local compiled = Compiler.compile_command(node, merged_ctx(compile_ctx, state, loop_stack))
    local node_ref = emitter:intern_node(node, false)
    emitter:emit(indent .. "runtime:set_exec_cursor_from(" .. node_ref .. ")")
    emitter:emit(indent .. "; " .. compiled.code)
end

local function emit_for_assignment(node, compile_ctx)
    local target = parse_static_lvalue(node.iter_lhs)
    if target then
        return lvalue_write_code(target, "__iter_v", compile_ctx)
    end
    return "runtime:assign(" .. lua_string(node.iter_lhs) .. ", __iter_v)"
end

local function render_compiled_chunk(emitter)
    local lines = {}
    if #emitter.static_nodes > 0 then
        lines[#lines + 1] = "local __nodes = {"
        for i = 1, #emitter.static_nodes do
            lines[#lines + 1] = "  " .. emitter.static_nodes[i] .. ","
        end
        lines[#lines + 1] = "}"
    else
        lines[#lines + 1] = "local __nodes = {}"
    end

    lines[#lines + 1] = "return function(state, runtime)"
    lines[#lines + 1] = "  if not runtime then error('runtime required') end"
    lines[#lines + 1] = "  runtime.state = state or runtime.state"
    lines[#lines + 1] = "  local Error = runtime.Error"
    lines[#lines + 1] = "  local __state = runtime.state"
    lines[#lines + 1] = "  local __ops = runtime.ops"
    lines[#lines + 1] = "  local __scopes = runtime.scopes"
    lines[#lines + 1] = "  local __g = __state.g"
    lines[#lines + 1] = "  local __s = __state.s"
    lines[#lines + 1] = "  local __v = __state.v"
    lines[#lines + 1] = "  local __frame = __state.frames[#__state.frames]"
    lines[#lines + 1] = "  runtime:_push_script_ctx()"
    lines[#lines + 1] = "  local __ok, __err = runtime:_pcall(function()"
    for i = 1, #emitter.body_lines do
        lines[#lines + 1] = emitter.body_lines[i]
    end
    lines[#lines + 1] = "  end)"
    lines[#lines + 1] = "  runtime:_pop_script_ctx()"
    lines[#lines + 1] = "  if not __ok then"
    lines[#lines + 1] = "    if type(__err) == 'table' and __err.__ret then return __err.value end"
    lines[#lines + 1] = "    error(__err)"
    lines[#lines + 1] = "  end"
    lines[#lines + 1] = "end"
    return table.concat(lines, "\n")
end

local function emit_sequence(emitter, seq, state, indent, loop_stack, compile_ctx)
    local i = 1
    while i <= #seq do
        local node = seq[i]
        local cmd = node.cmd
        if cmd == "if" then
            emitter:emit(("%sif %s then"):format(indent, _compile_condition(node.arg.expr_ast, merged_ctx(compile_ctx, state, loop_stack))))
            i = i + 1
        elseif cmd == "elseif" then
            emitter:emit(("%selseif %s then"):format(indent, _compile_condition(node.arg.expr_ast, merged_ctx(compile_ctx, state, loop_stack))))
            i = i + 1
        elseif cmd == "else" then
            emitter:emit(indent .. "else")
            i = i + 1
        elseif cmd == "endif" then
            emitter:emit(indent .. "end")
            i = i + 1
        elseif cmd == "while" then
            local label = string.format("__cont_%d", node.line)
            loop_stack[#loop_stack + 1] = label
            emitter:emit(indent .. "while true do")
            emitter:emit(("%s  if not %s then break end"):format(indent, _compile_condition(node.arg.expr_ast, merged_ctx(compile_ctx, state, loop_stack))))
            emitter:emit(indent .. "  local __loop_ok, __loop_err = runtime:_pcall(function()")
            i = i + 1
        elseif cmd == "endwhile" then
            local label = loop_stack[#loop_stack]
            loop_stack[#loop_stack] = nil
            emitter:emit(indent .. "  end)")
            emit_loop_error_guard(emitter, indent .. "  ", "__loop_ok", "__loop_err", label)
            emitter:emit(indent .. "  ::" .. label .. "::")
            emitter:emit(indent .. "end")
            i = i + 1
        elseif cmd == "for" then
            local label = string.format("__cont_%d", node.line)
            loop_stack[#loop_stack + 1] = label
            emitter:emit(indent .. "do")
            emitter:emit(indent .. "  for _, __iter_v in ipairs(runtime:iter(" .. Compiler.compile_expr(node.arg.rhs_ast, merged_ctx(compile_ctx, state, loop_stack)) .. ")) do")
            emitter:emit(indent .. "    ; " .. emit_for_assignment(node, compile_ctx))
            emitter:emit(indent .. "    local __loop_ok, __loop_err = runtime:_pcall(function()")
            i = i + 1
        elseif cmd == "endfor" then
            local label = loop_stack[#loop_stack]
            loop_stack[#loop_stack] = nil
            emitter:emit(indent .. "    end)")
            emit_loop_error_guard(emitter, indent .. "    ", "__loop_ok", "__loop_err", label)
            emitter:emit(indent .. "    ::" .. label .. "::")
            emitter:emit(indent .. "  end")
            emitter:emit(indent .. "end")
            i = i + 1
        elseif cmd == "try" then
            local region = node.try_region
            emitter:emit(indent .. "do")
            emitter:emit(indent .. "  local __try_ok, __try_err = runtime:_pcall(function()")
            emit_sequence(emitter, region.try_body, state, indent .. "    ", loop_stack, compile_ctx)
            emitter:emit(indent .. "  end)")
            emitter:emit(indent .. "  if not __try_ok then")
            emitter:emit(indent .. "    if type(__try_err) == 'table' and (__try_err.__ret or __try_err.__break or __try_err.__continue) then error(__try_err) end")
            if #region.catches > 0 then
                for catch_idx = 1, #region.catches do
                    local catch = region.catches[catch_idx]
                    local prefix = (catch_idx == 1) and "if" or "elseif"
                    emitter:emit(indent .. "    " .. prefix .. " runtime:catch_matches(__try_err, " .. lua_string(catch.rest) .. ") then")
                    emit_sequence(emitter, catch.body, state, indent .. "      ", loop_stack, compile_ctx)
                end
                emitter:emit(indent .. "    else")
                emitter:emit(indent .. "      error(__try_err)")
                emitter:emit(indent .. "    end")
            else
                emitter:emit(indent .. "    error(__try_err)")
            end
            emitter:emit(indent .. "  end")
            if region.finally_body then
                emit_sequence(emitter, region.finally_body, state, indent .. "  ", loop_stack, compile_ctx)
            end
            emitter:emit(indent .. "end")
            i = find_matching_end(seq, i, "try", "endtry") + 1
        elseif cmd == "function" then
            local region = node.function_region
            local plist = {}
            for _, p in ipairs(node.func_params) do
                plist[#plist + 1] = lua_string(p)
            end
            emitter:emit(indent .. "do")
            emitter:emit(indent .. "  local __fn = function(runtime)")
            emitter:emit(indent .. "    local __state = runtime.state")
            emitter:emit(indent .. "    local __ops = runtime.ops")
            emitter:emit(indent .. "    local __scopes = runtime.scopes")
            emitter:emit(indent .. "    local __g = __state.g")
            emitter:emit(indent .. "    local __s = __state.s")
            emitter:emit(indent .. "    local __v = __state.v")
            emitter:emit(indent .. "    local __frame = __state.frames[#__state.frames]")
            local fn_ctx = {
                in_function = true,
                local_vars = node.local_vars,
            }
            if node.local_vars then
                local names = {}
                for name in pairs(node.local_vars) do names[#names + 1] = name end
                table.sort(names)
                if #names > 0 then
                    local decls = {}
                    for _, name in ipairs(names) do
                        decls[#decls + 1] = "__l_" .. name
                    end
                    emitter:emit(indent .. "    local " .. table.concat(decls, ", "))
                end
            end
            emit_sequence(emitter, region.body, state, indent .. "    ", {}, fn_ctx)
            emitter:emit(indent .. "  end")
            emitter:emit(("%s  runtime:register_function(%s, {%s}, __fn)"):format(indent, lua_string(node.func_name), table.concat(plist, ", ")))
            emitter:emit(indent .. "end")
            i = find_matching_end(seq, i, "function", "endfunction") + 1
        else
            emit_regular_node(emitter, node, state, loop_stack, indent, compile_ctx)
            i = i + 1
        end
    end
end

function Compiler.compile_script(script, opts)
    opts = opts or {}
    local ir, err = build_ir(script)
    if not ir then
        return nil, err
    end
    local ok
    ok, err = analyze_control_flow(ir)
    if err then
        return nil, err
    end
    ok, err = parse_command_payloads(ir)
    if err then
        return nil, err
    end
    local ok_annotate, annotate_err = pcall(annotate_function_locals, ir)
    if not ok_annotate then
        return nil, Error.IsError(annotate_err) and annotate_err or Error(0, tostring(annotate_err))
    end
    local emitter = new_script_emitter()
    local ok_emit, emit_err = pcall(emit_sequence, emitter, ir, opts.state, "    ", {}, {})
    if not ok_emit then
        return nil, Error.IsError(emit_err) and emit_err or Error(0, tostring(emit_err))
    end
    local source_map = {}
    return render_compiled_chunk(emitter), source_map
end

return Compiler
