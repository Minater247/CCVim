local Color = {}

local XTERM_STANDARD = {
    0x000000, 0x800000, 0x008000, 0x808000,
    0x000080, 0x800080, 0x008080, 0xC0C0C0,
    0x808080, 0xFF0000, 0x00FF00, 0xFFFF00,
    0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
}

local oklab_cache = {}
local distance_cache = {}

function Color.pack(r, g, b)
    return r * 65536 + g * 256 + b
end

function Color.unpack(rgb)
    return math.floor(rgb / 65536) % 256, math.floor(rgb / 256) % 256, rgb % 256
end

function Color.xterm256(index, fallback)
    if index < 0 then
        return fallback or 0
    end
    if index < 16 then
        return XTERM_STANDARD[index + 1]
    end
    if index < 232 then
        local cube = index - 16
        local r = math.floor(cube / 36)
        local g = math.floor((cube % 36) / 6)
        local b = cube % 6
        r = r == 0 and 0 or 55 + r * 40
        g = g == 0 and 0 or 55 + g * 40
        b = b == 0 and 0 or 55 + b * 40
        return Color.pack(r, g, b)
    end
    if index < 256 then
        local value = 8 + (index - 232) * 10
        return Color.pack(value, value, value)
    end
    return fallback or 0
end

local function linear(channel)
    channel = channel / 255
    if channel <= 0.04045 then
        return channel / 12.92
    end
    return ((channel + 0.055) / 1.055) ^ 2.4
end

local function oklab(rgb)
    local cached = oklab_cache[rgb]
    if cached then
        return cached[1], cached[2], cached[3]
    end

    local r8, g8, b8 = Color.unpack(rgb)
    local r, g, b = linear(r8), linear(g8), linear(b8)
    local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    local lr, mr, sr = l ^ (1 / 3), m ^ (1 / 3), s ^ (1 / 3)
    cached = {
        0.2104542553 * lr + 0.7936177850 * mr - 0.0040720468 * sr,
        1.9779984951 * lr - 2.4285922050 * mr + 0.4505937099 * sr,
        0.0259040371 * lr + 0.7827717662 * mr - 0.8086757660 * sr,
    }
    oklab_cache[rgb] = cached
    return cached[1], cached[2], cached[3]
end

function Color.distance(a, b)
    if a == b then
        return 0
    end
    local low, high = a, b
    if low > high then
        low, high = high, low
    end
    local row = distance_cache[low]
    local cached = row and row[high]
    if cached ~= nil then
        return cached
    end

    local l1, a1, b1 = oklab(a)
    local l2, a2, b2 = oklab(b)
    local dl, da, db = l1 - l2, a1 - a2, b1 - b2
    cached = math.sqrt(dl * dl + da * da + db * db)
    if not row then
        row = {}
        distance_cache[low] = row
    end
    row[high] = cached
    return cached
end

function Color.luminance(rgb)
    local r, g, b = Color.unpack(rgb)
    return 0.30 * r + 0.59 * g + 0.11 * b
end

function Color.seeded_centers(items, wanted)
    local centers = {}
    if #items == 0 then
        return centers
    end
    if #items <= wanted then
        for i = 1, #items do
            centers[i] = items[i].rgb
        end
        return centers
    end

    local selected = {}
    local best_distances = {}
    centers[1] = items[1].rgb
    selected[centers[1]] = true
    for i = 1, #items do
        best_distances[i] = Color.distance(items[i].rgb, centers[1])
    end

    while #centers < wanted do
        local best_idx, best_score = nil, -1
        for i = 1, #items do
            local item = items[i]
            if not selected[item.rgb] then
                local score = best_distances[i] * item.weight
                if best_idx == nil or score > best_score
                    or (score == best_score and item.rgb < items[best_idx].rgb)
                then
                    best_idx, best_score = i, score
                end
            end
        end

        local next_rgb = items[best_idx].rgb
        selected[next_rgb] = true
        centers[#centers + 1] = next_rgb
        for i = 1, #items do
            local dist = Color.distance(items[i].rgb, next_rgb)
            if dist < best_distances[i] then
                best_distances[i] = dist
            end
        end
    end
    return centers
end

function Color.assign_palette_slots(centers, reference)
    local slots = {}
    local remaining = {}
    for i = 1, #centers do
        remaining[i] = centers[i]
    end

    local function take_extreme(darkest)
        if #remaining == 0 then
            return nil
        end
        local best_idx = 1
        local best_luma = Color.luminance(remaining[1])
        for i = 2, #remaining do
            local luma = Color.luminance(remaining[i])
            if (darkest and luma < best_luma) or (not darkest and luma > best_luma) then
                best_idx, best_luma = i, luma
            end
        end
        return table.remove(remaining, best_idx)
    end

    slots[15] = take_extreme(true) or reference[15]
    slots[0] = take_extreme(false) or reference[0]
    for slot = 0, 15 do
        if slots[slot] == nil then
            if #remaining == 0 then
                slots[slot] = reference[slot]
            else
                local best_idx, best_dist = 1, math.huge
                for i = 1, #remaining do
                    local dist = Color.distance(reference[slot], remaining[i])
                    if dist < best_dist then
                        best_idx, best_dist = i, dist
                    end
                end
                slots[slot] = table.remove(remaining, best_idx)
            end
        end
    end
    return slots
end

return Color
