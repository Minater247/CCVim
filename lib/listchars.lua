local ListChars = {}

local cache = { raw = nil, parsed = nil }

local function parse(raw)
    local out = {}
    raw = tostring(raw or "")
    if raw == "" then
        return out
    end

    local items = options.ParseKeyedCSL(raw, { [":"] = true })

    if items.space and items.space ~= "" then
        out.space = items.space
    end

    -- TODO: 3-item tab setting
    if items.tab and items.tab ~= "" then
        local t = items.tab
        local head = t:sub(1, 1)
        local fill = t:sub(2, 2)
        if fill == "" then fill = head end
        out.tab_head = head
        out.tab_fill = fill
    end

    return out
end

function ListChars.get(window)
    local raw = options.get("listchars", window)
    if cache.raw == raw and cache.parsed then
        return cache.parsed
    end
    local parsed = parse(raw)
    cache.raw = raw
    cache.parsed = parsed
    return parsed
end

return ListChars
