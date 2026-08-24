-- Shared parsing for Ex command payloads.
local Payload = {}

local Error = loadModule("lib.error")
local VimExpr = loadModule("lib.excmd.vimxpr")

local function is_space_byte(byte)
    return byte == 32 or byte == 9 or byte == 10 or byte == 13 or byte == 12 or byte == 11
end

function Payload.trim(value)
    local s = tostring(value or "")
    local first, last = 1, #s
    while first <= last and is_space_byte(s:byte(first)) do
        first = first + 1
    end
    while last >= first and is_space_byte(s:byte(last)) do
        last = last - 1
    end
    if first == 1 and last == #s then
        return s
    end
    return s:sub(first, last)
end

function Payload.lstrip(value)
    local s = tostring(value or "")
    local first = 1
    while first <= #s and is_space_byte(s:byte(first)) do
        first = first + 1
    end
    if first == 1 then
        return s
    end
    return s:sub(first)
end

function Payload.split_words(value)
    local out = {}
    local buf = {}
    local s = tostring(value or "")
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

function Payload.split_set_args(value)
    local s = tostring(value or "")
    if s == "" then return {} end

    local out, buf = {}, {}
    local i, n = 1, #s
    while i <= n do
        local byte = s:byte(i)
        if byte == 92 and i < n then
            buf[#buf + 1] = s:sub(i, i + 1)
            i = i + 2
        elseif byte == 34 then
            local prev = i > 1 and s:byte(i - 1)
            if i == 1 or prev == 32 or prev == 9 then
                break
            end
            buf[#buf + 1] = '"'
            i = i + 1
        elseif byte == 32 or byte == 9 then
            if #buf ~= 0 then
                out[#out + 1] = table.concat(buf)
                buf = {}
            end
            repeat
                i = i + 1
                byte = s:byte(i)
            until i > n or (byte ~= 32 and byte ~= 9)
        else
            buf[#buf + 1] = s:sub(i, i)
            i = i + 1
        end
    end
    if #buf ~= 0 then
        out[#out + 1] = table.concat(buf)
    end
    return out
end

function Payload.rejoin_option_assignments(args)
    local out, i = {}, 1
    while i <= #args do
        local token = args[i]
        local next_token = args[i + 1]
        local value = args[i + 2]
        if token:match("^[%a_]%w*$") and next_token then
            if next_token:match("^[:=]") then
                out[#out + 1] = token .. "=" .. next_token:sub(2)
                i = i + 2
                goto continue
            elseif next_token == "=" and value then
                out[#out + 1] = token .. "=" .. value
                i = i + 3
                goto continue
            elseif next_token:match("^[+%^%-]=") then
                out[#out + 1] = token .. next_token
                i = i + 2
                goto continue
            end
        end
        out[#out + 1] = token
        i = i + 1
        ::continue::
    end
    return out
end

function Payload.strip_trailing_comment(value)
    local s = tostring(value or "")
    if not s:find('"', 1, true) then
        return Payload.trim(s)
    end
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local byte = s:byte(i)
        if byte == 92 and i < n then
            out[#out + 1] = s:sub(i, i + 1)
            i = i + 2
        elseif byte == 34 then
            break
        else
            out[#out + 1] = s:sub(i, i)
            i = i + 1
        end
    end
    return Payload.trim(table.concat(out))
end

local COMMAND_ARG_PARSERS = {
    highlight = function(value)
        return Payload.split_words(Payload.strip_trailing_comment(value))
    end,
}
Payload.command_arg_parsers = COMMAND_ARG_PARSERS

function Payload.command_args(command, value)
    local parser = COMMAND_ARG_PARSERS[command] or Payload.split_words
    return parser(value)
end

function Payload.split_let_assignment(value)
    local s = tostring(value or "")
    local in_single, in_double, escaped = false, false, false
    local paren_depth, curly_depth, bracket_depth = 0, 0, 0
    local i, n = 1, #s

    while i <= n do
        local ch = s:sub(i, i)
        if escaped then
            escaped = false
        elseif ch == "\\" then
            if not in_single then escaped = true end
        elseif not in_double and ch == "'" then
            in_single = not in_single
        elseif not in_single and ch == '"' then
            in_double = not in_double
        elseif not in_single and not in_double then
            if ch == "(" then paren_depth = paren_depth + 1
            elseif ch == ")" then paren_depth = math.max(0, paren_depth - 1)
            elseif ch == "{" then curly_depth = curly_depth + 1
            elseif ch == "}" then curly_depth = math.max(0, curly_depth - 1)
            elseif ch == "[" then bracket_depth = bracket_depth + 1
            elseif ch == "]" then bracket_depth = math.max(0, bracket_depth - 1)
            elseif paren_depth == 0 and curly_depth == 0 and bracket_depth == 0 then
                local op = s:sub(i, i + 1)
                if op == "+=" or op == "-=" or op == "*=" or op == "/=" or op == "%=" or op == ".=" then
                    return Payload.trim(s:sub(1, i - 1)), op, Payload.trim(s:sub(i + 2))
                elseif ch == "=" then
                    return Payload.trim(s:sub(1, i - 1)), "=", Payload.trim(s:sub(i + 1))
                end
            end
        end
        i = i + 1
    end
    return nil
end

function Payload.parse_command_definition(value)
    local parts = Payload.split_words(value)
    local nargs, name = 0, nil
    local body_index = #parts + 1
    local i = 1
    while i <= #parts do
        local token = parts[i]
        if token:match("^%-nargs=") then
            local raw_nargs = token:sub(8)
            nargs = (raw_nargs == "*" or raw_nargs == "?" or raw_nargs == "+")
                and raw_nargs or tonumber(raw_nargs) or 0
        elseif token:sub(1, 1) ~= "-" then
            name = token
            body_index = i + 1
            break
        end
        i = i + 1
    end
    return {
        kind = "command",
        parts = parts,
        nargs = nargs,
        name = name,
        body_index = body_index,
    }
end

local function parse_expr(target, field, expression)
    if expression == nil or expression == "" then
        return true
    end
    local ast, parse_err = VimExpr.parse(expression)
    if not ast then
        return nil, Error(474, "Unsupported expression: " .. tostring(expression) .. " (" .. tostring(parse_err) .. ")")
    end
    target[field] = ast
    return true
end

function Payload.parse_sequence(sequence)
    local split_let_assignment = Payload.split_let_assignment
    local split_words = Payload.split_words
    local split_set_args = Payload.split_set_args
    local rejoin_option_assignments = Payload.rejoin_option_assignments
    local trim = Payload.trim

    for index = 1, #sequence do
        local node = sequence[index]
        local cmd = node.cmd
        if cmd == "let" or cmd == "const" then
        local lhs, op, rhs = split_let_assignment(node.rest)
        if not lhs then
            node.arg = { kind = "let_query" }
        else
            node.arg = { kind = "let", lhs = lhs, op = op, rhs = rhs }
            local ok, err = parse_expr(node.arg, "rhs_ast", rhs)
            if not ok then return nil, err end
        end
        elseif cmd == "if" or cmd == "elseif" or cmd == "while"
            or cmd == "call" or cmd == "throw" or (cmd == "return" and node.rest ~= "")
        then
            node.arg = { kind = "expr", expr = node.rest }
            local ok, err = parse_expr(node.arg, "expr_ast", node.rest)
            if not ok then return nil, err end
        elseif cmd == "for" then
            node.arg = { kind = "for", lhs = node.iter_lhs, rhs = node.iter_rhs }
            local ok, err = parse_expr(node.arg, "rhs_ast", node.iter_rhs)
            if not ok then return nil, err end
        elseif cmd == "echo" or cmd == "echoerr" or cmd == "echomsg" or cmd == "echon" then
        local exprs = VimExpr.splitExpressionAsts(node.rest)
        for i = 1, #exprs do
            if not exprs[i].ast then
                return nil, Error(474, "Unsupported expression: " .. tostring(exprs[i].text))
            end
        end
        node.arg = { kind = "expr_list", exprs = exprs }
        elseif cmd == "unlet" then
            node.arg = { kind = "unlet", names = split_words(node.rest) }
        elseif cmd == "set" or cmd == "setglobal" or cmd == "setlocal" then
            node.arg = {
                kind = "set",
                tokens = rejoin_option_assignments(split_set_args(node.rest)),
            }
        elseif cmd == "execute" then
        local exprs = VimExpr.splitExpressionAsts(node.rest)
        node.arg = {
            kind = "execute",
            exprs = exprs,
            dynamic = #exprs == 0 or node.rest:find("$'", 1, true) ~= nil,
        }
        for i = 1, #exprs do
            if not exprs[i].ast then
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
            node.arg = { kind = "put", source = expr == "" and "expr_reuse" or "expr", expr = expr }
            if expr ~= "" then
                local ok, err = parse_expr(node.arg, "expr_ast", expr)
                if not ok then return nil, err end
            end
        elseif #raw == 1 then
            node.arg = { kind = "put", source = "register", reg = raw }
        else
            node.arg = { kind = "put", source = "invalid", raw = raw }
        end
        elseif cmd == "autocmd" then
            node.arg = { kind = "autocmd", args = split_words(node.rest) }
        elseif cmd == "command" then
            node.arg = Payload.parse_command_definition(node.rest)
        elseif cmd == "doautoall" then
            node.arg = { kind = "doautoall", event = split_words(node.rest)[1] }
        end
    end
    return true
end

return Payload
