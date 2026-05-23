-- vim.lib.excmd.compiler
local Compiler = {}

local Error = loadModule("lib.error")
local Commands = loadModule("lib.excmd.commands")

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
        local head = table.concat(buf)
        local i = #head
        while i > 0 do
            local ch = head:sub(i, i)
            if not ch:match("%s") then return ch end
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
                if c == ":" or c:match("%s") then
                    buf[#buf + 1] = c
                    if c ~= ":" then seg_leading = false end
                    i = i + 1; goto continue
                else
                    seg_leading = false
                end
            end
            if #cmd_buf == 0 then
                if c:match("%a") then
                    cmd_buf = c
                else
                    buf[#buf + 1] = c; i = i + 1; goto continue
                end
            else
                if c:match("[%w]") then
                    cmd_buf = cmd_buf .. c
                elseif c == "!" then
                    cmd_buf = cmd_buf .. c
                    local mode, no_bar = _cmd_mode_and_bar(cmd_buf)
                    seg_mode = mode
                    seg_no_bar = no_bar
                    seg_cmd_known = true
                elseif c:match("%s") then
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
        while i <= n and s:sub(i, i):match("%s") do i = i + 1 end
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
        if c:match("%d") then
            while i <= n and s:sub(i, i):match("%d") do i = i + 1 end
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

local function compile_invocation_spec(node)
    local cmd = node.cmd
    local rest = node.rest
    local lname = cmd:lower()
    local ws_args = split_ws_static(rest)
    local ws_items = {}
    for i = 1, #ws_args do
        ws_items[#ws_items + 1] = lua_string(ws_args[i])
    end

    local fields = {
        "name = " .. lua_string(cmd),
        "lname = " .. lua_string(lname),
        "qargs = " .. lua_string(rest),
        "bang = " .. (node.bang and "true" or "false"),
        "ws_args = { " .. table.concat(ws_items, ", ") .. " }",
    }

    local dispatch
    if lname ~= "" then
        if DISPATCH_MIN_ABBREV[lname] or MAP_COMMAND_SPECS[lname] then
            dispatch = lname
        else
            local resolved = resolve_dispatch_name(lname)
            if not Error.IsError(resolved) then
                dispatch = resolved
            end
        end
    end
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
local SCOPED_VAR_PATTERN = "^[gslavwb]:[A-Za-z_][A-Za-z0-9_]*$"
local OPTION_PATTERN = "^&([gl]):([A-Za-z_][A-Za-z0-9_]*)$"
local OPTION_AUTO_PATTERN = "^&([A-Za-z_][A-Za-z0-9_]*)$"

local function _is_number_literal(s)
    return s:match("^[+-]?%d+$") ~= nil or s:match("^[+-]?%d+%.%d+$") ~= nil
end

local function _is_string_literal(s)
    return s:match("^'.*'$") ~= nil or s:match('^".*"$') ~= nil
end

local function _find_top_level_binary(s, op)
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
                -- Treat angle tokens like <SID>, <SNR>, <cword> as atomic so
                -- comparison scanning doesn't split inside them.
                if ch == "<" then
                    local close = s:find(">", i + 1, true)
                    if close then
                        local inner = s:sub(i + 1, close - 1)
                        if inner:match("^[%w%-]+$") then
                            i = close + 1
                            goto continue
                        end
                    end
                end
                if s:sub(i, i + #op - 1) == op then
                    if op == ">" and i > 1 and s:sub(i - 1, i - 1) == "-" then
                        i = i + 1
                        goto continue
                    end
                    return i
                end
            end
        end
        i = i + 1
        ::continue::
    end
    return nil
end

local BANG_OPERATORS = {
    "||", "&&", "?",
    "==#", "==?", "!=#", "!=?", "<=#", ">=#", "<=?", ">=?",
    "<#", ">#", "<?", ">?",
    "=~#", "=~?", "!~#", "!~?",
    "==", "!=", ">=", "<=", "=~", "!~", ">", "<",
    "..", ".", "+", "-", "*", "/", "%", "->",
}

local function _has_top_level_operator(s)
    for i = 1, #BANG_OPERATORS do
        if _find_top_level_binary(s, BANG_OPERATORS[i]) then
            return true
        end
    end
    return false
end

local function _compile_simple_atom(expr)
    local s = trim(expr)
    if s == "" then
        return nil
    end
    if _is_number_literal(s) then
        return { code = s, kind = "number" }
    end
    if s == "[]" then
        return { code = "{}", kind = "table" }
    end
    if _is_string_literal(s) then
        return { code = string.format("runtime:eval_expr(%q)", s), kind = "string" }
    end
    local oscope, oname = s:match(OPTION_PATTERN)
    if oscope and oname then
        local mode = (oscope == "g") and "global" or "local"
        return { code = string.format("runtime:get_option(%q, %q)", oname, mode), kind = "unknown" }
    end
    local oauto = s:match(OPTION_AUTO_PATTERN)
    if oauto then
        return { code = string.format("runtime:get_option(%q, %q)", oauto, "auto"), kind = "unknown" }
    end
    if s:match(SCOPED_VAR_PATTERN) or s:match(SIMPLE_VAR_PATTERN) then
        return { code = string.format("runtime:get_var(%q)", s), kind = "unknown" }
    end
    return nil
end

local function _compile_expr_typed(expr, ctx)
    local s = trim(expr)
    local atom = _compile_simple_atom(s)
    if atom then return atom end

    local bang = s:match("^!%s*(.+)$")
    if bang and not _has_top_level_operator(bang) then
        local inner = _compile_expr_typed(bang, ctx)
        if inner.kind == "boolean" then
            return { code = "(not (" .. inner.code .. "))", kind = "boolean" }
        end
        return { code = "(not runtime:truthy(" .. inner.code .. "))", kind = "boolean" }
    end

    local or_pos = _find_top_level_binary(s, "||")
    if or_pos then
        return { code = string.format("runtime:eval_expr(%q)", s), kind = "unknown" }
    end
    local and_pos = _find_top_level_binary(s, "&&")
    if and_pos then
        return { code = string.format("runtime:eval_expr(%q)", s), kind = "unknown" }
    end
    local qmark_pos = _find_top_level_binary(s, "?")
    if qmark_pos then
        return { code = string.format("runtime:eval_expr(%q)", s), kind = "unknown" }
    end

    local cmp_ops = {
        { op = "==#", fast = false },
        { op = "==?", fast = false },
        { op = "!=#", fast = false },
        { op = "!=?", fast = false },
        { op = "<=#", fast = false },
        { op = ">=#", fast = false },
        { op = "<=?", fast = false },
        { op = ">=?", fast = false },
        { op = "<#", fast = false },
        { op = ">#", fast = false },
        { op = "<?", fast = false },
        { op = ">?", fast = false },
        { op = "=~#", fast = false },
        { op = "=~?", fast = false },
        { op = "!~#", fast = false },
        { op = "!~?", fast = false },
        { op = "==", fast = true },
        { op = "!=", fast = true },
        { op = ">=", fast = true },
        { op = "<=", fast = true },
        { op = ">", fast = true },
        { op = "<", fast = true },
        { op = "=~", fast = false },
        { op = "!~", fast = false },
    }
    for i = 1, #cmp_ops do
        local op = cmp_ops[i].op
        local pos = _find_top_level_binary(s, op)
        if pos then
            local lhs = trim(s:sub(1, pos - 1))
            local rhs = trim(s:sub(pos + #op))
            if lhs ~= "" and rhs ~= "" then
                if not cmp_ops[i].fast then
                    return { code = string.format("runtime:eval_expr(%q)", s), kind = "unknown" }
                end
                local lc = _compile_expr_typed(lhs, ctx)
                local rc = _compile_expr_typed(rhs, ctx)
                return { code = string.format("runtime:cmp(%s, %q, %s)", lc.code, op, rc.code), kind = "boolean" }
            end
        end
    end

    return { code = string.format("runtime:eval_expr(%q)", tostring(expr or "")), kind = "unknown" }
end

local function _compile_condition(expr, ctx)
    local c = _compile_expr_typed(expr, ctx)
    if c.kind == "boolean" then
        return c.code
    end
    return "runtime:truthy(" .. c.code .. ")"
end

function Compiler.compile_expr(expr, ctx)
    return _compile_expr_typed(expr, ctx).code
end

function Compiler.compile_command(node, ctx)
    local cmd = node.cmd
    local rest = node.rest
    ctx = ctx or {}

    if cmd == "let" then
        local lhs, op, rhs = rest:match("^(.-)%s*([%.%+%-%*%/%%]=)%s*(.+)$")
        if not lhs then
            lhs, rhs = rest:match("^(.-)=(.+)$")
            op = "="
        end
        if not lhs or not op then
            return { code = "error('Malformed :let')" }
        end
        lhs = trim(lhs)
        rhs = trim(rhs)
        if op == "=" then
            return {
                code = string.format("runtime:assign(%s, %s)", lua_string(lhs), Compiler.compile_expr(rhs, ctx)),
            }
        end

        if op ~= "+=" and op ~= "-=" and op ~= "*=" and op ~= "/=" and op ~= "%=" and op ~= ".=" then
            return { code = "error('Malformed :let')" }
        end
        return {
            code = string.format(
                "do local __rv=runtime:assign_compound(%s,%s,%s); if Error.IsError(__rv) then error(__rv) end end",
                lua_string(lhs),
                lua_string(op),
                Compiler.compile_expr(rhs, ctx)
            ),
        }
    elseif cmd == "unlet" then
        return {
            code = string.format("runtime:unlet(%s,%s)", lua_string(rest), node.bang and "true" or "false"),
        }
    elseif cmd == "break" then
        return { code = "error(runtime:break_exc())" }
    elseif cmd == "continue" then
        local tgt = ctx.loop_continue
        if not tgt then
            return { code = "error('continue outside loop')" }
        end
        return { code = "error(runtime:continue_exc())" }
    elseif cmd == "execute" then
        return { code = string.format("runtime:execute(%s)", lua_string(rest)) }
    elseif cmd == "verbose" then
        local level = tonumber(node.verbose_count) or 1
        return { code = string.format("runtime:exec_verbose(%d, %s)", level, lua_string(rest)) }
    elseif cmd == "call" then
        local fname, argstr = rest:match("^([^%s(]+)%s*%((.*)%)%s*$")
        if not fname then
            return { code = "error('Malformed :call')" }
        end
        argstr = argstr or ""
        local args = {}
        local parts = split_top_args(argstr)
        for i = 1, #parts do
            args[#args + 1] = Compiler.compile_expr(parts[i], ctx)
        end
        return {
            code = string.format("runtime:call_func(%s, { %s })", lua_string(fname), table.concat(args, ", ")),
        }
    elseif cmd == "return" then
        local val = (#rest > 0) and Compiler.compile_expr(rest, ctx) or "nil"
        return { code = string.format("error(runtime:return_exc(%s))", val) }
    elseif cmd == "finish" then
        return { code = "error(runtime:return_exc(nil))" }
    elseif cmd == "set" then
        return { code = string.format("runtime:set_options(%s, %s)", lua_string(rest), lua_string("both")) }
    elseif cmd == "setlocal" then
        return { code = string.format("runtime:set_options(%s, %s)", lua_string(rest), lua_string("local")) }
    elseif cmd == "autocmd" then
        return {
            code = string.format("runtime:define_autocmd(%s, %s)", lua_string(rest), node.bang and "true" or "false"),
        }
    elseif cmd == "doautoall" then
        return { code = string.format("runtime:doautoall(%s)", lua_string(rest)) }
    elseif cmd == "command" or cmd == "command!" then
        return {
            code = string.format("runtime:define_command(%s, %s)", lua_string(rest), node.bang and "true" or "false"),
        }
    else
        return { uses_dispatch = true }
    end
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

local function emit_regular_node(emitter, node, state, loop_stack, indent)
    local compiled = Compiler.compile_command(node, {
        state = state,
        loop_continue = loop_stack[#loop_stack],
    })
    local node_ref = emitter:intern_node(node, compiled.uses_dispatch == true)
    if compiled.uses_dispatch then
        emitter:emit(indent .. "runtime:invoke_precompiled_node(" .. node_ref .. ")")
        return
    end
    emitter:emit(indent .. "runtime:set_exec_cursor_from(" .. node_ref .. ")")
    emitter:emit(indent .. compiled.code)
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

local function emit_sequence(emitter, seq, state, indent, loop_stack)
    indent = indent or "  "
    loop_stack = loop_stack or {}
    local i = 1
    while i <= #seq do
        local node = seq[i]
        local cmd = node.cmd
        if cmd == "if" then
            emitter:emit(("%sif %s then"):format(indent, _compile_condition(node.rest, { state = state })))
            i = i + 1
        elseif cmd == "elseif" then
            emitter:emit(("%selseif %s then"):format(indent, _compile_condition(node.rest, { state = state })))
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
            emitter:emit(("%s  if not %s then break end"):format(indent, _compile_condition(node.rest, { state = state })))
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
            emitter:emit(indent .. "  for _, __v in ipairs(runtime:iter(" .. Compiler.compile_expr(node.iter_rhs, { state = state }) .. ")) do")
            emitter:emit(indent .. "    runtime:assign(" .. lua_string(node.iter_lhs) .. ", __v)")
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
            emit_sequence(emitter, region.try_body, state, indent .. "    ", loop_stack)
            emitter:emit(indent .. "  end)")
            emitter:emit(indent .. "  if not __try_ok then")
            emitter:emit(indent .. "    if type(__try_err) == 'table' and (__try_err.__ret or __try_err.__break or __try_err.__continue) then error(__try_err) end")
            if #region.catches > 0 then
                for catch_idx = 1, #region.catches do
                    local catch = region.catches[catch_idx]
                    local prefix = (catch_idx == 1) and "if" or "elseif"
                    emitter:emit(indent .. "    " .. prefix .. " runtime:catch_matches(__try_err, " .. lua_string(catch.rest) .. ") then")
                    emit_sequence(emitter, catch.body, state, indent .. "      ", loop_stack)
                end
                emitter:emit(indent .. "    else")
                emitter:emit(indent .. "      error(__try_err)")
                emitter:emit(indent .. "    end")
            else
                emitter:emit(indent .. "    error(__try_err)")
            end
            emitter:emit(indent .. "  end")
            if region.finally_body then
                emit_sequence(emitter, region.finally_body, state, indent .. "  ", loop_stack)
            end
            emitter:emit(indent .. "end")
            i = region.end_idx + 1
        elseif cmd == "function" then
            local region = node.function_region
            local plist = {}
            for _, p in ipairs(node.func_params) do
                plist[#plist + 1] = lua_string(p)
            end
            emitter:emit(indent .. "do")
            emitter:emit(indent .. "  local __fn = function(runtime)")
            emit_sequence(emitter, region.body, state, indent .. "    ", {})
            emitter:emit(indent .. "  end")
            emitter:emit(("%s  runtime:register_function(%s, {%s}, __fn)"):format(indent, lua_string(node.func_name), table.concat(plist, ", ")))
            emitter:emit(indent .. "end")
            i = region.end_idx + 1
        else
            emit_regular_node(emitter, node, state, loop_stack, indent)
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
    local emitter = new_script_emitter()
    emit_sequence(emitter, ir, opts.state, "    ", {})
    local source_map = {}
    return render_compiled_chunk(emitter), source_map
end

return Compiler
