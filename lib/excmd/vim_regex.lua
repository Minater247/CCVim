-- vim_regex.lua
-- Hybrid Vim-style regex engine:
--   - Fast path: translate simple subset to Lua patterns (high throughput).
--   - VM path: backtracking matcher for syntax-oriented constructs.
--
-- VM-supported Stage 3 constructs:
--   lookarounds: \@= \@! \@<= \@<!
--   zero-width span markers: \zs \ze
--   external captures/backrefs: \z(...) \z1..
--   grouping forms: \%(...) and \%[...]
--   generalized \_ classes (newline-inclusive class atoms)
--
-- This module intentionally focuses on syntax-engine needs and guardrails.

local R = {}

local str_find = string.find
local str_sub = string.sub
local str_lower = string.lower

local DOT_NO_NL = "[^\n]"
local DOT_YES_NL = "."
local FRONT_WORD = "%f[%w_]"
local FRONT_NOT_WORD = "%f[^%w_]"

local COUNT_MAX = 12       -- max optional expansions for simple-path {m,n}
local BRANCH_MAX = 2048    -- simple-path combinatorial guard
local CACHE_MAX = 128

local VM_MAX_COUNT = 4096
local VM_LOOKBEHIND_MAX = 256
local VM_STEPS_BASE = 50000
local VM_STEPS_PER_CHAR = 128
local VM_PREFILTER_LITERAL_MAX = 24
local SIMPLE_VM_FALLBACK_MIN_HAY = 8192
local SIMPLE_VM_FALLBACK_MIN_LEAD = 2
local SIMPLE_VM_FALLBACK_MIN_POS = 256

local CLASS_MAP = {
    ["\\d"] = "%d",
    ["\\D"] = "%D",
    ["\\s"] = "%s",
    ["\\S"] = "%S",
    ["\\a"] = "%a",
    ["\\A"] = "[^%a]",
    ["\\l"] = "%l",
    ["\\L"] = "[^%l]",
    ["\\u"] = "%u",
    ["\\U"] = "[^%u]",
    ["\\x"] = "%x",
    ["\\X"] = "[^%x]",
    ["\\o"] = "[0-7]",
    ["\\O"] = "[^0-7]",
    ["\\h"] = "[%a_]",
    ["\\H"] = "[^%a_]",
    ["\\k"] = "[%w_]",
    ["\\K"] = "[^%w_]",
    ["\\f"] = "[%w_./-]",
    ["\\F"] = "[^%w_./-]",
    ["\\p"] = "[%g ]",
    ["\\P"] = "[^%g ]",
    ["\\i"] = "[%w_]",
    ["\\I"] = "[%a_]",
    ["\\w"] = "[%w_]",
    ["\\W"] = "[^%w_]",
    ["\\_."] = DOT_YES_NL,
    ["\\_s"] = "%s",
    ["\\_S"] = "%S",
    ["."] = DOT_NO_NL,
}

local compile_cache = {}
local cache_keys = {}
local compile_vm_uncached

local function err(msg)
    return nil, msg
end

local function lua_escape_string(s)
    return (s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function cache_touch(key)
    for i = 1, #cache_keys do
        if cache_keys[i] == key then
            table.remove(cache_keys, i)
            break
        end
    end
    cache_keys[#cache_keys + 1] = key
end

local function cache_get(key)
    local value = compile_cache[key]
    if value then
        cache_touch(key)
    end
    return value
end

local function cache_put(key, value)
    if compile_cache[key] then
        compile_cache[key] = value
        cache_touch(key)
        return
    end

    compile_cache[key] = value
    cache_keys[#cache_keys + 1] = key

    if #cache_keys > CACHE_MAX then
        local old = table.remove(cache_keys, 1)
        if old then
            compile_cache[old] = nil
        end
    end
end

function R.clear_cache()
    compile_cache = {}
    cache_keys = {}
end

-- ============================================================================
-- Fast-path tokenizer/parser/translator (existing high-throughput subset)
-- ============================================================================

local function tokenize_simple(pat)
    local i, n = 1, #pat
    local mode = "magic"
    local toks, ntoks = {}, 0

    local function peek(k)
        k = k or 0
        local j = i + k
        if j > n then return "" end
        return pat:sub(j, j)
    end

    local function add(t, v)
        ntoks = ntoks + 1
        toks[ntoks] = { t = t, v = v }
    end

    local function is_magic_char(ch)
        if mode == "verymagic" then
            return ch:match("[%^%$%.%*%+%?%[%]%(%){|}]") ~= nil
        elseif mode == "nomagic" then
            return ch == "^" or ch == "$"
        elseif mode == "verynomagic" then
            return ch == "." or ch == "^" or ch == "$"
        else
            return ch:match("[%.%*%[%]^$]") ~= nil
        end
    end

    local function read_bracket_class()
        local start = i
        i = i + 1 -- '['
        if peek() == "^" then i = i + 1 end

        local closed = false
        while i <= n do
            local c = peek()
            i = i + 1
            if c == "\\" then
                if i <= n then i = i + 1 end
            elseif c == "]" then
                closed = true
                break
            end
        end

        if not closed then
            return nil, "Unterminated [] class"
        end
        return pat:sub(start, i - 1)
    end

    local function try_counted_repeat(escaped)
        local m, n2, after
        if escaped then
            m, n2, after = pat:match("^\\{(%d+),(%d+)\\}()", i)
            if m then
                add("QCOUNT", { tonumber(m), tonumber(n2) })
                i = after
                return true
            end
            m, n2, after = pat:match("^\\{(%d+),(%d+)}()", i)
            if m then
                add("QCOUNT", { tonumber(m), tonumber(n2) })
                i = after
                return true
            end
            m, after = pat:match("^\\{(%d+),\\}()", i)
            if m then
                add("QCOUNT", { tonumber(m), nil })
                i = after
                return true
            end
            m, after = pat:match("^\\{(%d+),}()", i)
            if m then
                add("QCOUNT", { tonumber(m), nil })
                i = after
                return true
            end
            n2, after = pat:match("^\\{,(%d+)\\}()", i)
            if n2 then
                add("QCOUNT", { 0, tonumber(n2) })
                i = after
                return true
            end
            n2, after = pat:match("^\\{,(%d+)}()", i)
            if n2 then
                add("QCOUNT", { 0, tonumber(n2) })
                i = after
                return true
            end
            m, after = pat:match("^\\{(%d+)\\}()", i)
            if m then
                local nn = tonumber(m)
                add("QCOUNT", { nn, nn })
                i = after
                return true
            end
            m, after = pat:match("^\\{(%d+)}()", i)
            if m then
                local nn = tonumber(m)
                add("QCOUNT", { nn, nn })
                i = after
                return true
            end
        else
            m, n2, after = pat:match("^{(%d+),(%d+)\\}()", i)
            if m then
                add("QCOUNT", { tonumber(m), tonumber(n2) })
                i = after
                return true
            end
            m, n2, after = pat:match("^{(%d+),(%d+)}()", i)
            if m then
                add("QCOUNT", { tonumber(m), tonumber(n2) })
                i = after
                return true
            end
            m, after = pat:match("^{(%d+),\\}()", i)
            if m then
                add("QCOUNT", { tonumber(m), nil })
                i = after
                return true
            end
            m, after = pat:match("^{(%d+),}()", i)
            if m then
                add("QCOUNT", { tonumber(m), nil })
                i = after
                return true
            end
            n2, after = pat:match("^{,(%d+)\\}()", i)
            if n2 then
                add("QCOUNT", { 0, tonumber(n2) })
                i = after
                return true
            end
            n2, after = pat:match("^{,(%d+)}()", i)
            if n2 then
                add("QCOUNT", { 0, tonumber(n2) })
                i = after
                return true
            end
            m, after = pat:match("^{(%d+)\\}()", i)
            if m then
                local nn = tonumber(m)
                add("QCOUNT", { nn, nn })
                i = after
                return true
            end
            m, after = pat:match("^{(%d+)}()", i)
            if m then
                local nn = tonumber(m)
                add("QCOUNT", { nn, nn })
                i = after
                return true
            end
        end
        return false
    end

    while i <= n do
        local c = peek()

        if c == "\\" then
            local e = peek(1)

            if e == "v" then
                mode = "verymagic"
                i = i + 2
                goto cont
            end
            if e == "V" then
                mode = "verynomagic"
                i = i + 2
                goto cont
            end
            if e == "m" then
                mode = "magic"
                i = i + 2
                goto cont
            end
            if e == "M" then
                mode = "nomagic"
                i = i + 2
                goto cont
            end
            if e == "" then
                add("LIT", "\\")
                i = i + 1
                goto cont
            end

            if CLASS_MAP["\\" .. e] then
                add("CLASS", "\\" .. e)
                i = i + 2
                goto cont
            end

            if e == "_" then
                local e2 = peek(2)
                if e2 == "." then
                    add("CLASS", "\\_.")
                    i = i + 3
                    goto cont
                elseif e2 == "s" then
                    add("CLASS", "\\_s")
                    i = i + 3
                    goto cont
                elseif e2 == "S" then
                    add("CLASS", "\\_S")
                    i = i + 3
                    goto cont
                end
            end

            if e == "<" then
                add("WB", "\\<")
                i = i + 2
                goto cont
            elseif e == ">" then
                add("WB", "\\>")
                i = i + 2
                goto cont
            elseif e == "(" then
                add("LP", "\\(")
                i = i + 2
                goto cont
            elseif e == ")" then
                add("RP", "\\)")
                i = i + 2
                goto cont
            elseif e == "|" then
                add("ALT", "\\|")
                i = i + 2
                goto cont
            elseif e == "+" then
                add("Q", "+")
                i = i + 2
                goto cont
            elseif e == "?" then
                add("Q", "?")
                i = i + 2
                goto cont
            elseif e == "{" then
                if try_counted_repeat(true) then goto cont end
                add("LIT", "{")
                i = i + 2
                goto cont
            end

            if e:match("%a") then
                return nil, ("Unsupported escape in simple regex: \\%s"):format(e)
            end

            add("LIT", e)
            i = i + 2
            goto cont
        end

        if c == "[" and (mode == "magic" or mode == "verymagic") then
            local bclass, berr = read_bracket_class()
            if not bclass then
                return nil, berr
            end
            add("BCLASS", bclass)
            goto cont
        end

        if mode == "verymagic" then
            if c == "|" then
                add("ALT", "|")
                i = i + 1
                goto cont
            elseif c == "(" then
                add("LP", "(")
                i = i + 1
                goto cont
            elseif c == ")" then
                add("RP", ")")
                i = i + 1
                goto cont
            elseif c == "+" then
                add("Q", "+")
                i = i + 1
                goto cont
            elseif c == "?" then
                add("Q", "?")
                i = i + 1
                goto cont
            elseif c == "{" then
                if try_counted_repeat(false) then goto cont end
                add("LIT", "{")
                i = i + 1
                goto cont
            end
        end

        if c == "^" and is_magic_char("^") then
            add("ANCH", "^")
            i = i + 1
            goto cont
        elseif c == "$" and is_magic_char("$") then
            add("ANCH", "$")
            i = i + 1
            goto cont
        elseif c == "." and is_magic_char(".") then
            add("CLASS", ".")
            i = i + 1
            goto cont
        elseif c == "*" and is_magic_char("*") then
            add("Q", "*")
            i = i + 1
            goto cont
        end

        add("LIT", c)
        i = i + 1

        ::cont::
    end

    ntoks = ntoks + 1
    toks[ntoks] = { t = "EOF", v = nil }
    return toks
end

local function parse_simple(tokens)
    local i, n = 1, #tokens

    local function peek()
        return tokens[i]
    end

    local function consume()
        local t = tokens[i]
        i = i + 1
        return t
    end

    local parse_alt

    local function parse_atom()
        local t = peek()
        if not t then return nil end

        if t.t == "LIT" or t.t == "CLASS" or t.t == "BCLASS" or t.t == "WB" or t.t == "ANCH" then
            consume()
            return { kind = "ATOM", atom = t }
        end

        if t.t == "LP" then
            consume()
            local subtree, emsg = parse_alt()
            if not subtree then return nil, emsg end
            local rp = peek()
            if not rp or rp.t ~= "RP" then
                return nil, "Unmatched ("
            end
            consume()
            return { kind = "GROUP", sub = subtree }
        end

        if t.t == "RP" then
            return nil, "Unmatched )"
        end

        return nil
    end

    local function parse_seq()
        local nodes = {}
        while i <= n do
            local t = peek()
            if not t or t.t == "EOF" or t.t == "ALT" or t.t == "RP" then
                break
            end

            local atom, emsg = parse_atom()
            if not atom then
                return nil, emsg or ("Unexpected token: " .. tostring(t.t or "?"))
            end

            local q = peek()
            if q and (q.t == "Q" or q.t == "QCOUNT") then
                consume()
                atom.quant = q
            end

            nodes[#nodes + 1] = atom
        end

        return { kind = "SEQ", nodes = nodes }
    end

    parse_alt = function()
        local branches = {}

        local seq, emsg = parse_seq()
        if not seq then return nil, emsg end
        branches[#branches + 1] = seq

        while i <= n do
            local t = peek()
            if not t or t.t ~= "ALT" then break end
            consume()
            local nxt, e2 = parse_seq()
            if not nxt then return nil, e2 end
            branches[#branches + 1] = nxt
        end

        if #branches == 1 then
            return branches[1]
        end

        return { kind = "ALT", branches = branches }
    end

    local tree, emsg = parse_alt()
    if not tree then return nil, emsg end

    local trailing = peek()
    if trailing and trailing.t ~= "EOF" then
        if trailing.t == "RP" then
            return nil, "Unmatched )"
        end
        return nil, "Unexpected token: " .. tostring(trailing.t)
    end

    return tree
end

local function make_frag(pat, plain, single)
    return {
        pat = pat,
        plain = plain,
        single = single or false,
    }
end

local EMPTY_FRAG = make_frag("", "", false)

local function combine_frag(a, b)
    local plain
    if a.plain ~= nil and b.plain ~= nil then
        plain = a.plain .. b.plain
    end

    local single
    if a.pat == "" then
        single = b.single
    elseif b.pat == "" then
        single = a.single
    else
        single = false
    end

    return make_frag(a.pat .. b.pat, plain, single)
end

local function product(lhs, rhs)
    if #lhs == 0 or #rhs == 0 then
        return {}
    end

    local out, nout = {}, 0
    for i = 1, #lhs do
        local a = lhs[i]
        for j = 1, #rhs do
            nout = nout + 1
            if nout > BRANCH_MAX then
                return nil, ("Branch explosion (>%d branches)"):format(BRANCH_MAX)
            end
            out[nout] = combine_frag(a, rhs[j])
        end
    end

    return out
end

local function normalize_bclass(raw)
    local n = #raw
    if n < 2 or raw:sub(1, 1) ~= "[" or raw:sub(n, n) ~= "]" then
        return raw
    end

    local inner = raw:sub(2, n - 1)
    local out = { "[" }
    local i = 1
    local m = #inner

    while i <= m do
        local ch = inner:sub(i, i)
        if ch == "%" then
            out[#out + 1] = "%%"
            i = i + 1
        elseif ch == "\\" and i < m then
            local nxt = inner:sub(i + 1, i + 1)
            if nxt == "d" or nxt == "D" or nxt == "s" or nxt == "S" or nxt == "w" or nxt == "W" then
                out[#out + 1] = "%" .. nxt
            elseif nxt == "^" or nxt == "]" or nxt == "-" or nxt == "[" then
                out[#out + 1] = "%" .. nxt
            elseif nxt == "t" then
                out[#out + 1] = "\t"
            elseif nxt == "n" then
                out[#out + 1] = "\n"
            elseif nxt == "r" then
                out[#out + 1] = "\r"
            elseif nxt == "e" then
                out[#out + 1] = string.char(27)
            else
                out[#out + 1] = nxt
            end
            i = i + 2
        else
            out[#out + 1] = ch
            i = i + 1
        end
    end

    out[#out + 1] = "]"
    return table.concat(out)
end

local function translate_atom(atom)
    local t = atom.atom

    if t.t == "LIT" then
        local lit = t.v
        return make_frag(lua_escape_string(lit), lit, true)
    end

    if t.t == "ANCH" then
        if t.v == "^" or t.v == "$" then
            return make_frag(t.v, nil, false)
        end
    elseif t.t == "WB" then
        if t.v == "\\<" then
            return make_frag(FRONT_WORD, nil, false)
        elseif t.v == "\\>" then
            return make_frag(FRONT_NOT_WORD, nil, false)
        end
    elseif t.t == "CLASS" then
        local mapped = CLASS_MAP[t.v]
        if mapped then
            return make_frag(mapped, nil, true)
        end
    elseif t.t == "BCLASS" then
        return make_frag(normalize_bclass(t.v), nil, true)
    end

    return make_frag(lua_escape_string(tostring(t.v)), tostring(t.v), true)
end

local function apply_quant_single(frag, quant)
    if not quant then
        return { frag }
    end

    if quant.t == "Q" then
        local q = quant.v
        local unit = frag.single and frag.pat or ("(" .. frag.pat .. ")")
        if q == "*" or q == "+" or q == "?" then
            return { make_frag(unit .. q, nil, false) }
        end
        return nil, "Unknown quantifier: " .. tostring(q)
    end

    if quant.t == "QCOUNT" then
        local m, n = quant.v[1], quant.v[2]
        if n ~= nil and n < m then
            return nil, "Bad counted repeat {n<m}"
        end
        if n ~= nil and n - m > COUNT_MAX then
            return nil, ("Counted repeat too large {%d,%d} (>%d optional)"):format(m, n, COUNT_MAX)
        end

        local unit = frag.single and frag.pat or ("(" .. frag.pat .. ")")
        if n == nil then
            if m == 0 then
                return { make_frag(unit .. "*", nil, false) }
            end
            return { make_frag(string.rep(unit, m) .. unit .. "*", nil, false) }
        end

        local chunks, k = {}, 0
        if m > 0 then
            k = k + 1
            chunks[k] = string.rep(unit, m)
        end
        for _ = 1, (n - m) do
            k = k + 1
            chunks[k] = unit .. "?"
        end
        local plain
        if frag.plain ~= nil and m == n then
            plain = string.rep(frag.plain, m)
        end

        return { make_frag(table.concat(chunks), plain, false) }
    end

    return { frag }
end

local function repeat_alts(alts, times)
    if times == 0 then
        return { EMPTY_FRAG }
    end

    local out = { EMPTY_FRAG }
    for _ = 1, times do
        local next_out, emsg = product(out, alts)
        if not next_out then
            return nil, emsg
        end
        out = next_out
    end

    return out
end

local function apply_quant_group_alts(alts, quant)
    if not quant then
        return alts
    end

    if #alts == 1 then
        return apply_quant_single(alts[1], quant)
    end

    if quant.t == "Q" then
        local q = quant.v
        if q == "?" then
            local out = { EMPTY_FRAG }
            for i = 1, #alts do
                out[#out + 1] = alts[i]
                if #out > BRANCH_MAX then
                    return nil, ("Branch explosion (>%d branches)"):format(BRANCH_MAX)
                end
            end
            return out
        end
        return nil, ("Group alternation with '%s' quantifier is unsupported"):format(tostring(q))
    end

    if quant.t == "QCOUNT" then
        local m, n = quant.v[1], quant.v[2]
        if n ~= nil and n < m then
            return nil, "Bad counted repeat {n<m}"
        end
        if n == nil then
            return nil, "Group alternation with open-ended counted repeat is unsupported"
        end
        if n - m > COUNT_MAX then
            return nil, ("Counted repeat too large {%d,%d} (>%d optional)"):format(m, n, COUNT_MAX)
        end

        local out = {}
        for reps = m, n do
            local chunk, emsg = repeat_alts(alts, reps)
            if not chunk then
                return nil, emsg
            end
            for i = 1, #chunk do
                out[#out + 1] = chunk[i]
                if #out > BRANCH_MAX then
                    return nil, ("Branch explosion (>%d branches)"):format(BRANCH_MAX)
                end
            end
        end

        return out
    end

    return alts
end

local translate_node

local function translate_seq(seq)
    local branches = { EMPTY_FRAG }

    for i = 1, #seq.nodes do
        local node = seq.nodes[i]
        local alts, emsg

        if node.kind == "ATOM" then
            local atom_frag = translate_atom(node)
            alts, emsg = apply_quant_single(atom_frag, node.quant)
        elseif node.kind == "GROUP" then
            local sub_alts
            sub_alts, emsg = translate_node(node.sub)
            if not sub_alts then
                return nil, emsg
            end
            alts, emsg = apply_quant_group_alts(sub_alts, node.quant)
        else
            return nil, "Internal: unknown sequence node kind"
        end

        if not alts then
            return nil, emsg
        end

        local next_branches
        next_branches, emsg = product(branches, alts)
        if not next_branches then
            return nil, emsg
        end
        branches = next_branches
    end

    return branches
end

translate_node = function(node)
    if node.kind == "SEQ" then
        return translate_seq(node)
    end

    if node.kind == "ALT" then
        local out = {}
        for i = 1, #node.branches do
            local branch_alts, emsg = translate_seq(node.branches[i])
            if not branch_alts then
                return nil, emsg
            end
            for j = 1, #branch_alts do
                out[#out + 1] = branch_alts[j]
                if #out > BRANCH_MAX then
                    return nil, ("Branch explosion (>%d branches)"):format(BRANCH_MAX)
                end
            end
        end
        return out
    end

    return nil, "Internal: unknown node kind"
end

local function compile_simple_uncached(vim_pat)
    local toks, tok_err = tokenize_simple(vim_pat)
    if not toks then
        return err("Regex tokenize error: " .. tostring(tok_err))
    end
    local ast, emsg = parse_simple(toks)
    if not ast then
        return err("Regex parse error: " .. emsg)
    end

    local frags, tmsg = translate_node(ast)
    if not frags then
        return err("Regex translate error: " .. tmsg)
    end

    local branches = {}
    local specs = {}
    for i = 1, #frags do
        local f = frags[i]
        branches[i] = f.pat
        specs[i] = {
            pat = f.pat,
            plain = f.plain,
        }
    end

    return {
        mode = "simple",
        branches = branches,
        _branch_specs = specs,
        _single_spec = (#specs == 1) and specs[1] or nil,
        _vim_pat = vim_pat,
        _vm_fallback = nil,
    }
end

-- ============================================================================
-- VM tokenizer/parser/matcher (Stage 3 features)
-- ============================================================================

local VM_CLASS_CODES = {
    d = true, D = true,
    s = true, S = true,
    i = true, I = true,
    w = true, W = true,
    a = true, A = true,
    l = true, L = true,
    u = true, U = true,
    x = true, X = true,
    o = true, O = true,
    h = true, H = true,
    k = true, K = true,
    f = true, F = true,
    p = true, P = true,
}

local function vm_is_magic_char(mode, ch)
    if mode == "verymagic" then
        return ch:match("[%^%$%.%*%+%?%[%]%(%){|}]") ~= nil
    elseif mode == "nomagic" then
        return ch == "^" or ch == "$"
    elseif mode == "verynomagic" then
        return ch == "." or ch == "^" or ch == "$"
    else
        return ch:match("[%.%*%[%]^$]") ~= nil
    end
end

local function vm_parse_quant_fields(min_s, max_s, greedy)
    local min_n = tonumber(min_s)
    local max_n = max_s and tonumber(max_s) or nil

    if min_n and max_n and max_n < min_n then
        return nil, "Bad counted repeat {n<m}"
    end

    if max_n and max_n > VM_MAX_COUNT then
        return nil, ("Counted repeat exceeds max (%d)"):format(VM_MAX_COUNT)
    end

    if min_n and min_n > VM_MAX_COUNT then
        return nil, ("Counted repeat exceeds max (%d)"):format(VM_MAX_COUNT)
    end

    return {
        t = "Q",
        min = min_n or 0,
        max = max_n,
        greedy = greedy,
    }
end

local function vm_tokenize(pat)
    local i, n = 1, #pat
    local mode = "magic"
    local toks, ntoks = {}, 0

    local function peek(k)
        k = k or 0
        local j = i + k
        if j > n then return "" end
        return pat:sub(j, j)
    end

    local function add(t, v)
        ntoks = ntoks + 1
        toks[ntoks] = { t = t, v = v }
    end

    local function add_quant(min_v, max_v, greedy)
        ntoks = ntoks + 1
        toks[ntoks] = { t = "Q", min = min_v, max = max_v, greedy = greedy }
    end

    local function read_bracket_class(start_idx)
        local j = start_idx
        if pat:sub(j, j) ~= "[" then
            return nil, "Internal bracket start mismatch"
        end
        j = j + 1

        local c = pat:sub(j, j)
        if c == "^" then j = j + 1 end
        if pat:sub(j, j) == "]" then j = j + 1 end

        while j <= n do
            local ch = pat:sub(j, j)
            j = j + 1
            if ch == "\\" then
                if j <= n then j = j + 1 end
            elseif ch == "]" then
                return pat:sub(start_idx, j - 1), j
            end
        end

        return nil, "Unterminated [] class"
    end

    local function read_percent_opt(start_idx)
        -- start_idx points at first char after "\\%["
        local j = start_idx
        local buf = {}
        while j <= n do
            local ch = pat:sub(j, j)
            if ch == "\\" and j < n then
                buf[#buf + 1] = pat:sub(j, j + 1)
                j = j + 2
            elseif ch == "]" then
                return table.concat(buf), j + 1
            else
                buf[#buf + 1] = ch
                j = j + 1
            end
        end
        return nil, "Unterminated \\%[]"
    end

    local function try_counted_repeat(escaped)
        local src = pat:sub(i)
        local min_s, max_s, m_all

        if escaped then
            if src:match("^\\{%-}") then
                add_quant(0, nil, false)
                i = i + 4
                return true
            end

            min_s, max_s, m_all = src:match("^\\{%-(%d+),(%d+)}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, max_s, false)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            min_s, m_all = src:match("^\\{%-(%d+),}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, nil, false)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            max_s, m_all = src:match("^\\{%-,(%d+)}()")
            if max_s then
                local q, emsg = vm_parse_quant_fields(0, max_s, false)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            min_s, m_all = src:match("^\\{%-(%d+)}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, min_s, false)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            min_s, max_s, m_all = src:match("^\\{(%d+),(%d+)}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, max_s, true)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            min_s, m_all = src:match("^\\{(%d+),}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, nil, true)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            max_s, m_all = src:match("^\\{,(%d+)}()")
            if max_s then
                local q, emsg = vm_parse_quant_fields(0, max_s, true)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            min_s, m_all = src:match("^\\{(%d+)}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, min_s, true)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end
        else
            min_s, max_s, m_all = src:match("^{(%d+),(%d+)}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, max_s, true)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            min_s, m_all = src:match("^{(%d+),}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, nil, true)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            max_s, m_all = src:match("^{,(%d+)}()")
            if max_s then
                local q, emsg = vm_parse_quant_fields(0, max_s, true)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end

            min_s, m_all = src:match("^{(%d+)}()")
            if min_s then
                local q, emsg = vm_parse_quant_fields(min_s, min_s, true)
                if not q then return nil, emsg end
                add_quant(q.min, q.max, q.greedy)
                i = i + (m_all - 1)
                return true
            end
        end

        return false
    end

    while i <= n do
        local c = peek()

        if c == "\\" then
            local e = peek(1)
            if e == "" then
                add("LIT", "\\")
                i = i + 1
                goto cont
            end

            if e == "v" then
                mode = "verymagic"
                i = i + 2
                goto cont
            end
            if e == "V" then
                mode = "verynomagic"
                i = i + 2
                goto cont
            end
            if e == "m" then
                mode = "magic"
                i = i + 2
                goto cont
            end
            if e == "M" then
                mode = "nomagic"
                i = i + 2
                goto cont
            end

            if e == "n" then
                add("LIT", "\n")
                i = i + 2
                goto cont
            elseif e == "r" then
                add("LIT", "\r")
                i = i + 2
                goto cont
            elseif e == "t" then
                add("LIT", "\t")
                i = i + 2
                goto cont
            elseif e == "e" then
                add("LIT", string.char(27))
                i = i + 2
                goto cont
            end

            if e == "_" then
                local e2 = peek(2)
                if e2 == "[" then
                    local raw, after_or_err = read_bracket_class(i + 2)
                    if not raw then
                        return nil, after_or_err
                    end
                    ntoks = ntoks + 1
                    toks[ntoks] = { t = "BCLASS", raw = raw, allow_nl = true }
                    i = after_or_err
                    goto cont
                end

                if e2 ~= "" then
                    ntoks = ntoks + 1
                    toks[ntoks] = { t = "CLASS", v = "\\_" .. e2 }
                    i = i + 3
                    goto cont
                end

                add("LIT", "_")
                i = i + 2
                goto cont
            end

            if e == "%" then
                local e2 = peek(2)
                if e2 == "(" then
                    ntoks = ntoks + 1
                    toks[ntoks] = { t = "LP", kind = "noncap" }
                    i = i + 3
                    goto cont
                elseif e2 == "[" then
                    local raw, after_or_err = read_percent_opt(i + 3)
                    if not raw then
                        return nil, after_or_err
                    end
                    ntoks = ntoks + 1
                    toks[ntoks] = { t = "PCTOPT", raw = raw }
                    i = after_or_err
                    goto cont
                end
            end

            if e == "z" then
                local e2 = peek(2)
                if e2 == "s" then
                    add("ZS", true)
                    i = i + 3
                    goto cont
                elseif e2 == "e" then
                    add("ZE", true)
                    i = i + 3
                    goto cont
                elseif e2 == "(" then
                    ntoks = ntoks + 1
                    toks[ntoks] = { t = "LP", kind = "ext" }
                    i = i + 3
                    goto cont
                elseif e2:match("%d") then
                    ntoks = ntoks + 1
                    toks[ntoks] = { t = "BREF_EXT", id = tonumber(e2) }
                    i = i + 3
                    goto cont
                end
            end

            if e == "@" then
                local e2 = peek(2)
                if e2 == "=" then
                    add("LOOK", "ahead_pos")
                    i = i + 3
                    goto cont
                elseif e2 == "!" then
                    add("LOOK", "ahead_neg")
                    i = i + 3
                    goto cont
                elseif e2 == "<" then
                    local e3 = peek(3)
                    if e3 == "=" then
                        add("LOOK", "behind_pos")
                        i = i + 4
                        goto cont
                    elseif e3 == "!" then
                        add("LOOK", "behind_neg")
                        i = i + 4
                        goto cont
                    end
                end
            end

            if e == "<" then
                add("WB", "\\<")
                i = i + 2
                goto cont
            elseif e == ">" then
                add("WB", "\\>")
                i = i + 2
                goto cont
            elseif e == "(" then
                ntoks = ntoks + 1
                toks[ntoks] = { t = "LP", kind = "group" }
                i = i + 2
                goto cont
            elseif e == ")" then
                add("RP", true)
                i = i + 2
                goto cont
            elseif e == "|" then
                add("ALT", true)
                i = i + 2
                goto cont
            elseif e == "+" then
                add_quant(1, nil, true)
                i = i + 2
                goto cont
            elseif e == "?" or e == "=" then
                add_quant(0, 1, true)
                i = i + 2
                goto cont
            elseif e == "{" then
                local ok, emsg = try_counted_repeat(true)
                if ok == nil then
                    return nil, emsg
                end
                if ok then goto cont end
                add("LIT", "{")
                i = i + 2
                goto cont
            end

            if VM_CLASS_CODES[e] then
                ntoks = ntoks + 1
                toks[ntoks] = { t = "CLASS", v = "\\" .. e }
                i = i + 2
                goto cont
            end

            add("LIT", e)
            i = i + 2
            goto cont
        end

        if c == "[" and (mode == "magic" or mode == "verymagic") then
            local raw, after_or_err = read_bracket_class(i)
            if not raw then
                return nil, after_or_err
            end
            ntoks = ntoks + 1
            toks[ntoks] = { t = "BCLASS", raw = raw, allow_nl = false }
            i = after_or_err
            goto cont
        end

        if mode == "verymagic" then
            if c == "|" then
                add("ALT", true)
                i = i + 1
                goto cont
            elseif c == "(" then
                ntoks = ntoks + 1
                toks[ntoks] = { t = "LP", kind = "group" }
                i = i + 1
                goto cont
            elseif c == ")" then
                add("RP", true)
                i = i + 1
                goto cont
            elseif c == "+" then
                add_quant(1, nil, true)
                i = i + 1
                goto cont
            elseif c == "?" then
                add_quant(0, 1, true)
                i = i + 1
                goto cont
            elseif c == "{" then
                local ok, emsg = try_counted_repeat(false)
                if ok == nil then
                    return nil, emsg
                end
                if ok then goto cont end
                add("LIT", "{")
                i = i + 1
                goto cont
            end
        end

        if c == "^" and vm_is_magic_char(mode, "^") then
            add("ANCH", "^")
            i = i + 1
            goto cont
        elseif c == "$" and vm_is_magic_char(mode, "$") then
            add("ANCH", "$")
            i = i + 1
            goto cont
        elseif c == "." and vm_is_magic_char(mode, ".") then
            ntoks = ntoks + 1
            toks[ntoks] = { t = "CLASS", v = "." }
            i = i + 1
            goto cont
        elseif c == "*" and vm_is_magic_char(mode, "*") then
            add_quant(0, nil, true)
            i = i + 1
            goto cont
        end

        add("LIT", c)
        i = i + 1

        ::cont::
    end

    ntoks = ntoks + 1
    toks[ntoks] = { t = "EOF", v = nil }

    return toks
end

local function vm_percent_opt_node(raw)
    local atoms = {}
    local i, n = 1, #raw

    while i <= n do
        local c = raw:sub(i, i)
        if c == "\\" and i < n then
            local e = raw:sub(i + 1, i + 1)
            if e == "n" then
                atoms[#atoms + 1] = "\n"
            elseif e == "r" then
                atoms[#atoms + 1] = "\r"
            elseif e == "t" then
                atoms[#atoms + 1] = "\t"
            elseif e == "e" then
                atoms[#atoms + 1] = string.char(27)
            else
                atoms[#atoms + 1] = e
            end
            i = i + 2
        else
            atoms[#atoms + 1] = c
            i = i + 1
        end
    end

    local branches = {}
    -- Prefer longest expansion first so \%[abc] matches greedily when possible.
    for k = #atoms, 0, -1 do
        local nodes = {}
        for j = 1, k do
            nodes[#nodes + 1] = { kind = "LIT", text = atoms[j] }
        end
        branches[#branches + 1] = { kind = "SEQ", nodes = nodes }
    end

    return { kind = "ALT", branches = branches }
end

local function vm_parse(tokens)
    local i, n = 1, #tokens
    local ext_group_count = 0

    local function peek()
        return tokens[i]
    end

    local function consume()
        local t = tokens[i]
        i = i + 1
        return t
    end

    local parse_alt

    local function parse_atom()
        local t = peek()
        if not t then return nil end

        if t.t == "LIT" then
            consume()
            return { kind = "LIT", text = t.v }
        end

        if t.t == "CLASS" then
            consume()
            return { kind = "CLASS", cls = t.v }
        end

        if t.t == "BCLASS" then
            consume()
            return {
                kind = "BCLASS",
                raw = t.raw,
                allow_nl = t.allow_nl and true or false,
            }
        end

        if t.t == "ANCH" then
            consume()
            if t.v == "^" then
                return { kind = "BOL" }
            end
            return { kind = "EOL" }
        end

        if t.t == "WB" then
            consume()
            if t.v == "\\<" then
                return { kind = "WB_START" }
            end
            return { kind = "WB_END" }
        end

        if t.t == "ZS" then
            consume()
            return { kind = "ZS" }
        end

        if t.t == "ZE" then
            consume()
            return { kind = "ZE" }
        end

        if t.t == "BREF_EXT" then
            consume()
            return { kind = "BREF_EXT", id = t.id }
        end

        if t.t == "PCTOPT" then
            consume()
            return vm_percent_opt_node(t.raw)
        end

        if t.t == "LP" then
            local lp = consume()
            local sub, emsg = parse_alt()
            if not sub then return nil, emsg end

            local rp = peek()
            if not rp or rp.t ~= "RP" then
                return nil, "Unmatched ("
            end
            consume()

            if lp.kind == "ext" then
                ext_group_count = ext_group_count + 1
                return {
                    kind = "GROUP",
                    sub = sub,
                    ext_id = ext_group_count,
                }
            end

            return {
                kind = "GROUP",
                sub = sub,
                ext_id = nil,
            }
        end

        if t.t == "RP" then
            return nil, "Unmatched )"
        end

        return nil
    end

    local function parse_piece()
        local atom, emsg = parse_atom()
        if not atom then return nil, emsg end

        while true do
            local t = peek()
            if not t then break end

            if t.t == "Q" then
                consume()
                atom = {
                    kind = "QUANT",
                    sub = atom,
                    min = t.min,
                    max = t.max,
                    greedy = t.greedy,
                }
            elseif t.t == "LOOK" then
                consume()
                atom = {
                    kind = "LOOK",
                    look = t.v,
                    sub = atom,
                }
            else
                break
            end
        end

        return atom
    end

    local function parse_seq()
        local nodes = {}

        while i <= n do
            local t = peek()
            if not t or t.t == "EOF" or t.t == "ALT" or t.t == "RP" then
                break
            end

            local piece, emsg = parse_piece()
            if not piece then
                return nil, emsg or ("Unexpected token: " .. tostring(t.t or "?"))
            end

            nodes[#nodes + 1] = piece
        end

        return { kind = "SEQ", nodes = nodes }
    end

    parse_alt = function()
        local branches = {}

        local seq, emsg = parse_seq()
        if not seq then return nil, emsg end
        branches[#branches + 1] = seq

        while i <= n do
            local t = peek()
            if not t or t.t ~= "ALT" then break end
            consume()
            local nxt, e2 = parse_seq()
            if not nxt then return nil, e2 end
            branches[#branches + 1] = nxt
        end

        if #branches == 1 then
            return branches[1]
        end

        return { kind = "ALT", branches = branches }
    end

    local tree, emsg = parse_alt()
    if not tree then return nil, emsg end

    local trailing = peek()
    if trailing and trailing.t ~= "EOF" then
        if trailing.t == "RP" then
            return nil, "Unmatched )"
        end
        return nil, "Unexpected token: " .. tostring(trailing.t)
    end

    return tree, ext_group_count
end

local function vm_word_char(ch)
    return ch ~= nil and ch:match("[%w_]") ~= nil
end

local function vm_char_equal(a, b, case_sensitive)
    if a == nil or b == nil then return false end
    if case_sensitive then
        return a == b
    end
    return str_lower(a) == str_lower(b)
end

local function vm_match_class_token(code, ch, case_sensitive)
    if not ch then return false end

    if code == "." then
        return ch ~= "\n"
    elseif code == "\\_." then
        return true
    end

    local force_nl = false
    if code:sub(1, 2) == "\\_" then
        force_nl = true
        code = "\\" .. code:sub(3, 3)
    end

    local e = code:sub(2, 2)
    local matched = false

    if e == "d" then
        matched = ch:match("%d") ~= nil
    elseif e == "D" then
        matched = ch:match("%d") == nil
    elseif e == "s" then
        matched = ch:match("%s") ~= nil
    elseif e == "S" then
        matched = ch:match("%s") == nil
    elseif e == "w" then
        matched = ch:match("[%w_]") ~= nil
    elseif e == "W" then
        matched = ch:match("[%w_]") == nil
    elseif e == "i" then
        matched = ch:match("[%w_]") ~= nil
    elseif e == "I" then
        matched = ch:match("[%a_]") ~= nil
    elseif e == "a" then
        matched = ch:match("%a") ~= nil
    elseif e == "A" then
        matched = ch:match("%a") == nil
    elseif e == "l" then
        matched = ch:match("%l") ~= nil
    elseif e == "L" then
        matched = ch:match("%l") == nil
    elseif e == "u" then
        matched = ch:match("%u") ~= nil
    elseif e == "U" then
        matched = ch:match("%u") == nil
    elseif e == "x" then
        matched = ch:match("%x") ~= nil
    elseif e == "X" then
        matched = ch:match("%x") == nil
    elseif e == "o" then
        matched = ch:match("[0-7]") ~= nil
    elseif e == "O" then
        matched = ch:match("[0-7]") == nil
    elseif e == "h" then
        matched = ch:match("[%a_]") ~= nil
    elseif e == "H" then
        matched = ch:match("[%a_]") == nil
    elseif e == "k" then
        matched = ch:match("[%w_]") ~= nil
    elseif e == "K" then
        matched = ch:match("[%w_]") == nil
    elseif e == "f" then
        matched = ch:match("[%a_]") ~= nil
    elseif e == "F" then
        matched = ch:match("[%a_]") == nil
    elseif e == "p" then
        matched = ch:match("%p") ~= nil
    elseif e == "P" then
        matched = ch:match("%p") == nil
    else
        matched = vm_char_equal(ch, e, case_sensitive)
    end

    if force_nl and ch == "\n" then
        return true
    end

    return matched
end

local function vm_parse_bracket(raw)
    local n = #raw
    if n < 2 or raw:sub(1, 1) ~= "[" or raw:sub(n, n) ~= "]" then
        return nil, "Invalid [] class"
    end

    local i = 2
    local neg = false
    local entries = {}

    if raw:sub(i, i) == "^" then
        neg = true
        i = i + 1
    end

    if i <= n - 1 and raw:sub(i, i) == "]" then
        entries[#entries + 1] = { kind = "char", a = "]" }
        i = i + 1
    end

    while i <= n - 1 do
        local ch = raw:sub(i, i)

        local function read_item(idx)
            local c = raw:sub(idx, idx)
            if c == "\\" and idx < (n - 1) then
                local e = raw:sub(idx + 1, idx + 1)
                if VM_CLASS_CODES[e] then
                    return { kind = "class", cls = "\\" .. e }, idx + 2
                elseif e == "n" then
                    return { kind = "char", a = "\n" }, idx + 2
                elseif e == "r" then
                    return { kind = "char", a = "\r" }, idx + 2
                elseif e == "t" then
                    return { kind = "char", a = "\t" }, idx + 2
                elseif e == "e" then
                    return { kind = "char", a = string.char(27) }, idx + 2
                else
                    return { kind = "char", a = e }, idx + 2
                end
            end
            return { kind = "char", a = c }, idx + 1
        end

        local item1, next_i = read_item(i)

        local dash = raw:sub(next_i, next_i)
        if item1.kind == "char" and dash == "-" then
            local tail = next_i + 1
            if tail <= (n - 1) and raw:sub(tail, tail) ~= "]" then
                local item2, after2 = read_item(tail)
                if item2.kind == "char" then
                    entries[#entries + 1] = {
                        kind = "range",
                        a = item1.a,
                        b = item2.a,
                    }
                    i = after2
                    goto continue
                end
            end
        end

        entries[#entries + 1] = item1
        i = next_i

        ::continue::
    end

    return {
        neg = neg,
        entries = entries,
    }
end

local function vm_match_bracket(parsed, ch, case_sensitive)
    if not ch then return false end

    local matched = false
    for i = 1, #parsed.entries do
        local e = parsed.entries[i]
        if e.kind == "char" then
            if vm_char_equal(ch, e.a, case_sensitive) then
                matched = true
                break
            end
        elseif e.kind == "range" then
            local a, b = e.a, e.b
            local cch = ch
            if not case_sensitive then
                a = str_lower(a)
                b = str_lower(b)
                cch = str_lower(cch)
            end
            local bc = string.byte(cch)
            local ba = string.byte(a)
            local bb = string.byte(b)
            if bc and ba and bb then
                if ba <= bb then
                    if bc >= ba and bc <= bb then
                        matched = true
                        break
                    end
                else
                    if bc >= bb and bc <= ba then
                        matched = true
                        break
                    end
                end
            end
        elseif e.kind == "class" then
            if vm_match_class_token(e.cls, ch, case_sensitive) then
                matched = true
                break
            end
        end
    end

    if parsed.neg then
        matched = not matched
    end

    if parsed.allow_nl and ch == "\n" then
        return true
    end

    return matched
end

local function vm_bounds(node)
    local kind = node.kind

    if kind == "LIT" or kind == "CLASS" or kind == "BCLASS" then
        return 1, 1
    end

    if kind == "BREF_EXT" then
        return 0, nil
    end

    if kind == "BOL" or kind == "EOL" or kind == "WB_START" or kind == "WB_END" or
        kind == "ZS" or kind == "ZE" or kind == "LOOK" then
        return 0, 0
    end

    if kind == "GROUP" then
        return vm_bounds(node.sub)
    end

    if kind == "SEQ" then
        local min_sum, max_sum = 0, 0
        for i = 1, #node.nodes do
            local mn, mx = vm_bounds(node.nodes[i])
            min_sum = min_sum + mn
            if max_sum ~= nil then
                if mx == nil then
                    max_sum = nil
                else
                    max_sum = max_sum + mx
                end
            end
        end
        return min_sum, max_sum
    end

    if kind == "ALT" then
        local min_v, max_v
        for i = 1, #node.branches do
            local mn, mx = vm_bounds(node.branches[i])
            if not min_v or mn < min_v then min_v = mn end
            if max_v ~= nil then
                if mx == nil then
                    max_v = nil
                elseif not max_v or mx > max_v then
                    max_v = mx
                end
            elseif max_v == nil and i == 1 then
                max_v = mx
            end
        end
        if min_v == nil then min_v = 0 end
        return min_v, max_v
    end

    if kind == "QUANT" then
        local mn, mx = vm_bounds(node.sub)
        local min_v = (node.min or 0) * mn
        local max_v
        if node.max == nil or mx == nil then
            max_v = nil
        else
            max_v = node.max * mx
        end
        return min_v, max_v
    end

    return 0, nil
end

local function vm_starts_with_bol(node)
    if not node then return false end

    local kind = node.kind
    if kind == "BOL" then
        return true
    end

    if kind == "SEQ" then
        for i = 1, #node.nodes do
            local sub = node.nodes[i]
            if sub.kind == "ZS" or sub.kind == "ZE" or sub.kind == "LOOK" then
                -- skip zero-width wrappers that do not consume position
            else
                return vm_starts_with_bol(sub)
            end
        end
        return false
    end

    if kind == "ALT" then
        if #node.branches == 0 then return false end
        for i = 1, #node.branches do
            if not vm_starts_with_bol(node.branches[i]) then
                return false
            end
        end
        return true
    end

    if kind == "GROUP" then
        return vm_starts_with_bol(node.sub)
    end

    return false
end

local function vm_clone_state(st)
    local ext
    if st.ext then
        ext = {}
        for k, v in pairs(st.ext) do
            ext[k] = v
        end
    end

    return {
        pos = st.pos,
        zs = st.zs,
        ze = st.ze,
        ext = ext,
    }
end

local function vm_clone_ext(ext_in)
    if not ext_in then
        return {}
    end
    local out = {}
    for k, v in pairs(ext_in) do
        out[k] = v
    end
    return out
end

local function vm_make_matcher(ast, hints)
    local lead_literal = hints and hints.lead_literal or nil
    local lead_literal_lower = lead_literal and lead_literal:lower() or nil
    local ic_hay, ic_lower = nil, nil

    local function find_vm(hay, case_sensitive, ext_in, start_pos)
        local n = #hay
        local anchored_bol = vm_starts_with_bol(ast)
        local search_from = tonumber(start_pos) or 1
        if search_from < 1 then
            search_from = 1
        elseif search_from > n + 1 then
            search_from = n + 1
        end

        local steps = 0
        local step_limit = VM_STEPS_BASE + (n * VM_STEPS_PER_CHAR)
        local timed_out = false

        local function step()
            steps = steps + 1
            if steps > step_limit then
                timed_out = true
                return false
            end
            return true
        end

        local eval_node
        local eval_seq

        local function check_lookahead(sub, st)
            local ok = false
            eval_node(sub, vm_clone_state(st), function(_)
                ok = true
                return true
            end)
            return ok
        end

        local function check_lookbehind(sub, st)
            local mn, mx = vm_bounds(sub)
            if mn == nil then mn = 0 end
            local max_back = mx
            if max_back == nil then
                max_back = VM_LOOKBEHIND_MAX
            end

            local start_lo = st.pos - max_back
            if start_lo < 1 then start_lo = 1 end
            local start_hi = st.pos - mn
            if start_hi < 1 then
                return false
            end

            for sp = start_hi, start_lo, -1 do
                local found = false
                local base = {
                    pos = sp,
                    zs = nil,
                    ze = nil,
                    ext = {},
                }
                eval_node(sub, base, function(ns)
                    if ns.pos == st.pos then
                        found = true
                        return true
                    end
                    return false
                end)
                if found then
                    return true
                end
                if timed_out then return false end
            end

            return false
        end

        eval_seq = function(nodes, idx, st, cont)
            if not step() then return false end
            if idx > #nodes then
                return cont(st)
            end

            local node = nodes[idx]
            return eval_node(node, st, function(ns)
                return eval_seq(nodes, idx + 1, ns, cont)
            end)
        end

        eval_node = function(node, st, cont)
            if not step() then return false end

            local kind = node.kind

            if kind == "SEQ" then
                return eval_seq(node.nodes, 1, st, cont)
            end

            if kind == "ALT" then
                for i = 1, #node.branches do
                    if eval_node(node.branches[i], vm_clone_state(st), cont) then
                        return true
                    end
                    if timed_out then return false end
                end
                return false
            end

            if kind == "LIT" then
                local ch = hay:sub(st.pos, st.pos)
                if ch ~= "" and vm_char_equal(ch, node.text, case_sensitive) then
                    local ns = {
                        pos = st.pos + 1,
                        zs = st.zs,
                        ze = st.ze,
                        ext = st.ext,
                    }
                    return cont(ns)
                end
                return false
            end

            if kind == "CLASS" then
                local ch = hay:sub(st.pos, st.pos)
                if ch ~= "" and vm_match_class_token(node.cls, ch, case_sensitive) then
                    local ns = {
                        pos = st.pos + 1,
                        zs = st.zs,
                        ze = st.ze,
                        ext = st.ext,
                    }
                    return cont(ns)
                end
                return false
            end

            if kind == "BCLASS" then
                local ch = hay:sub(st.pos, st.pos)
                if ch ~= "" and vm_match_bracket(node.parsed, ch, case_sensitive) then
                    local ns = {
                        pos = st.pos + 1,
                        zs = st.zs,
                        ze = st.ze,
                        ext = st.ext,
                    }
                    return cont(ns)
                end
                return false
            end

            if kind == "BOL" then
                if st.pos == 1 then
                    return cont(st)
                end
                return false
            end

            if kind == "EOL" then
                if st.pos == n + 1 then
                    return cont(st)
                end
                return false
            end

            if kind == "WB_START" then
                local cur = hay:sub(st.pos, st.pos)
                if cur == "" then cur = nil end
                local prev = nil
                if st.pos > 1 then
                    prev = hay:sub(st.pos - 1, st.pos - 1)
                end
                if vm_word_char(cur) and not vm_word_char(prev) then
                    return cont(st)
                end
                return false
            end

            if kind == "WB_END" then
                local cur = hay:sub(st.pos, st.pos)
                if cur == "" then cur = nil end
                local prev = nil
                if st.pos > 1 then
                    prev = hay:sub(st.pos - 1, st.pos - 1)
                end
                if vm_word_char(prev) and not vm_word_char(cur) then
                    return cont(st)
                end
                return false
            end

            if kind == "ZS" then
                local ns = vm_clone_state(st)
                ns.zs = st.pos
                return cont(ns)
            end

            if kind == "ZE" then
                local ns = vm_clone_state(st)
                ns.ze = st.pos
                return cont(ns)
            end

            if kind == "BREF_EXT" then
                local ext = st.ext or {}
                local cap = ext[node.id]
                if type(cap) ~= "string" then
                    return false
                end

                local clen = #cap
                if clen == 0 then
                    return cont(st)
                end

                local seg = hay:sub(st.pos, st.pos + clen - 1)
                local ok
                if case_sensitive then
                    ok = seg == cap
                else
                    ok = str_lower(seg) == str_lower(cap)
                end

                if ok then
                    local ns = {
                        pos = st.pos + clen,
                        zs = st.zs,
                        ze = st.ze,
                        ext = st.ext,
                    }
                    return cont(ns)
                end
                return false
            end

            if kind == "GROUP" then
                local gstart = st.pos
                return eval_node(node.sub, st, function(ns)
                    if node.ext_id then
                        local ns2 = vm_clone_state(ns)
                        ns2.ext = ns2.ext or {}
                        ns2.ext[node.ext_id] = hay:sub(gstart, ns.pos - 1)
                        return cont(ns2)
                    end
                    return cont(ns)
                end)
            end

            if kind == "LOOK" then
                local passed
                if node.look == "ahead_pos" then
                    passed = check_lookahead(node.sub, st)
                elseif node.look == "ahead_neg" then
                    passed = not check_lookahead(node.sub, st)
                elseif node.look == "behind_pos" then
                    passed = check_lookbehind(node.sub, st)
                else
                    passed = not check_lookbehind(node.sub, st)
                end

                if passed then
                    return cont(st)
                end
                return false
            end

            if kind == "QUANT" then
                local min = node.min or 0
                local max = node.max
                local greedy = node.greedy ~= false

                local function loop(count, cur)
                    if timed_out then return false end

                    if count >= min and not greedy then
                        if cont(cur) then return true end
                        if timed_out then return false end
                    end

                    if max ~= nil and count >= max then
                        if count >= min and greedy then
                            return cont(cur)
                        end
                        return false
                    end

                    local advanced = false
                    local done = false

                    eval_node(node.sub, cur, function(ns)
                        local progressed = ns.pos ~= cur.pos or ns.zs ~= cur.zs or ns.ze ~= cur.ze
                        if not progressed then
                            return false
                        end

                        advanced = true
                        if loop(count + 1, ns) then
                            done = true
                            return true
                        end
                        return false
                    end)

                    if done then return true end
                    if timed_out then return false end

                    if count >= min and greedy then
                        if cont(cur) then return true end
                        if timed_out then return false end
                    end

                    if not advanced then
                        return false
                    end
                    return false
                end

                return loop(0, st)
            end

            return false
        end

        local function run_from(start_pos)
            local init = {
                pos = start_pos,
                zs = nil,
                ze = nil,
                ext = vm_clone_ext(ext_in),
            }

            local winner = nil
            eval_node(ast, init, function(ns)
                winner = ns
                return true
            end)

            if winner then
                local s = winner.zs or start_pos
                local e
                if winner.ze ~= nil then
                    e = winner.ze - 1
                else
                    e = winner.pos - 1
                end
                if e < s - 1 then
                    e = s - 1
                end
                return s, e, winner.ext
            end

            return nil, nil, nil
        end

        if anchored_bol then
            if search_from > 1 then
                return nil, nil, nil
            end
            local s, e, caps = run_from(1)
            if timed_out then
                return nil, nil, nil, "Regex VM timeout"
            end
            return s, e, caps
        end

        if lead_literal and lead_literal ~= "" then
            local scan_hay = hay
            local needle = lead_literal

            if not case_sensitive then
                if ic_hay == hay and ic_lower ~= nil then
                    scan_hay = ic_lower
                else
                    scan_hay = hay:lower()
                    ic_hay = hay
                    ic_lower = scan_hay
                end
                needle = lead_literal_lower
            end

            local from = search_from
            while true do
                local pos = str_find(scan_hay, needle, from, true)
                if not pos then
                    break
                end

                local s, e, caps = run_from(pos)
                if timed_out then
                    return nil, nil, nil, "Regex VM timeout"
                end
                if s then
                    return s, e, caps
                end

                from = pos + 1
            end

            return nil, nil, nil
        end

        for sp = search_from, n + 1 do
            local s, e, caps = run_from(sp)
            if timed_out then
                return nil, nil, nil, "Regex VM timeout"
            end
            if s then
                return s, e, caps
            end
        end

        return nil, nil, nil
    end

    return find_vm
end

local function vm_prepare_bclasses(node)
    local kind = node.kind

    if kind == "BCLASS" then
        local parsed, emsg = vm_parse_bracket(node.raw)
        if not parsed then
            return nil, emsg
        end
        parsed.allow_nl = node.allow_nl and true or false
        node.parsed = parsed
        return true
    end

    if kind == "SEQ" then
        for i = 1, #node.nodes do
            local ok, emsg = vm_prepare_bclasses(node.nodes[i])
            if not ok then return nil, emsg end
        end
        return true
    end

    if kind == "ALT" then
        for i = 1, #node.branches do
            local ok, emsg = vm_prepare_bclasses(node.branches[i])
            if not ok then return nil, emsg end
        end
        return true
    end

    if kind == "GROUP" or kind == "QUANT" or kind == "LOOK" then
        return vm_prepare_bclasses(node.sub)
    end

    return true
end

local function vm_common_prefix(a, b)
    local na = #a
    local nb = #b
    local n = (na < nb) and na or nb
    local i = 1
    while i <= n do
        if a:sub(i, i) ~= b:sub(i, i) then
            break
        end
        i = i + 1
    end
    return a:sub(1, i - 1)
end

local function vm_is_zero_width_kind(kind)
    return kind == "BOL" or kind == "EOL" or kind == "WB_START" or kind == "WB_END" or
        kind == "ZS" or kind == "ZE" or kind == "LOOK"
end

local function vm_extract_lead_literal(node, depth)
    depth = depth or 0
    if depth > 24 or not node then
        return nil
    end

    local kind = node.kind

    if kind == "LIT" then
        return node.text
    end

    if kind == "GROUP" then
        return vm_extract_lead_literal(node.sub, depth + 1)
    end

    if kind == "ALT" then
        local common = nil
        for i = 1, #node.branches do
            local lit = vm_extract_lead_literal(node.branches[i], depth + 1)
            if not lit or lit == "" then
                return nil
            end
            if not common then
                common = lit
            else
                common = vm_common_prefix(common, lit)
                if common == "" then
                    return nil
                end
            end
        end
        return common
    end

    if kind == "QUANT" then
        if (node.min or 0) <= 0 then
            return nil
        end
        return vm_extract_lead_literal(node.sub, depth + 1)
    end

    if kind == "SEQ" then
        local parts = {}
        local started = false
        local total_len = 0

        for i = 1, #node.nodes do
            local sub = node.nodes[i]
            if not vm_is_zero_width_kind(sub.kind) then
                local lit = vm_extract_lead_literal(sub, depth + 1)
                if not lit or lit == "" then
                    if not started then
                        return nil
                    end
                    break
                end

                started = true
                if total_len < VM_PREFILTER_LITERAL_MAX then
                    local room = VM_PREFILTER_LITERAL_MAX - total_len
                    if #lit > room then
                        lit = lit:sub(1, room)
                    end
                    parts[#parts + 1] = lit
                    total_len = total_len + #lit
                end

                -- Stop once the sequence moves away from deterministic literal atoms.
                if sub.kind ~= "LIT" then
                    break
                end

                if total_len >= VM_PREFILTER_LITERAL_MAX then
                    break
                end
            end
        end

        if not started or #parts == 0 then
            return nil
        end

        return table.concat(parts)
    end

    return nil
end

compile_vm_uncached = function(vim_pat)
    local toks, tmsg = vm_tokenize(vim_pat)
    if not toks then
        return err("Regex VM tokenize error: " .. tostring(tmsg))
    end

    local ast, ext_count_or_err = vm_parse(toks)
    if not ast then
        return err("Regex VM parse error: " .. tostring(ext_count_or_err))
    end

    local ok, emsg = vm_prepare_bclasses(ast)
    if not ok then
        return err("Regex VM class error: " .. tostring(emsg))
    end

    local lead_lit = vm_extract_lead_literal(ast)
    if lead_lit == "" then
        lead_lit = nil
    end
    local prefilter = {
        lead_literal = lead_lit,
    }

    local vm_find = vm_make_matcher(ast, prefilter)

    return {
        mode = "vm",
        ast = ast,
        ext_group_count = ext_count_or_err,
        prefilter = prefilter,
        _vm_find = vm_find,
    }
end

local VM_TRIGGER_LITS = {
    "\\@=",
    "\\@!",
    "\\@<=",
    "\\@<!",
    "\\zs",
    "\\ze",
    "\\z",
    "\\%(",
    "\\%[",
    "\\_",
    "\\=",
    "\\{-",
}

local function pattern_needs_vm(pat)
    for i = 1, #VM_TRIGGER_LITS do
        if pat:find(VM_TRIGGER_LITS[i], 1, true) then
            return true
        end
    end
    return false
end

local function compile_uncached(vim_pat)
    local must_vm = pattern_needs_vm(vim_pat)

    if not must_vm then
        local simple, serr = compile_simple_uncached(vim_pat)
        if simple then
            return simple
        end

        local vm, verr = compile_vm_uncached(vim_pat)
        if vm then
            return vm
        end

        return nil, ("%s; VM fallback failed: %s"):format(tostring(serr), tostring(verr))
    end

    local vm, verr = compile_vm_uncached(vim_pat)
    if vm then
        return vm
    end

    return nil, verr
end

local function normalize_engine_selector(vim_pat)
    -- \%#=N selects Vim's regexp engine (old/NFA/auto). It is zero-width and
    -- does not affect match semantics for this engine, so strip it.
    return (tostring(vim_pat or ""):gsub("\\%%#=%d+", ""))
end

local function compile(vim_pat)
    local pat = normalize_engine_selector(vim_pat)

    local cached = cache_get(pat)
    if cached then
        return cached
    end

    local compiled, emsg = compile_uncached(pat)
    if not compiled then
        return nil, emsg
    end

    cache_put(pat, compiled)
    return compiled
end

R.compile = compile
R.compile_vm = function(vim_pat)
    local pat = normalize_engine_selector(vim_pat)
    return compile_vm_uncached(pat)
end

-- ============================================================================
-- Matching entrypoints
-- ============================================================================

local function fold_case(pat)
    local out, i, n = {}, 1, #pat
    while i <= n do
        local c = pat:sub(i, i)
        if c == "%" then
            out[#out + 1] = "%" .. (pat:sub(i + 1, i + 1) or "")
            i = i + 2
        else
            out[#out + 1] = c:lower()
            i = i + 1
        end
    end
    return table.concat(out)
end

local function get_specs(compiled)
    local specs = compiled._branch_specs
    if specs then
        return specs
    end

    specs = {}
    local branches = compiled.branches or {}
    for i = 1, #branches do
        specs[i] = { pat = branches[i], plain = nil }
    end
    compiled._branch_specs = specs
    return specs
end

local function get_folded_specs(compiled)
    if compiled._folded_specs then
        return compiled._folded_specs
    end

    local src = get_specs(compiled)
    local folded = {}
    for i = 1, #src do
        local b = src[i]
        if b.plain ~= nil then
            folded[i] = { plain = b.plain:lower(), pat = nil }
        else
            folded[i] = { plain = nil, pat = fold_case(b.pat) }
        end
    end

    compiled._folded_specs = folded
    compiled._folded_single = (#folded == 1) and folded[1] or nil
    return folded
end

local function find_in_specs(hay, specs, start_pos)
    local from = start_pos or 1
    local best_s, best_e = nil, nil
    for i = 1, #specs do
        local spec = specs[i]
        local s, e
        if spec.plain ~= nil then
            s, e = str_find(hay, spec.plain, from, true)
        else
            s, e = str_find(hay, spec.pat, from)
        end
        if s then
            if not best_s or s < best_s then
                best_s, best_e = s, e
            end
        end
    end
    return best_s, best_e
end

local function get_simple_vm_fallback(compiled)
    local cached = compiled._vm_fallback
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local source_pat = compiled._vim_pat
    if not source_pat or type(compile_vm_uncached) ~= "function" then
        compiled._vm_fallback = false
        return nil
    end

    local vm_compiled = select(1, compile_vm_uncached(source_pat))
    if not vm_compiled then
        compiled._vm_fallback = false
        return nil
    end

    local lead = vm_compiled.prefilter and vm_compiled.prefilter.lead_literal
    if not lead or #lead < SIMPLE_VM_FALLBACK_MIN_LEAD then
        compiled._vm_fallback = false
        return nil
    end

    compiled._vm_fallback = vm_compiled
    return vm_compiled
end

function R.match(text, vim_pat, case_sensitive)
    local compiled, emsg = compile(vim_pat)
    if not compiled then
        return false, emsg
    end
    return R.match_compiled(text, compiled, case_sensitive)
end

function R.find(text, vim_pat, case_sensitive)
    local compiled, emsg = compile(vim_pat)
    if not compiled then
        return nil, nil, emsg
    end
    return R.find_compiled(text, compiled, case_sensitive)
end

function R.match_compiled(text, compiled, case_sensitive)
    local s = R.find_compiled(text, compiled, case_sensitive)
    return s ~= nil
end

function R.find_compiled_with_caps(text, compiled, case_sensitive, ext_in, start_pos)
    local hay = tostring(text or "")
    local from = tonumber(start_pos) or 1
    if from < 1 then from = 1 end
    if from > #hay + 1 then
        return nil, nil, nil, nil
    end

    if compiled.mode == "vm" then
        local s, e, caps, emsg = compiled._vm_find(hay, case_sensitive ~= false, ext_in, from)
        return s, e, caps, emsg
    end

    if case_sensitive ~= false then
        local specs = get_specs(compiled)
        local best_s, best_e, best_caps = nil, nil, nil
        for i = 1, #specs do
            local spec = specs[i]
            if spec.plain ~= nil then
                local s, e = str_find(hay, spec.plain, from, true)
                if s and (not best_s or s < best_s) then
                    best_s, best_e, best_caps = s, e, nil
                end
            else
                local found = { str_find(hay, spec.pat, from) }
                local s, e = found[1], found[2]
                if s and (not best_s or s < best_s) then
                    local caps = {}
                    for j = 3, #found do
                        caps[#caps + 1] = found[j]
                    end
                    best_s, best_e, best_caps = s, e, caps
                end
            end
        end
        return best_s, best_e, best_caps, nil
    end

    local s, e = R.find_compiled(hay, compiled, case_sensitive, from)
    return s, e, nil, nil
end

function R.find_compiled(text, compiled, case_sensitive, start_pos)
    local hay = tostring(text or "")
    local from = tonumber(start_pos) or 1
    if from < 1 then from = 1 end
    if from > #hay + 1 then
        return nil, nil
    end

    if compiled.mode == "vm" then
        local s, e, _, emsg = compiled._vm_find(hay, case_sensitive ~= false, nil, from)
        return s, e, emsg
    end

    if case_sensitive then
        local single = compiled._single_spec
        if single then
            if from == 1 and single.plain == nil and #hay >= SIMPLE_VM_FALLBACK_MIN_HAY then
                local vm_fallback = get_simple_vm_fallback(compiled)
                if vm_fallback then
                    local lead = vm_fallback.prefilter and vm_fallback.prefilter.lead_literal
                    if lead and lead ~= "" then
                        local first
                        if compiled._cs_lead_hay == hay and compiled._cs_lead_lit == lead then
                            first = compiled._cs_lead_pos
                        else
                            first = str_find(hay, lead, 1, true)
                            compiled._cs_lead_hay = hay
                            compiled._cs_lead_lit = lead
                            compiled._cs_lead_pos = first
                        end

                        if not first then
                            return nil, nil
                        end
                        if first >= SIMPLE_VM_FALLBACK_MIN_POS then
                            local s, e, _, emsg = vm_fallback._vm_find(hay, true, nil)
                            return s, e, emsg
                        end
                    end
                end
            end

            if single.plain ~= nil then
                return str_find(hay, single.plain, from, true)
            end
            return str_find(hay, single.pat, from)
        end
        return find_in_specs(hay, get_specs(compiled), from)
    end

    local folded = get_folded_specs(compiled)

    local lowered
    if compiled._ic_hay == hay and compiled._ic_lower ~= nil then
        lowered = compiled._ic_lower
    else
        lowered = hay:lower()
        compiled._ic_hay = hay
        compiled._ic_lower = lowered
    end

    local f_single = compiled._folded_single
    if f_single then
        if f_single.plain ~= nil then
            return str_find(lowered, f_single.plain, from, true)
        end
        return str_find(lowered, f_single.pat, from)
    end

    return find_in_specs(lowered, folded, from)
end

-- ============================================================================
-- Syntax offset integration hooks (Stage 3 hand-off to runtime stage)
-- ============================================================================

local OFFSET_KEYS = {
    ms = true, me = true,
    hs = true, he = true,
    rs = true, re = true,
    lc = true,
}

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_csv(raw)
    local out = {}
    for part in tostring(raw or ""):gmatch("[^,]+") do
        local v = trim(part)
        if v ~= "" then out[#out + 1] = v end
    end
    return out
end

local function parse_offset_atom(v)
    v = trim(v)
    if v == "" then return nil end

    local anchor, delta = v:match("^([se])([%+%-]%d+)$")
    if anchor then
        return { anchor = anchor, delta = tonumber(delta) or 0, raw = v }
    end

    if v == "s" or v == "e" then
        return { anchor = v, delta = 0, raw = v }
    end

    local num = tonumber(v)
    if num then
        return { anchor = "s", delta = num, raw = v, absolute = true }
    end

    return { raw = v }
end

function R.parse_syntax_offsets(raw)
    local offsets = {}
    local parts = split_csv(raw)

    for i = 1, #parts do
        local tok = parts[i]
        local k, v = tok:match("^([%a][%a])=(.+)$")
        if k then
            k = k:lower()
            if OFFSET_KEYS[k] then
                if k == "lc" then
                    local n = tonumber(v)
                    offsets[k] = (n ~= nil) and n or trim(v)
                else
                    offsets[k] = parse_offset_atom(v)
                end
            end
        end
    end

    return offsets
end

function R.apply_syntax_offsets(match_start, match_end, offsets)
    offsets = offsets or {}

    local function eval_atom(atom)
        if type(atom) ~= "table" then return nil end
        if atom.absolute then
            return atom.delta
        end
        if atom.anchor == "s" then
            return match_start + (atom.delta or 0)
        elseif atom.anchor == "e" then
            return match_end + (atom.delta or 0)
        end
        return nil
    end

    local out = {
        match_start = match_start,
        match_end = match_end,
        ms = eval_atom(offsets.ms),
        me = eval_atom(offsets.me),
        hs = eval_atom(offsets.hs),
        he = eval_atom(offsets.he),
        rs = eval_atom(offsets.rs),
        re = eval_atom(offsets.re),
        lc = offsets.lc,
    }

    local lc = tonumber(offsets.lc)
    if lc and out.ms == nil then
        out.ms = match_start + lc
    end

    return out
end

return R
