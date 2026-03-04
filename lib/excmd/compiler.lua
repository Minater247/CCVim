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

local function parse_cmd_head(line)
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
    local cmd = tostring(node.cmd or "")
    local rest = tostring(node.rest or "")
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
            local rhs = "[" .. table.concat(items, ", ") .. "]"
            ir[#ir + 1] = {
                cmd = "let",
                rest = lhs .. " = " .. rhs,
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
    local cmd = node.cmd or ""
    local rest = node.rest or ""
    ctx = ctx or {}

    if cmd == "let" then
        local lhs, op, rhs = rest:match("^(.-)%s*([%.%+%-%*%/%%]=)%s*(.+)$")
        if not lhs then
            lhs, rhs = rest:match("^(.-)=(.+)$")
            op = "="
        end
        if not lhs or not op then
            return "error('Malformed :let')"
        end
        lhs = trim(lhs)
        rhs = trim(rhs)
        if op == "=" then
            return string.format("runtime:assign(%s, %s)", lua_string(lhs), Compiler.compile_expr(rhs, ctx))
        end

        if op ~= "+=" and op ~= "-=" and op ~= "*=" and op ~= "/=" and op ~= "%=" and op ~= ".=" then
            return "error('Malformed :let')"
        end
        return string.format(
            "do local __rv=runtime:assign_compound(%s,%s,%s); if Error.IsError(__rv) then error(__rv) end end",
            lua_string(lhs),
            lua_string(op),
            Compiler.compile_expr(rhs, ctx)
        )
    elseif cmd == "unlet" then
        return string.format("runtime:unlet(%s,%s)", lua_string(rest), node.bang and "true" or "false")
    elseif cmd == "break" then
        return "error(runtime:break_exc())"
    elseif cmd == "continue" then
        local tgt = ctx.loop_continue
        if not tgt then
            return "error('continue outside loop')"
        end
        return "error(runtime:continue_exc())"
    elseif cmd == "execute" then
        return string.format("runtime:execute(%s)", lua_string(rest))
    elseif cmd == "verbose" then
        local level = tonumber(node.verbose_count) or 1
        return string.format("runtime:exec_verbose(%d, %s)", level, lua_string(rest))
    elseif cmd == "call" then
        local fname, argstr = rest:match("^([^%s(]+)%s*%((.*)%)%s*$")
        if not fname then
            return "error('Malformed :call')"
        end
        argstr = argstr or ""
        local args = {}
        local parts = split_top_args(argstr)
        for i = 1, #parts do
            args[#args + 1] = Compiler.compile_expr(parts[i], ctx)
        end
        return string.format("runtime:call_func(%s, { %s })", lua_string(fname), table.concat(args, ", "))
    elseif cmd == "return" then
        local val = (#rest > 0) and Compiler.compile_expr(rest, ctx) or "nil"
        return string.format("error(runtime:return_exc(%s))", val)
    elseif cmd == "finish" then
        return "error(runtime:return_exc(nil))"
    elseif cmd == "set" then
        return string.format("runtime:set_options(%s, %s)", lua_string(rest), lua_string("both"))
    elseif cmd == "setlocal" then
        return string.format("runtime:set_options(%s, %s)", lua_string(rest), lua_string("local"))
    elseif cmd == "autocmd" then
        return string.format("runtime:define_autocmd(%s, %s)", lua_string(rest), node.bang and "true" or "false")
    elseif cmd == "doautoall" then
        return string.format("runtime:doautoall(%s)", lua_string(rest))
    elseif cmd == "command" or cmd == "command!" then
        return string.format("runtime:define_command(%s, %s)", lua_string(rest), node.bang and "true" or "false")
    else
        return string.format("runtime:invoke_compiled_command(%s)", compile_invocation_spec(node))
    end
end

function Compiler.compile_script(script, opts)
    opts = opts or {}
    local ir, err = build_ir(script)
    if not ir then
        return nil, err
    end

    local lua_lines = {}
    lua_lines[#lua_lines + 1] = "return function(state, runtime)"
    lua_lines[#lua_lines + 1] = "  if not runtime then error('runtime required') end"
    lua_lines[#lua_lines + 1] = "  runtime.state = state or runtime.state"
    lua_lines[#lua_lines + 1] = "  local Error = runtime.Error"
    lua_lines[#lua_lines + 1] = "  runtime:_push_script_ctx()"
    lua_lines[#lua_lines + 1] = "  local __ok, __err = runtime:_pcall(function()"

    local function emit_block(seq, indent, loop_stack)
        indent = indent or "  "
        loop_stack = loop_stack or {}
        local i = 1
        while i <= #seq do
            local node = seq[i]
            local c = node.cmd or ""
            if c == "if" then
                lua_lines[#lua_lines + 1] = ("%sif %s then"):format(
                    indent,
                    _compile_condition(node.rest or "", { state = opts.state })
                )
                i = i + 1
            elseif c == "elseif" then
                lua_lines[#lua_lines + 1] = ("%selseif %s then"):format(
                    indent,
                    _compile_condition(node.rest or "", { state = opts.state })
                )
                i = i + 1
            elseif c == "else" then
                lua_lines[#lua_lines + 1] = indent .. "else"
                i = i + 1
            elseif c == "endif" then
                lua_lines[#lua_lines + 1] = indent .. "end"
                i = i + 1
            elseif c == "while" then
                local lbl = string.format("__cont_%d", node.line or #lua_lines)
                loop_stack[#loop_stack + 1] = lbl
                lua_lines[#lua_lines + 1] = indent .. "while true do"
                lua_lines[#lua_lines + 1] = ("%s  if not %s then break end"):format(
                    indent,
                    _compile_condition(node.rest or "", { state = opts.state })
                )
                lua_lines[#lua_lines + 1] = indent .. "  local __loop_ok, __loop_err = runtime:_pcall(function()"
                i = i + 1
            elseif c == "endwhile" then
                local lbl = loop_stack[#loop_stack]
                loop_stack[#loop_stack] = nil
                lua_lines[#lua_lines + 1] = indent .. "  end)"
                lua_lines[#lua_lines + 1] = indent .. "  if not __loop_ok then"
                lua_lines[#lua_lines + 1] = indent .. "    if type(__loop_err) == 'table' and __loop_err.__continue then goto " .. (lbl or "__cont") .. " end"
                lua_lines[#lua_lines + 1] = indent .. "    if type(__loop_err) == 'table' and __loop_err.__break then break end"
                lua_lines[#lua_lines + 1] = indent .. "    if type(__loop_err) == 'table' and __loop_err.__ret then error(__loop_err) end"
                lua_lines[#lua_lines + 1] = indent .. "    error(__loop_err)"
                lua_lines[#lua_lines + 1] = indent .. "  end"
                lua_lines[#lua_lines + 1] = indent .. "  ::" .. (lbl or "__cont") .. "::"
                lua_lines[#lua_lines + 1] = indent .. "end"
                i = i + 1
            elseif c == "for" then
                local lhs, rhs = (node.rest or ""):match("^(.-)%s+in%s+(.+)$")
                if not lhs then
                    lua_lines[#lua_lines + 1] = indent .. "error('Malformed :for')"
                else
                    local lbl = string.format("__cont_%d", node.line or #lua_lines)
                    loop_stack[#loop_stack + 1] = lbl
                    lua_lines[#lua_lines + 1] = indent .. "do"
                    lua_lines[#lua_lines + 1] = indent .. "  for _, __v in ipairs(runtime:iter(" .. Compiler.compile_expr(rhs or "", { state = opts.state }) .. ")) do"
                    lua_lines[#lua_lines + 1] = indent .. "    runtime:assign(" .. lua_string(lhs) .. ", __v)"
                    lua_lines[#lua_lines + 1] = indent .. "    local __loop_ok, __loop_err = runtime:_pcall(function()"
                end
                i = i + 1
            elseif c == "endfor" then
                local lbl = loop_stack[#loop_stack]
                loop_stack[#loop_stack] = nil
                lua_lines[#lua_lines + 1] = indent .. "    end)"
                lua_lines[#lua_lines + 1] = indent .. "    if not __loop_ok then"
                lua_lines[#lua_lines + 1] = indent .. "      if type(__loop_err) == 'table' and __loop_err.__continue then goto " .. (lbl or "__cont") .. " end"
                lua_lines[#lua_lines + 1] = indent .. "      if type(__loop_err) == 'table' and __loop_err.__break then break end"
                lua_lines[#lua_lines + 1] = indent .. "      if type(__loop_err) == 'table' and __loop_err.__ret then error(__loop_err) end"
                lua_lines[#lua_lines + 1] = indent .. "      error(__loop_err)"
                lua_lines[#lua_lines + 1] = indent .. "    end"
                lua_lines[#lua_lines + 1] = indent .. "    ::" .. (lbl or "__cont") .. "::"
                lua_lines[#lua_lines + 1] = indent .. "  end"
                lua_lines[#lua_lines + 1] = indent .. "end"
                i = i + 1
            elseif c == "try" then
                local depth = 1
                local j = i + 1
                local end_idx = nil
                local marks = {}
                while j <= #seq do
                    local inner = seq[j].cmd
                    if inner == "try" then
                        depth = depth + 1
                    elseif inner == "endtry" then
                        depth = depth - 1
                        if depth == 0 then
                            end_idx = j
                            break
                        end
                    elseif depth == 1 and (inner == "catch" or inner == "finally") then
                        marks[#marks + 1] = { idx = j, kind = inner, rest = seq[j].rest or "" }
                    end
                    j = j + 1
                end

                if not end_idx then
                    lua_lines[#lua_lines + 1] = indent .. "error('Malformed :try')"
                    i = i + 1
                else
                    local try_body_start = i + 1
                    local try_body_end = end_idx - 1
                    if #marks > 0 then
                        try_body_end = marks[1].idx - 1
                    end

                    local try_body_ir = {}
                    for k = try_body_start, try_body_end do
                        try_body_ir[#try_body_ir + 1] = seq[k]
                    end

                    local catches = {}
                    local finally_body_ir = nil
                    for mi = 1, #marks do
                        local m = marks[mi]
                        local next_idx = (mi < #marks) and marks[mi + 1].idx or end_idx
                        local body_start = m.idx + 1
                        local body_end = next_idx - 1
                        local body_ir = {}
                        for k = body_start, body_end do
                            body_ir[#body_ir + 1] = seq[k]
                        end
                        if m.kind == "catch" then
                            catches[#catches + 1] = { rest = m.rest, body = body_ir }
                        elseif m.kind == "finally" then
                            finally_body_ir = body_ir
                        end
                    end

                    lua_lines[#lua_lines + 1] = indent .. "do"
                    lua_lines[#lua_lines + 1] = indent .. "  local __try_ok, __try_err = runtime:_pcall(function()"
                    emit_block(try_body_ir, indent .. "    ", loop_stack)
                    lua_lines[#lua_lines + 1] = indent .. "  end)"
                    lua_lines[#lua_lines + 1] = indent .. "  if not __try_ok then"
                    lua_lines[#lua_lines + 1] = indent .. "    if type(__try_err) == 'table' and (__try_err.__ret or __try_err.__break or __try_err.__continue) then error(__try_err) end"
                    if #catches > 0 then
                        for ci = 1, #catches do
                            local cat = catches[ci]
                            local kw = (ci == 1) and "if" or "elseif"
                            lua_lines[#lua_lines + 1] = indent .. "    " .. kw .. " runtime:catch_matches(__try_err, " .. lua_string(cat.rest or "") .. ") then"
                            emit_block(cat.body or {}, indent .. "      ", loop_stack)
                        end
                        lua_lines[#lua_lines + 1] = indent .. "    else"
                        lua_lines[#lua_lines + 1] = indent .. "      error(__try_err)"
                        lua_lines[#lua_lines + 1] = indent .. "    end"
                    else
                        lua_lines[#lua_lines + 1] = indent .. "    error(__try_err)"
                    end
                    lua_lines[#lua_lines + 1] = indent .. "  end"
                    if finally_body_ir then
                        emit_block(finally_body_ir, indent .. "  ", loop_stack)
                    end
                    lua_lines[#lua_lines + 1] = indent .. "end"
                    i = end_idx + 1
                end
            elseif c == "function" then
                local fname, params = parse_function_head(node.rest or "")
                if not fname then
                    lua_lines[#lua_lines + 1] = indent .. "error('Malformed :function')"
                    i = i + 1
                else
                    local depth = 1
                    local j = i + 1
                    while j <= #seq and depth > 0 do
                        local inner = seq[j].cmd
                        if inner == "function" then depth = depth + 1 end
                        if inner == "endfunction" then depth = depth - 1 end
                        j = j + 1
                    end
                    local end_idx = j - 1
                    local body_ir = {}
                    for k = i + 1, end_idx - 1 do
                        body_ir[#body_ir + 1] = seq[k]
                    end
                    local plist_raw = split_params(params)
                    local plist = {}
                    for _, p in ipairs(plist_raw) do
                        plist[#plist + 1] = lua_string(p)
                    end
                        lua_lines[#lua_lines + 1] = indent .. "do"
                        lua_lines[#lua_lines + 1] = indent .. "  local __fn = function(runtime)"
                        emit_block(body_ir, indent .. "    ")
                        lua_lines[#lua_lines + 1] = indent .. "  end"
                        lua_lines[#lua_lines + 1] = ("%s  runtime:register_function(%s, {%s}, __fn)"):format(
                            indent,
                            lua_string(fname),
                            table.concat(plist, ", ")
                        )
                        lua_lines[#lua_lines + 1] = indent .. "end"
                    i = end_idx + 1
                end
            elseif c == "endfunction" then
                i = i + 1
            elseif c == "catch" or c == "finally" or c == "endtry" then
                i = i + 1
            else
                lua_lines[#lua_lines + 1] = indent
                    .. "runtime:set_exec_cursor("
                    .. tostring(node.line or "nil")
                    .. ", "
                    .. lua_string(node.text or "")
                    .. ", "
                    .. lua_string(node.cmd or "")
                    .. ", "
                    .. lua_string(node.rest or "")
                    .. ")"
                lua_lines[#lua_lines + 1] = ("%s%s"):format(
                    indent,
                    Compiler.compile_command(node, { state = opts.state, loop_continue = loop_stack[#loop_stack] })
                )
                i = i + 1
            end
        end
    end

    emit_block(ir, "    ")
    lua_lines[#lua_lines + 1] = "  end)"
    lua_lines[#lua_lines + 1] = "  runtime:_pop_script_ctx()"
    lua_lines[#lua_lines + 1] = "  if not __ok then"
    lua_lines[#lua_lines + 1] = "    if type(__err) == 'table' and __err.__ret then return __err.value end"
    lua_lines[#lua_lines + 1] = "    error(__err)"
    lua_lines[#lua_lines + 1] = "  end"
    lua_lines[#lua_lines + 1] = "end"

    local source_map = {}
    return table.concat(lua_lines, "\n"), source_map
end

return Compiler
