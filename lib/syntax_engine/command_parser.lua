local CommandParser = {}

local ITEM_FLAGS = {
    conceal = true,
    concealends = true,
    contained = true,
    display = true,
    excludenl = true,
    extend = true,
    fold = true,
    keepend = true,
    oneline = true,
    skipempty = true,
    skipnl = true,
    skipwhite = true,
    transparent = true,
}

local LIST_VALUE_KEYS = {
    add = true,
    contains = true,
    containedin = true,
    nextgroup = true,
    remove = true,
}

local SINGLE_VALUE_KEYS = {
    cchar = true,
    matchgroup = true,
}

local SYNC_CONTROL = {
    ccomment = true,
    clear = true,
    fromstart = true,
    linecont = true,
    match = true,
    region = true,
}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_assign(token)
    token = tostring(token or "")
    if token == "" then return nil, nil end

    -- Quoted regex/pattern tokens can legitimately contain '=' (e.g. \=) and
    -- must not be treated as key=value option assignments.
    local n = #token
    local q = token:sub(1, 1)
    if n >= 2 and (q == "'" or q == "\"") and token:sub(n, n) == q then
        return nil, nil
    end

    local p = token:find("=", 1, true)
    if not p or p <= 1 then return nil, nil end

    local key = token:sub(1, p - 1)
    if not key:match("^[A-Za-z][A-Za-z0-9_]*$") then
        return nil, nil
    end

    return key:lower(), token:sub(p + 1)
end

local function parse_csv(raw)
    local out, buf = {}, {}
    local i, n = 1, #raw
    while i <= n do
        local c = raw:sub(i, i)
        if c == "\\" and i < n then
            buf[#buf + 1] = raw:sub(i + 1, i + 1)
            i = i + 2
        elseif c == "," then
            local v = trim(table.concat(buf))
            if v ~= "" then out[#out + 1] = v end
            buf = {}
            i = i + 1
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    local v = trim(table.concat(buf))
    if v ~= "" then out[#out + 1] = v end
    return out
end

local function tokenize(raw)
    local out = {}
    local i, n = 1, #raw

    local function scan_quoted(pos, q)
        local j = pos + 1
        local esc = false
        local in_class = false
        local class_count = 0
        local class_leading_caret = false
        while j <= n do
            local ch = raw:sub(j, j)
            if esc then
                esc = false
                if in_class then
                    class_count = class_count + 1
                end
            elseif ch == "\\" then
                esc = true
            elseif in_class then
                class_count = class_count + 1
                if class_count == 1 and ch == "^" then
                    class_leading_caret = true
                elseif ch == "]" then
                    if class_count > 1 and not (class_leading_caret and class_count == 2) then
                        in_class = false
                    end
                end
            elseif ch == "[" then
                in_class = true
                class_count = 0
                class_leading_caret = false
            elseif ch == q then
                return j
            end
            j = j + 1
        end
        return nil
    end

    local function scan_delimited(pos, d)
        local j = pos + 1
        local esc = false
        local in_class = false
        local class_count = 0
        local class_leading_caret = false
        while j <= n do
            local ch = raw:sub(j, j)
            if esc then
                esc = false
                if in_class then
                    class_count = class_count + 1
                end
            elseif ch == "\\" then
                esc = true
            elseif in_class then
                class_count = class_count + 1
                if class_count == 1 and ch == "^" then
                    class_leading_caret = true
                elseif ch == "]" then
                    if class_count > 1 and not (class_leading_caret and class_count == 2) then
                        in_class = false
                    end
                end
            elseif ch == "[" then
                in_class = true
                class_count = 0
                class_leading_caret = false
            elseif ch == d then
                return j
            end
            j = j + 1
        end
        return nil
    end

    while i <= n do
        while i <= n and raw:sub(i, i):match("%s") do
            i = i + 1
        end
        if i > n then break end

        local c = raw:sub(i, i)
        if c == "'" or c == "\"" then
            local j = scan_quoted(i, c)
            if j and j <= n then
                out[#out + 1] = raw:sub(i, j)
                i = j + 1
            else
                out[#out + 1] = raw:sub(i)
                break
            end
        else
            -- Keep key=VALUE tokens intact when VALUE is a quoted string
            -- or delimiter-form pattern that may contain whitespace.
            local k = i
            if raw:sub(k, k):match("[A-Za-z]") then
                k = k + 1
                while k <= n and raw:sub(k, k):match("[A-Za-z0-9_]") do
                    k = k + 1
                end

                if raw:sub(k, k) == "=" then
                    local vpos = k + 1
                    local v = raw:sub(vpos, vpos)
                    local close = nil
                    if v == "'" or v == "\"" then
                        close = scan_quoted(vpos, v)
                    elseif v ~= "" and not v:match("%s") and not v:match("[%w_]") then
                        close = scan_delimited(vpos, v)
                    end

                    if close then
                        local j = close + 1
                        while j <= n and not raw:sub(j, j):match("%s") do
                            j = j + 1
                        end
                        out[#out + 1] = raw:sub(i, j - 1)
                        i = j
                        goto continue
                    end
                end
            end

            local j = i
            while j <= n and not raw:sub(j, j):match("%s") do
                j = j + 1
            end
            out[#out + 1] = raw:sub(i, j - 1)
            i = j
        end
        ::continue::
    end

    return out
end

local function normalize_assignments(tokens)
    local out = {}
    local i = 1
    while i <= #tokens do
        local tok = tokens[i]
        if tokens[i + 1] == "=" and tokens[i + 2] then
            out[#out + 1] = tok .. "=" .. tokens[i + 2]
            i = i + 3
        elseif tok:sub(-1) == "=" and tokens[i + 1] then
            out[#out + 1] = tok .. tokens[i + 1]
            i = i + 2
        elseif tokens[i + 1] and tokens[i + 1]:sub(1, 1) == "=" and #tokens[i + 1] > 1 and not tok:find("=", 1, true) then
            out[#out + 1] = tok .. tokens[i + 1]
            i = i + 2
        else
            out[#out + 1] = tok
            i = i + 1
        end
    end
    return out
end

local function new_options()
    return {
        flags = {},
        attrs = {},
        unknown = {},
    }
end

local function parse_common_option(token, opts)
    local low = token:lower()
    if ITEM_FLAGS[low] then
        opts.flags[low] = true
        return true
    end

    local key, value = split_assign(token)
    if not key then
        return false
    end

    if LIST_VALUE_KEYS[key] then
        opts[key] = parse_csv(value)
        return true
    end

    if SINGLE_VALUE_KEYS[key] then
        opts[key] = value
        return true
    end

    opts.attrs[key] = value
    return true
end

local function expand_optional_keyword(word, out, seen)
    local s, e = word:find("%b[]")
    if not s then
        if word ~= "" and not seen[word] then
            seen[word] = true
            out[#out + 1] = word
        end
        return
    end

    local inside = word:sub(s + 1, e - 1)
    local prefix = word:sub(1, s - 1)
    local suffix = word:sub(e + 1)

    expand_optional_keyword(prefix .. suffix, out, seen)
    expand_optional_keyword(prefix .. inside .. suffix, out, seen)
end

local function parse_keyword(tokens, raw)
    local cmd = {
        kind = "keyword",
        raw = raw,
        group = tokens[2] or "",
        options = new_options(),
        keywords = {},
    }

    local seen = {}
    for i = 3, #tokens do
        local tok = tokens[i]
        if not parse_common_option(tok, cmd.options) then
            expand_optional_keyword(tok, cmd.keywords, seen)
        end
    end

    return cmd
end

local function parse_match(tokens, raw)
    local cmd = {
        kind = "match",
        raw = raw,
        group = tokens[2] or "",
        options = new_options(),
        pattern = nil,
    }

    for i = 3, #tokens do
        local tok = tokens[i]
        if not cmd.pattern then
            if not parse_common_option(tok, cmd.options) then
                cmd.pattern = tok
            end
        elseif not parse_common_option(tok, cmd.options) then
            cmd.options.unknown[#cmd.options.unknown + 1] = tok
        end
    end

    return cmd
end

local function parse_region_body(tokens, from_idx, options)
    local patterns = {
        start = {},
        skip = {},
        ["end"] = {},
    }

    local active_matchgroup = nil
    local pending_excludenl = false

    for i = from_idx, #tokens do
        local tok = tokens[i]
        local key, value = split_assign(tok)

        if key == "matchgroup" then
            active_matchgroup = value
            options.matchgroup = value
        elseif tok:lower() == "excludenl" then
            options.flags.excludenl = true
            pending_excludenl = true
        elseif key == "start" or key == "skip" or key == "end" then
            local spec = { pattern = value }
            if active_matchgroup then spec.matchgroup = active_matchgroup end
            if pending_excludenl then
                spec.excludenl = true
                pending_excludenl = false
            end
            patterns[key][#patterns[key] + 1] = spec
        elseif not parse_common_option(tok, options) then
            options.unknown[#options.unknown + 1] = tok
        end
    end

    return patterns
end

local function parse_region(tokens, raw)
    local cmd = {
        kind = "region",
        raw = raw,
        group = tokens[2] or "",
        options = new_options(),
    }
    cmd.patterns = parse_region_body(tokens, 3, cmd.options)
    return cmd
end

local function parse_cluster(tokens, raw)
    local cmd = {
        kind = "cluster",
        raw = raw,
        name = tokens[2] or "",
        contains = nil,
        add = nil,
        remove = nil,
        attrs = {},
        unknown = {},
    }

    for i = 3, #tokens do
        local key, value = split_assign(tokens[i])
        if key == "contains" then
            cmd.contains = parse_csv(value)
        elseif key == "add" then
            cmd.add = parse_csv(value)
        elseif key == "remove" then
            cmd.remove = parse_csv(value)
        elseif key then
            cmd.attrs[key] = value
        else
            cmd.unknown[#cmd.unknown + 1] = tokens[i]
        end
    end

    return cmd
end

local function parse_include(tokens, raw)
    local cmd = {
        kind = "include",
        raw = raw,
        cluster = nil,
        file = "",
    }

    local idx = 2
    if tokens[idx] and tokens[idx]:sub(1, 1) == "@" then
        cmd.cluster = tokens[idx]:sub(2)
        idx = idx + 1
    end

    if idx <= #tokens then
        cmd.file = table.concat(tokens, " ", idx)
    end

    return cmd
end

local function parse_clear_or_list(kind, tokens, raw)
    local cmd = {
        kind = kind,
        raw = raw,
        groups = {},
        clusters = {},
    }

    for i = 2, #tokens do
        local tok = tokens[i]
        if tok:sub(1, 1) == "@" then
            local cname = tok:sub(2)
            if cname ~= "" then cmd.clusters[#cmd.clusters + 1] = cname end
        elseif tok ~= "" then
            cmd.groups[#cmd.groups + 1] = tok
        end
    end

    if #cmd.groups == 0 and #cmd.clusters == 0 then
        cmd.scope = "all"
    else
        cmd.scope = "named"
    end

    return cmd
end

local function is_sync_assignment(tok)
    local key = split_assign(tok)
    return key == "linebreaks" or key == "lines" or key == "maxlines" or key == "minlines"
end

local function is_sync_control_token(tok)
    local low = tok:lower()
    if SYNC_CONTROL[low] then
        return true
    end
    return is_sync_assignment(tok)
end

local function parse_sync_item(tokens, start_idx)
    local item_kind = tokens[start_idx]:lower()
    local item = {
        kind = item_kind == "match" and "sync_match" or "sync_region",
        sync_group = nil,
        sync_point = nil,
        target_group = nil,
        pattern = nil,
        patterns = nil,
        options = new_options(),
    }

    local i = start_idx + 1
    if i <= #tokens then
        item.sync_group = tokens[i]
        i = i + 1
    end

    local mode = tokens[i] and tokens[i]:lower() or ""
    if mode == "grouphere" or mode == "groupthere" then
        item.sync_point = mode
        item.target_group = tokens[i + 1] or "NONE"
        i = i + 2
    end

    if item.kind == "sync_match" then
        while i <= #tokens do
            local tok = tokens[i]
            if not item.pattern then
                if not parse_common_option(tok, item.options) then
                    item.pattern = tok
                end
            elseif not parse_common_option(tok, item.options) then
                item.options.unknown[#item.options.unknown + 1] = tok
            end
            i = i + 1
        end
    else
        item.patterns = parse_region_body(tokens, i, item.options)
    end

    return item, #tokens + 1
end

local function parse_sync(tokens, raw)
    local cmd = {
        kind = "sync",
        raw = raw,
        settings = {},
        action = nil,
        clear_names = {},
        items = {},
        unknown = {},
    }

    local i = 2
    while i <= #tokens do
        local tok = tokens[i]
        local low = tok:lower()
        local key, value = split_assign(tok)

        if low == "clear" then
            cmd.action = "clear"
            i = i + 1
            while i <= #tokens do
                cmd.clear_names[#cmd.clear_names + 1] = tokens[i]
                i = i + 1
            end
            break
        elseif low == "fromstart" then
            cmd.settings.fromstart = true
            i = i + 1
        elseif low == "ccomment" then
            cmd.settings.ccomment = true
            i = i + 1
            if i <= #tokens and not is_sync_control_token(tokens[i]) then
                cmd.settings.ccomment_group = tokens[i]
                i = i + 1
            end
        elseif low == "linecont" then
            cmd.settings.linecont = tokens[i + 1] or ""
            i = i + 2
        elseif key == "lines" then
            cmd.settings.minlines = tonumber(value) or value
            i = i + 1
        elseif key == "minlines" or key == "maxlines" or key == "linebreaks" then
            cmd.settings[key] = tonumber(value) or value
            i = i + 1
        elseif low == "match" or low == "region" then
            local item, next_idx = parse_sync_item(tokens, i)
            cmd.items[#cmd.items + 1] = item
            i = next_idx
        else
            cmd.unknown[#cmd.unknown + 1] = tok
            i = i + 1
        end
    end

    return cmd
end

function CommandParser.parse(raw_cmd)
    local raw = trim(tostring(raw_cmd or ""))
    if raw == "" then
        return {
            kind = "list",
            raw = "",
            groups = {},
            clusters = {},
            scope = "all",
        }
    end

    local tokens = normalize_assignments(tokenize(raw))
    if #tokens == 0 then
        return {
            kind = "list",
            raw = "",
            groups = {},
            clusters = {},
            scope = "all",
        }
    end

    local head = tokens[1]:lower()
    if head == "case" then
        return {
            kind = "case",
            raw = raw,
            mode = tokens[2] and tokens[2]:lower() or nil,
        }
    elseif head == "iskeyword" then
        local arg = tokens[2]
        if not arg then
            return { kind = "iskeyword", raw = raw, query = true }
        end
        if arg:lower() == "clear" then
            return { kind = "iskeyword", raw = raw, clear = true }
        end
        return {
            kind = "iskeyword",
            raw = raw,
            value = table.concat(tokens, " ", 2),
        }
    elseif head == "keyword" then
        return parse_keyword(tokens, raw)
    elseif head == "match" then
        return parse_match(tokens, raw)
    elseif head == "region" then
        return parse_region(tokens, raw)
    elseif head == "cluster" then
        return parse_cluster(tokens, raw)
    elseif head == "include" then
        return parse_include(tokens, raw)
    elseif head == "sync" then
        return parse_sync(tokens, raw)
    elseif head == "clear" then
        return parse_clear_or_list("clear", tokens, raw)
    elseif head == "list" then
        return parse_clear_or_list("list", tokens, raw)
    end

    return {
        kind = "unknown",
        raw = raw,
        command = head,
        tokens = tokens,
    }
end

return CommandParser
