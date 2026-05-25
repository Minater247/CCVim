-- Supports environment variables: $VAR and ${VAR} -> strings via vim.lib.envvars.

local M             = {}

local Error         = loadModule("lib.error")
local VimRegex      = loadModule("lib.excmd.vim_regex")
local EnvVars       = loadModule("lib.envvars")
local Scopes        = loadModule("lib.luaapi.scopes")
local Key           = loadModule("lib.key")
local VimFnBuiltins = loadModule("lib.luaapi.fn")
local ApiBuild = loadModule("lib.luaapi.apibuild")
-- =========================================================

-- -------- helpers --------
local function is_error(x)
    return Error.IsError(x)
end
local function as_bool_legacy(v)
    -- For logical ops in legacy Vim: numbers are used (0 false, non-zero true).
    local t = type(v)
    if t == "boolean" then return v end
    if t == "number" then return v ~= 0 end
    if t == "string" then
        local s = v:match("^%s*([%+%-]?%d+%.?%d*)")
        local n = s and tonumber(s) or 0
        return n ~= 0
    end
    return false
end

local VIMXPR_LIST_MT = { __vimxpr_kind = "list" }
local VIMXPR_DICT_MT = { __vimxpr_kind = "dict" }

local function mark_list(tbl)
    return setmetatable(tbl, VIMXPR_LIST_MT)
end

local function mark_dict(tbl)
    return setmetatable(tbl, VIMXPR_DICT_MT)
end

local function table_kind(v)
    if type(v) ~= "table" then
        return nil
    end

    local mt = getmetatable(v)
    if mt and (mt.__vimxpr_kind == "list" or mt.__vimxpr_kind == "dict") then
        return mt.__vimxpr_kind
    end

    local maxk = 0
    local count = 0
    for k, _ in pairs(v) do
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

local function numeric_coercion_error(v)
    local t = type(v)
    if t == "function" then
        return Error(703)
    end
    if t == "table" then
        if table_kind(v) == "list" then
            return Error(745)
        end
        return Error(728)
    end
    return Error(0, "Invalid numeric coercion! Type=" .. type(v))
end
local function num_coerce(v)
    if type(v) == "number" then return v end
    if type(v) == "boolean" then return v and 1 or 0 end
    if type(v) == "string" then
        local s = v:match("^%s*([%+%-]?%d+%.?%d*)")
        return s and (s:find("%.") and tonumber(s) or tonumber(s)) or 0
    end
    return nil
end
local function num_coerce_or_error(v)
    local n = num_coerce(v)
    if n ~= nil then
        return n
    end
    return nil, numeric_coercion_error(v)
end
local function to_string_simple(v)
    local t = type(v)
    if t == "nil" then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    return tostring(v)
end

local function short_expr(s, maxlen)
    local text = tostring(s or "")
    text = text:gsub("[\r\n\t]", " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    local lim = maxlen or 120
    if #text <= lim then
        return text
    end
    return text:sub(1, lim - 3) .. "..."
end

local function decode_angle_escape(content)
    local c = tostring(content or "")
    if c == "" then
        return nil
    end

    local hex = c:match("^Char%-0[xX]([0-9A-Fa-f]+)$")
    if hex then
        local n = tonumber(hex, 16)
        if n then
            if utf8 and utf8.char then
                local ok, ch = pcall(utf8.char, n)
                if ok then
                    return ch
                end
            end
            if n >= 0 and n <= 255 then
                return string.char(n)
            end
        end
    end

    local dec = c:match("^Char%-(%d+)$")
    if dec then
        local n = tonumber(dec)
        if n then
            if utf8 and utf8.char then
                local ok, ch = pcall(utf8.char, n)
                if ok then
                    return ch
                end
            end
            if n >= 0 and n <= 255 then
                return string.char(n)
            end
        end
    end

    return Key.decode_angle_escape(c)
end

local function resolve_vlua_path(path)
    if type(path) ~= "string" or path == "" then
        return Error(117, "v:lua")
    end
    local segs = {}
    for seg in path:gmatch("[^%.]+") do segs[#segs + 1] = seg end
    local function is_valid_seg(seg)
        return seg:match("^[A-Za-z0-9_]+$") ~= nil
    end
    for i = 1, #segs do
        if not is_valid_seg(segs[i]) then
            return Error(117, "v:lua." .. tostring(path))
        end
    end
    local function traverse(root)
        local cur = root
        for _, s in ipairs(segs) do
            if type(cur) ~= "table" then return nil end
            cur = cur[s]
        end
        return cur
    end
    local api = ApiBuild.Build()
    local f = api and traverse(api)
    if type(f) ~= "function" then return Error(117, "v:lua." .. path) end
    return f
end

-- -------- tokenizer --------
local function tokenize(input)
    local i, n, toks = 1, #input, {}
    local function peek(k)
        k = k or 0; local j = i + k; return j <= n and input:sub(j, j) or ""
    end
    local function adv(k) i = i + (k or 1) end
    local function add(typ, val, pos, raw) toks[#toks + 1] = { typ = typ, val = val, pos = pos, raw = raw } end
    local function consume(pred)
        local j = i
        while j <= n and pred(input:sub(j, j)) do j = j + 1 end
        local out = input:sub(i, j - 1); i = j; return out
    end
    local function consume_sid_identifier()
        local start_i = i
        local head = input:sub(i, i + 4)
        local head_l = head:lower()

        if head_l == "<sid>" then
            i = i + 5
            local tail = consume(function(ch) return ch:match("[%w_#]") end)
            if tail ~= "" then
                return "<SID>" .. tail
            end
            i = start_i
            return nil
        end

        if head_l == "<snr>" then
            i = i + 5
            local digits = consume(function(ch) return ch:match("%d") end)
            if digits ~= "" and peek() == "_" then
                adv(1)
                local tail = consume(function(ch) return ch:match("[%w_#]") end)
                if tail ~= "" then
                    return "<SNR>" .. digits .. "_" .. tail
                end
            end
            i = start_i
            return nil
        end

        return nil
    end
    while i <= n do
        local c = peek()
        if c:match("%s") then
            adv(1)
            goto cont
        end
        local start = i

        -- number: int or simple float
        if c:match("%d") then
            local num = consume(function(ch) return ch:match("%d") end)
            if peek() == "." and peek(1):match("%d") then
                num = num .. consume(function(ch) return ch == "." or ch:match("%d") end)
            end
            add("NUM", tonumber(num), start, num); goto cont
        end

        -- string (single or double quoted)
        if c == "'" then
            adv(1)
            local buf = {}
            while i <= n do
                local ch = peek(); adv(1)
                if ch == "'" then
                    -- Vimscript single-quote escaping: '' -> literal '
                    if peek() == "'" then
                        buf[#buf + 1] = "'"
                        adv(1)
                    else
                        break
                    end
                elseif ch == "\\" and peek() == '"' then
                    -- In Vimscript single-quoted strings, \" yields a literal ".
                    buf[#buf + 1] = '"'
                    adv(1)
                else
                    buf[#buf + 1] = ch
                end
            end
            add("STR", table.concat(buf), start); goto cont
        end
        if c == '"' then
            adv(1)
            local buf, esc = {}, false
            while i <= n do
                local ch = peek(); adv(1)
                if esc then
                    local decoded = ({
                        n = "\n",
                        r = "\r",
                        t = "\t",
                        b = "\b",
                        e = string.char(27),
                        f = string.char(12),
                        ['\\'] = "\\",
                        ['"'] = '"',
                    })[ch]
                    if decoded == nil and ch == "<" then
                        local j = i
                        while j <= n and input:sub(j, j) ~= ">" do
                            j = j + 1
                        end
                        if j <= n then
                            local angle_content = input:sub(i, j - 1)
                            decoded = decode_angle_escape(angle_content)
                            if decoded == nil then
                                decoded = "<" .. angle_content .. ">"
                            end
                            i = j + 1
                        end
                    end
                    if decoded ~= nil then
                        buf[#buf + 1] = decoded
                    else
                        -- Keep unknown escapes literal (\X) so patterns like "\*$"
                        -- preserve the backslash as documented by :help expr-quote.
                        buf[#buf + 1] = "\\" .. ch
                    end
                    esc = false
                elseif ch == "\\" then
                    esc = true
                elseif ch == '"' then
                    break
                else
                    buf[#buf + 1] = ch
                end
            end
            if esc then
                -- Trailing backslash in a double-quoted string is literal.
                buf[#buf + 1] = "\\"
            end
            add("STR", table.concat(buf), start); goto cont
        end

        -- environment variable: $NAME or ${NAME}
        if c == "$" and peek(1) == "'" then
            -- $'...' single-quoted string.
            -- Parse as one string token so splitExpressions() can segment
            -- execute arguments without being confused by interpolation text.
            adv(2) -- skip $'
            local buf = {}
            while i <= n do
                local ch = peek(); adv(1)
                if ch == "'" then
                    if peek() == "'" then
                        buf[#buf + 1] = "'"
                        adv(1)
                    else
                        break
                    end
                else
                    buf[#buf + 1] = ch
                end
            end
            add("STR", table.concat(buf), start); goto cont
        end
        if c == "$" then
            adv(1)
            local name
            if peek() == "{" then
                adv(1) -- skip '{'
                local j = i
                while j <= n and input:sub(j, j):match("[%w_]") do j = j + 1 end
                name = input:sub(i, j - 1)
                i = j
                if peek() ~= "}" then
                    error(("Unterminated ${ at %d"):format(start))
                end
                adv(1) -- skip '}'
            else
                if not peek():match("[%a_]") then
                    error(("Invalid env var name at %d: %s"):format(start, input:sub(i)))
                end
                local ident = consume(function(ch) return ch:match("[%w_]") end)
                name = ident
            end
            add("ENV", name, start); goto cont
        end

        -- register: @x or @@
        if c == "@" then
            adv(1)
            local nxt = peek()
            if nxt == "" then
                error(("Missing register name at %d"):format(start))
            end
            if nxt == "@" then
                adv(1)
                add("REG", "@", start); goto cont
            end
            if nxt == "{" then
                -- minimal support for @{name}; read until }
                adv(1) -- skip '{'
                local j = i
                while j <= n and input:sub(j, j) ~= "}" do j = j + 1 end
                if j > n then
                    error(("Unterminated @{ at %d"):format(start))
                end
                local name = input:sub(i, j - 1)
                i = j + 1
                add("REG", name, start); goto cont
            end
            -- single-character register name
            local reg = nxt
            adv(1)
            add("REG", reg, start); goto cont
        end

        -- multi-char operators (longest first)
        local multi = {
            "==#",
            "==?",
            "!=#",
            "!=?",
            ">=",
            "<=",
            "=~#",
            "=~?",
            "!~#",
            "!~?",
            "==",
            "!=",
            "=~",
            "!~",
            "&&",
            "||",
            "<<",
            ">>",
            "->",
            ".."
        }
        local matched = false
        for _, op in ipairs(multi) do
            if input:sub(i, i + #op - 1) == op then
                add("OP", op, start); adv(#op); matched = true; break
            end
        end
        if matched then goto cont end

        local word_ops = {
            "isnot#",
            "isnot?",
            "isnot",
            "is#",
            "is?",
            "is",
        }
        for _, op in ipairs(word_ops) do
            if input:sub(i, i + #op - 1) == op then
                local nxt = input:sub(i + #op, i + #op)
                if nxt == "" or not nxt:match("[%w_#?]") then
                    add("OP", op, start); adv(#op); matched = true; break
                end
            end
        end
        if matched then goto cont end

        -- script-local function names in expression context: <SID>Foo(), <SNR>12_Foo()
        if c == "<" then
            local sid_ident = consume_sid_identifier()
            if sid_ident then
                add("ID", sid_ident, start); goto cont
            end
        end

        -- single-char tokens
        if c == "#" and peek(1) == "{" then
            -- Vim literal dictionary syntax: #{ key: value }.
            -- Treat this as a dict-opening brace for parser compatibility.
            add("LBRACE", "{", start); adv(2); goto cont
        end
        if c == "(" then
            add("LPAREN", "(", start); adv(1); goto cont
        end
        if c == ")" then
            add("RPAREN", ")", start); adv(1); goto cont
        end
        if c == "{" then
            add("LBRACE", "{", start); adv(1); goto cont
        end
        if c == "}" then
            add("RBRACE", "}", start); adv(1); goto cont
        end
        if c == "[" then
            add("LBRACK", "[", start); adv(1); goto cont
        end
        if c == "]" then
            add("RBRACK", "]", start); adv(1); goto cont
        end
        if c == "&" then
            add("AMP", "&", start); adv(1); goto cont
        end
        if c == ":" then
            add("COLON", ":", start); adv(1); goto cont
        end
        if c:match("[%+%-%*/%%<>%.%!%?,]") then
            add("OP", c, start); adv(1); goto cont
        end

        -- identifiers
        if c:match("[%a_]") then
            local ident = consume(function(ch) return ch:match("[%w_#]") end)
            add("ID", ident, start); goto cont
        end

        error(("Unexpected char %q at %d (expr=%q, tail=%q)"):format(c, i, short_expr(input, 120),
            short_expr(input:sub(i), 80)))

        ::cont::
    end
    add("EOF", nil, n + 1)
    return toks
end

-- -------- parser (Pratt) to AST --------
local PREC = {
    ["||"] = 0,
    ["&&"] = 1,
    -- comparisons (with #/? variants)
    ["=="] = 2,
    ["!="] = 2,
    ["<"] = 2,
    ["<="] = 2,
    [">"] = 2,
    [">="] = 2,
    ["==#"] = 2,
    ["!=#"] = 2,
    ["<#"] = 2,
    ["<=#"] = 2,
    [">#"] = 2,
    [">=#"] = 2,
    ["==?"] = 2,
    ["!=?"] = 2,
    ["<?"] = 2,
    ["<=?"] = 2,
    [">?"] = 2,
    [">=?"] = 2,
    ["=~"] = 2,
    ["!~"] = 2,
    ["=~#"] = 2,
    ["!~#"] = 2,
    ["=~?"] = 2,
    ["!~?"] = 2,
    ["is"] = 2,
    ["is#"] = 2,
    ["is?"] = 2,
    ["isnot"] = 2,
    ["isnot#"] = 2,
    ["isnot?"] = 2,
    -- pipe
    ["->"] = 5,
    -- concatenation + additive share precedence (left-assoc)
    ["."] = 3,
    [".."] = 3,
    ["+"] = 3,
    ["-"] = 3,
    -- multiplicative
    ["*"] = 4,
    ["/"] = 4,
    ["%"] = 4,
}

local function parse(tokens)
    local i = 1
    local function peek() return tokens[i] end
    local function adv()
        local t = tokens[i]; i = i + 1; return t
    end
    local function expect(typ, val)
        local t = peek()
        if t.typ ~= typ or (val and t.val ~= val) then
            error(("Expected %s %s at %d, got %s %s"):format(typ, val or "", t.pos, t.typ, tostring(t.val)))
        end
        return adv()
    end
    local function tok_text(tok)
        if tok and tok.raw ~= nil then
            return tostring(tok.raw)
        end
        return tostring(tok and tok.val or "")
    end
    local function tok_end(tok)
        local text = tok_text(tok)
        return (tok and tok.pos or 1) + #text - 1
    end

    local expr, unary, apply_postfix

    function apply_postfix(node)
        while true do
            local t = peek()
            if t.typ == "OP" and t.val == "." and node.endpos and t.pos == (node.endpos + 1) then
                local save_i = i
                adv() -- '.'
                local keytok = peek()
                local nexttok = tokens[i + 1]
                local can_index = node.kind ~= "str" and node.kind ~= "num"
                if
                    can_index
                    and keytok.typ == "ID"
                    and keytok.pos == (t.pos + 1)
                    and not (nexttok and nexttok.typ == "COLON")
                then
                    local key = adv()
                    node = {
                        kind = "index",
                        a = node,
                        idx = { kind = "str", val = key.val, pos = key.pos, endpos = tok_end(key) },
                        pos = t.pos,
                        endpos = tok_end(key),
                    }
                else
                    i = save_i
                    break
                end
            elseif t.typ == "LBRACK" then
                adv() -- '['
                local first = nil
                if peek().typ ~= "COLON" and peek().typ ~= "RBRACK" then
                    first = expr(0)
                end
                if peek().typ == "COLON" then
                    adv() -- ':'
                    local last = nil
                    if peek().typ ~= "RBRACK" then
                        last = expr(0)
                    end
                    local close = expect("RBRACK")
                    node = {
                        kind = "slice",
                        a = node,
                        first = first,
                        last = last,
                        pos = t.pos,
                        endpos = tok_end(close)
                    }
                else
                    if first == nil then
                        error("Expected index or slice inside []")
                    end
                    local close = expect("RBRACK")
                    node = { kind = "index", a = node, idx = first, pos = t.pos, endpos = tok_end(close) }
                end
            else
                break
            end
        end
        return node
    end

    function unary()
        local t = peek()
        if t.typ == "OP" and (t.val == "+" or t.val == "-" or t.val == "!") then
            local op = adv().val
            return { kind = "unary", op = op, a = unary(), pos = t.pos }
        end
        if t.typ == "LPAREN" then
            adv()
            local n = expr(0)
            local close = expect("RPAREN")
            n.endpos = tok_end(close)
            return apply_postfix(n)
        end
        if t.typ == "LBRACK" then
            -- List literal: [expr, expr, ...]
            adv()
            local items = {}
            if peek().typ ~= "RBRACK" then
                while true do
                    local e = expr(0)
                    items[#items + 1] = e
                    if peek().typ == "RBRACK" then break end
                    local op = expect("OP").val
                    if op ~= "," then error("Expected ',' in list literal") end
                    if peek().typ == "RBRACK" then break end
                end
            end
            local close = expect("RBRACK")
            return apply_postfix({ kind = "list", items = items, pos = t.pos, endpos = tok_end(close) })
        end
        if t.typ == "LBRACE" then
            -- Try |curly-braces-names| first: {expr}name
            -- Example: {a:vt}netrw_dirkeep -> "w:netrw_dirkeep"
            do
                local save_i = i
                local ok_curly, node = pcall(function()
                    adv() -- '{'
                    local inner = expr(0)
                    expect("RBRACE")

                    -- Curly-name requires a following variable-name fragment.
                    local nxt = peek()
                    if nxt.typ ~= "ID" and nxt.typ ~= "NUM" then
                        error("__not_curly_var__")
                    end

                    local suffix = {}
                    while true do
                        local tk = peek()
                        if tk.typ == "ID" then
                            suffix[#suffix + 1] = adv().val
                        elseif tk.typ == "NUM" then
                            suffix[#suffix + 1] = tok_text(adv())
                        elseif tk.typ == "COLON" then
                            suffix[#suffix + 1] = ":"
                            adv()
                        elseif tk.typ == "OP" and (tk.val == "." or tk.val == "#") then
                            suffix[#suffix + 1] = tk.val
                            adv()
                        else
                            break
                        end
                    end

                    if #suffix == 0 then
                        error("__not_curly_var__")
                    end
                    return { kind = "curlyvar", inner = inner, suffix = table.concat(suffix), pos = t.pos }
                end)
                if ok_curly then
                    return apply_postfix(node)
                end
                i = save_i
            end

            -- Try lambda literal: {params -> body}
            do
                local save_i = i
                local ok_lambda, node = pcall(function()
                    adv() -- '{'
                    local params = {}
                    local function parse_param()
                        local tok = peek()
                        if tok.typ == "ID" or tok.typ == "NUM" then
                            return adv().val
                        elseif tok.typ == "OP" and tok.val == "_" then
                            adv(); return "_"
                        end
                        error("__not_lambda__")
                    end
                    params[#params + 1] = parse_param()
                    while true do
                        local tk = peek()
                        if tk.typ == "OP" and tk.val == "," then
                            adv(); params[#params + 1] = parse_param()
                        elseif tk.typ == "OP" and tk.val == "->" then
                            adv(); break
                        else
                            error("__not_lambda__")
                        end
                    end
                    local body = expr(0)
                    expect("RBRACE")
                    return { kind = "lambda", params = params, body = body, pos = t.pos }
                end)
                if ok_lambda then
                    return apply_postfix(node)
                end
                i = save_i
            end

            -- Dict literal: {key: value, ...}
            adv()
            local entries = {}
            if peek().typ ~= "RBRACE" then
                while true do
                    local kt = peek()
                    local key
                    if kt.typ == "STR" then
                        key = adv().val
                    elseif kt.typ == "NUM" then
                        key = tostring(adv().val)
                    elseif kt.typ == "ID" then
                        -- treat bare identifier as string key name (legacy friendly subset)
                        key = adv().val
                    else
                        error(("Invalid dict key at %d"):format(kt.pos))
                    end
                    expect("COLON")
                    local val = expr(0)
                    entries[#entries + 1] = { k = key, v = val }
                    if peek().typ == "RBRACE" then break end
                    local op = expect("OP").val
                    if op ~= "," then error("Expected ',' in dict literal") end
                end
            end
            local close = expect("RBRACE")
            return apply_postfix({ kind = "dict", entries = entries, pos = t.pos, endpos = tok_end(close) })
        end
        if t.typ == "AMP" then
            adv()
            local idtok = expect("ID")
            local id = idtok.val
            local scope = nil
            local endpos = tok_end(idtok)
            if peek().typ == "COLON" then
                local colon = adv()
                scope = id
                endpos = tok_end(colon)
                local nxt = peek()
                if nxt.typ == "ID" then
                    local name_tok = adv()
                    id = name_tok.val
                    endpos = tok_end(name_tok)
                elseif nxt.typ == "NUM" then
                    local name_tok = adv()
                    id = tok_text(name_tok)
                    endpos = tok_end(name_tok)
                else
                    error(("Expected ID or NUM after option scope at %d, got %s %s"):format(
                        nxt.pos, nxt.typ, tostring(nxt.val)))
                end
            end
            return apply_postfix({ kind = "opt", name = id, scope = scope, pos = t.pos, endpos = endpos })
        end
        if t.typ == "ENV" then
            local tok = adv()
            return apply_postfix({ kind = "env", name = tok.val, pos = tok.pos, endpos = tok_end(tok) })
        end
        if t.typ == "REG" then
            local tok = adv()
            return apply_postfix({ kind = "reg", name = tok.val, pos = tok.pos, endpos = tok_end(tok) })
        end
        if t.typ == "ID" then
            local id = adv().val
            local endpos = tok_end(tokens[i - 1])
            local scope, name = nil, id
            if peek().typ == "COLON" then
                local colon = adv()
                endpos = tok_end(colon)
                local nxt = peek()
                if nxt.typ == "ID" then
                    local name_tok = adv()
                    name = name_tok.val
                    endpos = tok_end(name_tok)
                elseif nxt.typ == "NUM" then
                    local name_tok = adv()
                    name = tok_text(name_tok)
                    endpos = tok_end(name_tok)
                else
                    -- Bare scope dictionary reference, e.g. g: / b: / s: ...
                    scope = id
                    name = nil
                end
                scope = scope or id
            end
            if scope and name == nil then
                return apply_postfix({ kind = "scope", scope = scope, pos = t.pos, endpos = endpos })
            end
            if scope == "v" and name == "lua" then
                local dot_i = i
                local segs = {}
                while peek().typ == "OP" and peek().val == "." do
                    adv()
                    local segtok = peek()
                    if segtok.typ ~= "ID" then
                        i = dot_i
                        segs = {}
                        break
                    end
                    segs[#segs + 1] = adv().val
                end
                if #segs > 0 and peek().typ == "LPAREN" then
                    adv() -- '('
                    local args = {}
                    if peek().typ ~= "RPAREN" then
                        while true do
                            local e = expr(0)
                            args[#args + 1] = e
                            if peek().typ == "RPAREN" then break end
                            local op = expect("OP").val
                            if op ~= "," then error("Expected ',' in arg list") end
                        end
                    end
                    local close = expect("RPAREN")
                    return apply_postfix({
                        kind = "call",
                        name = name,
                        scope = scope,
                        lua_path = table.concat(segs, "."),
                        args = args,
                        pos = t.pos,
                        endpos = tok_end(close),
                    })
                else
                    i = dot_i
                end
            end
            -- Support simple function call: Name '(' args? ')'
            if peek().typ == "LPAREN" then
                adv() -- '('
                local args = {}
                if peek().typ ~= "RPAREN" then
                    -- parse simple comma-separated expressions until ')'
                    while true do
                        local e = expr(0)
                        args[#args + 1] = e
                        if peek().typ == "RPAREN" then break end
                        local op = expect("OP").val
                        if op ~= "," then error("Expected ',' in arg list") end
                    end
                end
                local close = expect("RPAREN")
                return apply_postfix({
                    kind = "call",
                    name = name,
                    scope = scope,
                    args = args,
                    pos = t.pos,
                    endpos = tok_end(close)
                })
            end
            if peek().typ == "LBRACE" then
                local base = (scope and (scope .. ":") or "") .. tostring(name)
                local parts = { { kind = "lit", val = base } }
                while peek().typ == "LBRACE" do
                    adv() -- '{'
                    local inner = expr(0)
                    expect("RBRACE")
                    parts[#parts + 1] = { kind = "expr", val = inner }
                    local suffix = {}
                    while true do
                        local tk = peek()
                        if tk.typ == "ID" then
                            suffix[#suffix + 1] = adv().val
                        elseif tk.typ == "NUM" then
                            suffix[#suffix + 1] = tok_text(adv())
                        else
                            break
                        end
                    end
                    if #suffix > 0 then
                        parts[#parts + 1] = { kind = "lit", val = table.concat(suffix) }
                    end
                end
                return apply_postfix({ kind = "varcurly", parts = parts, pos = t.pos, endpos = endpos })
            end
            return apply_postfix({ kind = "var", scope = scope, name = name, pos = t.pos, endpos = endpos })
        end
        if t.typ == "NUM" then
            local tok = adv()
            return apply_postfix({ kind = "num", val = tok.val, pos = tok.pos, endpos = tok_end(tok) })
        end
        if t.typ == "STR" then
            local tok = adv()
            return apply_postfix({ kind = "str", val = tok.val, pos = tok.pos, endpos = tok_end(tok) })
        end
        error(("Unexpected token %s %s at %d"):format(t.typ, tostring(t.val), t.pos))
    end

    function expr(minp)
        local left = unary()
        while true do
            local t = peek()
            if t.typ ~= "OP" then break end
            if t.val == "?" then break end
            local p = PREC[t.val]
            if not p or p < minp then break end
            local op = adv().val
            local right = expr(p + 1)
            if op == "->" and right.kind == "call" then
                -- Pipe: inject left as first arg to the call.
                local new_args = { left }
                for j = 1, #right.args do new_args[#new_args + 1] = right.args[j] end
                left = { kind = "call", name = right.name, scope = right.scope, args = new_args, pos = t.pos }
            else
                left = { kind = "binop", op = op, a = left, b = right, pos = t.pos }
            end
        end
        -- Ternary: cond ? expr1 : expr2 (lowest precedence, right-assoc)
        if minp <= 0 and peek().typ == "OP" and peek().val == "?" then
            local qtok = adv() -- '?'
            local t_expr = expr(0)
            expect("COLON")
            local f_expr = expr(0)
            left = { kind = "ternary", cond = left, t = t_expr, f = f_expr, pos = qtok.pos }
        end
        return left
    end

    local root = expr(0)
    return root, i
end

-- -------- evaluator --------
local function decide_case(op)
    if op:sub(-1) == "#" then return true end
    if op:sub(-1) == "?" then return false end
    local ic = options.get("ignorecase")
    if is_error(ic) then return ic end
    return not (ic and ic ~= 0) -- true => case-sensitive
end

local function cmp_norm(a, b, case_sensitive, vim9)
    local ta, tb = type(a), type(b)
    if ta == "string" and tb == "string" then
        if not case_sensitive then
            a = a:lower(); b = b:lower()
        end
        if a == b then return 0 elseif a < b then return -1 else return 1 end
    end

    if ta == "number" and tb == "number" then
        if a == b then return 0 elseif a < b then return -1 else return 1 end
    end

    if ta == "string" and tb == "string" then
        if not case_sensitive then
            a = a:lower(); b = b:lower()
        end
        if a == b then return 0 elseif a < b then return -1 else return 1 end
    end

    if ta == "nil" then
        if tb == "nil" then return 1 else return 0 end
    elseif tb == "nil" then
        if ta == "nil" then return 1 else return 0 end
    end

    if not vim9 then
        if (ta == "string" and tb == "number") or (tb == "string" and ta == "number") then
            local na, nb = num_coerce(a), num_coerce(b)
            if na == nb then return 0 elseif na < nb then return -1 else return 1 end
        end
    end

    LOG_DEBUG(
        "ERROR: Unimplemented/unknown comparison: a=%s (%s) b=%s (%s)",
        tostring(a),
        type(a),
        tostring(b),
        type(b)
    )
    return 0
end

local function eval_node(node, vim9, env)
    local k = node.kind
    if k == "num" then return node.val end
    if k == "str" then return node.val end
    if k == "list" then
        local out = {}
        for i = 1, #node.items do
            local v = eval_node(node.items[i], vim9, env); if is_error(v) then return v end
            out[i] = v
        end
        return mark_list(out)
    end
    if k == "dict" then
        local out = {}
        for i = 1, #node.entries do
            local pair = node.entries[i]
            local v = eval_node(pair.v, vim9, env); if is_error(v) then return v end
            out[pair.k] = v
        end
        return mark_dict(out)
    end
    local function resolve_var(scope_name, var_name)
        local scope = (env and env.scope) or {}
        local function from(tbl)
            if tbl then return tbl[var_name] end
            return nil
        end
        if scope_name == "g" then
            return from(scope.g) or Scopes._g[var_name]
        elseif scope_name == "s" then
            return from(scope.s)
        elseif scope_name == "v" then
            return from(scope.v) or Scopes._v[var_name]
        elseif scope_name == "b" then
            return Scopes.b[var_name]
        elseif scope_name == "w" then
            return Scopes.w[var_name]
        elseif scope_name == "t" then
            return Scopes.t[var_name]
        elseif scope_name == "l" then
            return from(scope.l)
        elseif scope_name == "a" then
            local v = from(scope.a)
            if v == nil then
                LOG_DEBUG("vimxpr a:%s is nil (scope.a=%s)", tostring(var_name), tostring(scope.a))
            end
            return v
        else
            -- bare: prefer l: if present, else g:
            if scope.l and scope.l[var_name] ~= nil then return scope.l[var_name] end
            if scope.g and scope.g[var_name] ~= nil then return scope.g[var_name] end
            if var_name == "ptch" then
                LOG_DEBUG("vimxpr var ptch missing (l=%s g=%s)", tostring(scope.l and scope.l.ptch),
                    tostring(scope.g and scope.g.ptch))
            end
            return nil
        end
    end

    if k == "var" then
        return resolve_var(node.scope, node.name)
    end
    if k == "scope" then
        local scope = (env and env.scope) or {}
        if node.scope == "g" then
            return scope.g or Scopes.g
        elseif node.scope == "s" then
            return scope.s or {}
        elseif node.scope == "v" then
            return scope.v or Scopes.v
        elseif node.scope == "b" then
            return Scopes.b
        elseif node.scope == "w" then
            return Scopes.w
        elseif node.scope == "t" then
            return Scopes.t
        elseif node.scope == "l" then
            return scope.l or {}
        elseif node.scope == "a" then
            return scope.a or {}
        end
        return {}
    end
    if k == "curlyvar" then
        local pv = eval_node(node.inner, vim9, env); if is_error(pv) then return pv end
        local full = tostring(pv or "") .. (node.suffix or "")
        local scope_name, var_name = full:match("^([gsalvbtw]):(.+)$")
        if scope_name then
            return resolve_var(scope_name, var_name)
        end
        return resolve_var(nil, full)
    end
    if k == "varcurly" then
        local chunks = {}
        for i = 1, #node.parts do
            local part = node.parts[i]
            if part.kind == "lit" then
                chunks[#chunks + 1] = part.val or ""
            else
                local pv = eval_node(part.val, vim9, env); if is_error(pv) then return pv end
                chunks[#chunks + 1] = tostring(pv or "")
            end
        end
        local full = table.concat(chunks)
        local scope_name, var_name = full:match("^([gsalvbtw]):(.+)$")
        if scope_name then
            return resolve_var(scope_name, var_name)
        end
        return resolve_var(nil, full)
    end
    if k == "lambda" then
        local params = node.params or {}
        return function(...)
            local args = { ... }
            local l, a = {}, {}
            for idx = 1, #params do
                l[params[idx]] = args[idx]
                a[params[idx]] = args[idx]
            end
            local child_env = {
                scope = { l = l, a = a, g = Scopes._g, v = Scopes._v },
                funcs = env.funcs,
                script_sid = env.script_sid,
            }
            return eval_node(node.body, vim9, child_env)
        end
    end
    if k == "call" then
        local f = nil
        if node.scope == "v" and node.name == "lua" then
            if not node.lua_path then
                return Error(117, "v:lua")
            end
            f = resolve_vlua_path(node.lua_path)
            if is_error(f) then return f end
        else
            local scoped_name = node.scope and (tostring(node.scope) .. ":" .. tostring(node.name))
            if not f and scoped_name and type(env.funcs[scoped_name]) == "function" then
                f = env.funcs[scoped_name]
            end
            if not f and node.scope == "s" and env.script_sid then
                local snr_name = "<SNR>" .. tostring(env.script_sid) .. "_" .. tostring(node.name)
                if type(env.funcs[snr_name]) == "function" then
                    f = env.funcs[snr_name]
                end
            end
            -- Builtins first
            if not f and type(VimFnBuiltins.fn[node.name]) == "function" then
                f = VimFnBuiltins.fn[node.name]
            end
            -- Then user-provided functions map
            if not f and type(env.funcs[node.name]) == "function" then
                f = env.funcs[node.name]
            end
        end
        if type(f) ~= "function" then
            if node.scope == "v" and node.name == "lua" then
                return Error(117, "v:lua." .. tostring(node.lua_path or ""))
            end
            return Error(117, node.name)
        end
        local argv = {}
        for i = 1, #node.args do
            local v = eval_node(node.args[i], vim9, env); if is_error(v) then return v end
            argv[i] = v
        end
        VimFnBuiltins._push_eval_scope(env and env.scope)
        local ok, rv = pcall(f, table.unpack(argv))
        VimFnBuiltins._pop_eval_scope()
        if not ok then
            if Error.IsError(rv) then
                return rv
            end
            return Error(5108, tostring(rv))
        end
        return rv
    end

    if k == "index" then
        local container = eval_node(node.a, vim9, env); if is_error(container) then return container end
        local idx = eval_node(node.idx, vim9, env); if is_error(idx) then return idx end
        if container == nil then return nil end

        if type(container) == "table" then
            local kind = table_kind(container)
            if kind == "list" and type(idx) == "number" then
                local key = idx >= 0 and (idx + 1) or (#container + idx + 1)
                return container[key]
            end
            return container[idx]
        end

        if type(container) == "string" then
            if type(idx) ~= "number" then return nil end
            local pos = idx >= 0 and (idx + 1) or (#container + idx + 1)
            if pos < 1 or pos > #container then return "" end
            return container:sub(pos, pos)
        end

        return nil
    end

    if k == "slice" then
        local container = eval_node(node.a, vim9, env); if is_error(container) then return container end
        if container == nil then return nil end

        local first = nil
        local last = nil
        if node.first ~= nil then
            first = eval_node(node.first, vim9, env); if is_error(first) then return first end
        end
        if node.last ~= nil then
            last = eval_node(node.last, vim9, env); if is_error(last) then return last end
        end

        local function to_index(v, default)
            if v == nil then return default end
            local n = num_coerce(v)
            if n == nil then return default end
            if n >= 0 then
                return math.floor(n)
            end
            return math.ceil(n)
        end

        local function to_bounds(len, start_v, end_v)
            if len <= 0 then
                return nil, nil
            end
            local s = to_index(start_v, 0)
            local e = to_index(end_v, -1)
            if s < 0 then s = len + s end
            if e < 0 then e = len + e end
            s = s + 1
            e = e + 1
            if s < 1 then s = 1 end
            if e > len then e = len end
            if s > len or e < 1 or s > e then
                return nil, nil
            end
            return s, e
        end

        if type(container) == "table" then
            if table_kind(container) ~= "list" then
                return nil
            end
            local s, e = to_bounds(#container, first, last)
            if not s then
                return mark_list({})
            end
            local out = {}
            for i = s, e do
                out[#out + 1] = container[i]
            end
            return mark_list(out)
        end

        if type(container) == "string" then
            local s, e = to_bounds(#container, first, last)
            if not s then
                return ""
            end
            return container:sub(s, e)
        end

        return nil
    end

    if k == "opt" then
        local win = windows[curwin]
        local buf = win.buffer
        local getlocal, getglobal = false, false
        if node.scope == "l" then
            getlocal = true
        elseif node.scope == "g" then
            getglobal = true
        end
        local val = options.get(node.name, win, buf, getlocal, getglobal)
        if type(val) == "boolean" then
            return val and 1 or 0
        end
        return val
    end
    if k == "env" then
        local v = EnvVars.get(node.name)
        if v == nil then return "" end
        if type(v) == "boolean" then return v and "1" or "" end -- coerce booleans to typical env-stringy values
        return tostring(v)
    end
    if k == "reg" then
        local regs = registers
        local key = node.name
        if key == "@" then key = "unnamed" end
        local regval = regs[key]
        if regval == nil and type(key) == "string" and key:match("^%d$") then
            regval = regs[tonumber(key)]
        end
        if regval == nil then return "" end
        if type(regval) == "table" then
            local val = regval[2]
            if type(val) == "table" then
                return table.concat(val, "\n")
            elseif type(val) == "string" then
                return val
            else
                return tostring(val)
            end
        end
        if type(regval) == "string" then return regval end
        return tostring(regval)
    end
    if k == "unary" then
        local v = eval_node(node.a, vim9, env); if is_error(v) then return v end
        if node.op == "!" then
            if vim9 then
                if type(v) ~= "boolean" then return Error(0, "Expected boolean for ! in Vim9") end
                return not v
            else
                return as_bool_legacy(v) and 0 or 1
            end
        end
        local n
        if vim9 then
            if type(v) ~= "number" then return Error(0, "Unary on non-number") end
            n = v
        else
            local nerr
            n, nerr = num_coerce_or_error(v)
            if n == nil then return nerr end
        end
        if node.op == "+" then return n else return -n end
    end
    if k == "binop" then
        -- short-circuit logical ops: only evaluate RHS when needed
        if node.op == "||" then
            local L = eval_node(node.a, vim9, env); if is_error(L) then return L end
            local truth = vim9 and (type(L) == "boolean" and L) or as_bool_legacy(L)
            if truth then return vim9 and true or 1 end
            local R = eval_node(node.b, vim9, env); if is_error(R) then return R end
            local rtruth = vim9 and (type(R) == "boolean" and R) or as_bool_legacy(R)
            return vim9 and rtruth or (rtruth and 1 or 0)
        elseif node.op == "&&" then
            local L = eval_node(node.a, vim9, env); if is_error(L) then return L end
            local truth = vim9 and (type(L) == "boolean" and L) or as_bool_legacy(L)
            if not truth then return vim9 and false or 0 end
            local R = eval_node(node.b, vim9, env); if is_error(R) then return R end
            local rtruth = vim9 and (type(R) == "boolean" and R) or as_bool_legacy(R)
            return vim9 and rtruth or (rtruth and 1 or 0)
        end

        local L = eval_node(node.a, vim9, env); if is_error(L) then return L end
        local R = eval_node(node.b, vim9, env); if is_error(R) then return R end
        local op = node.op

        -- arithmetic
        if op == "+" or op == "-" or op == "*" or op == "/" or op == "%" then
            if op == "+" and type(L) == "table" and type(R) == "table" then
                local lkind = table_kind(L)
                local rkind = table_kind(R)
                if lkind == "list" and rkind == "list" then
                    local out = {}
                    for i = 1, #L do
                        out[#out + 1] = L[i]
                    end
                    for i = 1, #R do
                        out[#out + 1] = R[i]
                    end
                    return mark_list(out)
                end
            end

            local a, b = L, R
            if vim9 then
                if type(a) ~= "number" or type(b) ~= "number" then
                    return Error(0,
                        "Type error: arithmetic on non-numbers")
                end
            else
                local aerr, berr
                a, aerr = num_coerce_or_error(a)
                if a == nil then return aerr end
                b, berr = num_coerce_or_error(b)
                if b == nil then return berr end
            end
            if op == "+" then return a + b end
            if op == "-" then return a - b end
            if op == "*" then return a * b end
            if op == "/" then return a / b end
            if op == "%" then
                if
                    type(a) == "number"
                    and type(b) == "number"
                    and (math.type and (math.type(a) == "float" or math.type(b) == "float"))
                then
                    return Error(0, "Float modulo")
                end
                return a % b
            end
        end

        -- concatenation
        if op == "." or op == ".." then
            if vim9 and op == "." then return Error(0, "'.' not allowed in Vim9") end
            return to_string_simple(L) .. to_string_simple(R)
        end

        -- comparisons and matches
        local cmp_ops = {
            ["=="] = true,
            ["!="] = true,
            ["<"] = true,
            ["<="] = true,
            [">"] = true,
            [">="] = true,
            ["==#"] = true,
            ["!=#"] = true,
            ["<#"] = true,
            ["<=#"] = true,
            [">#"] = true,
            [">=#"] = true,
            ["==?"] = true,
            ["!=?"] = true,
            ["<?"] = true,
            ["<=?"] = true,
            [">?"] = true,
            [">=?"] = true,
        }
        if cmp_ops[op] then
            local case = decide_case(op); if is_error(case) then return case end
            local base = op:gsub("[#?]$", "")
            local c = cmp_norm(L, R, case, vim9)
            if is_error(c) then
                LOG_DEBUG("Comparison failed op=%s L=%s (%s) R=%s (%s)", tostring(op), tostring(L), type(L),
                    tostring(R), type(R))
                return c
            end
            local out
            if base == "==" then
                out = (c == 0)
            elseif base == "!=" then
                out = (c ~= 0)
            elseif base == "<" then
                out = (c < 0)
            elseif base == "<=" then
                out = (c <= 0)
            elseif base == ">" then
                out = (c > 0)
            elseif base == ">=" then
                out = (c >= 0)
            end
            return vim9 and out or (out and 1 or 0)
        end

        if op:match("^=~[#?]?$") or op:match("^!~[#?]?$") then
            local case = decide_case(op); if is_error(case) then return case end
            local ok = VimRegex.match(to_string_simple(L), to_string_simple(R), case)
            local res
            if op:sub(1, 1) == "!" then
                res = not ok
            else
                res = ok
            end
            return vim9 and res or (res and 1 or 0)
        end

        if op:match("^isnot[#?]?$") or op:match("^is[#?]?$") then
            local neg = op:sub(1, 5) == "isnot"
            local case = decide_case(op); if is_error(case) then return case end
            local same
            if type(L) == "table" or type(R) == "table" then
                same = rawequal(L, R)
            elseif type(L) ~= type(R) then
                same = false
            elseif type(L) == "string" then
                if not case then
                    same = L:lower() == R:lower()
                else
                    same = L == R
                end
            else
                same = L == R
            end
            local res
            if neg then
                res = not same
            else
                res = same
            end
            return vim9 and res or (res and 1 or 0)
        end

        return Error(0, "Unknown operator: " .. op)
    end
    if k == "ternary" then
        local cond = eval_node(node.cond, vim9, env); if is_error(cond) then return cond end
        local truth = vim9 and (type(cond) == "boolean" and cond) or as_bool_legacy(cond)
        if truth then
            return eval_node(node.t, vim9, env)
        end
        return eval_node(node.f, vim9, env)
    end
    return Error(0, "Unknown node: " .. tostring(k or "eval_node got nil!"))
end

-- Public API:
-- Returns value or Error object.
function M.evaluate(expr, opts)
    opts = opts or {}
    local vim9 = not not opts.vim9
    local env = {
        scope = opts.scope,
        funcs = opts.funcs,
    }
    local toks = tokenize(expr)
    local ok, ast, next_i = pcall(parse, toks)
    if not ok then
        LOG_DEBUG("vimxpr parse error expr=%s err=%s", tostring(expr), tostring(ast))
        error(ast)
    end
    if toks[next_i].typ ~= "EOF" then
        LOG_DEBUG("vimxpr trailing input expr=%s pos=%d token=%s", tostring(expr), tonumber(toks[next_i].pos),
            tostring(toks[next_i].typ))
        return Error(0, ("Trailing input at %d"):format(toks[next_i].pos))
    end
    return eval_node(ast, vim9, env)
end

function M.splitExpressions(expr_str)
    local expressions = {}
    local current_pos = 1

    while current_pos <= #expr_str do
        local sub_expr = expr_str:sub(current_pos)
        if sub_expr:match("^%s*$") then break end

        local ok, toks = pcall(tokenize, sub_expr)
        if not ok or #toks <= 1 then -- only EOF
            local first_word = sub_expr:match("^%s*([^%s]+)")
            if first_word then
                expressions[#expressions + 1] = first_word
                current_pos = current_pos + (sub_expr:find(first_word, 1, true) + #first_word - 1)
            else
                break -- Should not happen if not empty
            end
            goto continue
        end

        local ok_parse, _, end_tok_idx = pcall(parse, toks)
        if not ok_parse or not end_tok_idx then
            local first_word = sub_expr:match("^%s*([^%s]+)")
            if first_word then
                expressions[#expressions + 1] = first_word
                current_pos = current_pos + (sub_expr:find(first_word, 1, true) + #first_word - 1)
            else
                break
            end
            goto continue
        end

        -- Use the next token's start to compute the end of the parsed expression.
        -- This preserves original source length (including quotes), avoiding stalls.
        local next_tok = toks[end_tok_idx]
        local end_pos = (next_tok and next_tok.pos and (next_tok.pos - 1)) or #sub_expr
        if end_pos < 1 then end_pos = 1 end

        expressions[#expressions + 1] = sub_expr:sub(1, end_pos)
        current_pos = current_pos + end_pos

        ::continue::
    end

    return expressions
end

return M
