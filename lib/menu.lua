local Menu = {}

local MODE_BUCKETS = {
    normal = { "n", "nvo", "a" },
    visual = { "x", "vs", "nvo", "a" },
    select = { "s", "vs", "a" },
    insert = { "i", "a" },
    cmdline = { "c", "a" },
    operator = { "o", "nvo", "a" },
}
local ALL_BUCKETS = { "a", "nvo", "n", "vs", "x", "s", "o", "i", "c", "tl" }

local function buckets(mode)
    return MODE_BUCKETS[mode] or ALL_BUCKETS
end

function Menu.ensure(state)
    local menus = state.menus
    if type(menus) ~= "table" then
        menus = {}
        state.menus = menus
    end
    menus.items = menus.items or {}
    menus.tooltips = menus.tooltips or {}
    menus.translations = menus.translations or {}
    menus.next_order = menus.next_order or 0
    return menus
end

local function display_name(name)
    name = tostring(name or ""):gsub("\\([ .])", "%1")
    name = name:gsub("&&", "\0"):gsub("&", ""):gsub("\0", "&")
    return name
end

local function priority(item)
    local out = {}
    for part in tostring(item.priority or "500"):gmatch("%d+") do
        out[#out + 1] = tonumber(part)
    end
    return out
end

local function less(a, b)
    local ap, bp = priority(a), priority(b)
    for i = 1, math.max(#ap, #bp) do
        local av, bv = ap[i] or 500, bp[i] or 500
        if av ~= bv then return av < bv end
    end
    if a.order ~= b.order then return (a.order or 0) < (b.order or 0) end
    return a.label:lower() < b.label:lower()
end

function Menu.find(state, name, mode)
    local menus = Menu.ensure(state)
    local order = buckets(mode)
    for i = 1, #order do
        local bucket = menus.items[order[i]]
        local item = bucket and bucket[name]
        if item then return item end
        for _, candidate in pairs(bucket or {}) do
            if candidate.translated == name then return candidate end
        end
    end
end

function Menu.entries(state, root, mode)
    local menus = Menu.ensure(state)
    local order = buckets(mode)
    local prefix = root == "" and "" or root .. "."
    local entries, by_name = {}, {}

    for i = 1, #order do
        for name, item in pairs(menus.items[order[i]] or {}) do
            local shown = item.translated or name
            if item.enabled ~= false and shown:sub(1, #prefix) == prefix then
                local tail = shown:sub(#prefix + 1)
                local segment, rest = tail:match("^([^.]+)%.(.+)$")
                segment = segment or tail
                if segment ~= "" then
                    local entry = {
                        label = display_name(segment),
                        path = prefix .. segment,
                        submenu = rest ~= nil,
                        item = rest == nil and item or nil,
                        priority = item.priority,
                        order = item.order,
                        separator = segment:match("^%-.*%-$") ~= nil,
                    }
                    local current = by_name[segment]
                    if not current then
                        entries[#entries + 1] = entry
                        by_name[segment] = entry
                    elseif less(entry, current) then
                        current.priority = entry.priority
                    end
                end
            end
        end
    end

    table.sort(entries, less)
    return entries
end

function Menu.execute(item, exec, feed)
    local rhs = tostring(item and item.rhs or "")
    if rhs == "" or rhs:lower() == "<nop>" then return true end
    if rhs:lower():sub(1, 5) == "<cmd>" then rhs = rhs:sub(6) end
    if rhs:sub(1, 1) == ":" then rhs = rhs:sub(2) end
    rhs = rhs:gsub("<[cC][rR]>%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if rhs == "" then return true end
    if feed and not rhs:find("^%a+[%s!]") then return feed(rhs, item.recursive) end
    return exec(rhs)
end

return Menu
