return function(s, sep, opts, old_trimempty)
    if type(s) ~= "string" then error("split: s must be a string", 2) end
    if sep == nil then error("split: sep must be provided", 2) end

    -- Options: table {plain?, trimempty?} or legacy (opts=boolean plain, old_trimempty=boolean)
    local plain, trimempty
    if type(opts) == "table" then
        plain     = not not opts.plain
        trimempty = not not opts.trimempty
    else
        -- Legacy signature
        plain     = not not opts
        trimempty = not not old_trimempty
    end

    -- Empty separator: split into individual bytes (Neovim does not promise UTF-8 codepoint splitting)
    if sep == "" then
        local out = {}
        for i = 1, #s do out[#out + 1] = s:sub(i, i) end
        if trimempty then
            while out[1] == "" do table.remove(out, 1) end
            while out[#out] == "" do table.remove(out) end
        end
        return out
    end

    -- Eager split using Lua patterns by default; literal search if plain=true
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local s1, e1 = string.find(s, sep, i, plain) -- Lua pattern unless plain=true
        if not s1 then
            out[#out + 1] = s:sub(i)
            break
        end
        out[#out + 1] = s:sub(i, s1 - 1)

        -- Guard against zero-width matches to avoid infinite loops (Lua: empty match gives e1 < s1)
        if e1 < s1 then
            i = i + 1
        else
            i = e1 + 1
        end
    end

    if trimempty then
        while out[1] == "" do table.remove(out, 1) end
        while out[#out] == "" do table.remove(out) end
    end

    return out
end
