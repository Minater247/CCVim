local function dirname(path)
    return (tostring(path or ""):match("^(.*)/[^/]+$")) or "."
end

local function normalize_abs(path)
    path = tostring(path or ""):gsub("\\", "/")
    if path == "" then
        return "/"
    end
    local parts = {}
    for seg in path:gmatch("[^/]+") do
        if seg == ".." then
            if #parts > 0 then
                table.remove(parts)
            end
        elseif seg ~= "." and seg ~= "" then
            parts[#parts + 1] = seg
        end
    end
    return "/" .. table.concat(parts, "/")
end

local function cwd()
    local handle = io.popen("pwd")
    if not handle then
        return "."
    end
    local out = handle:read("*l")
    handle:close()
    return normalize_abs(out or ".")
end

local function make_absolute(path)
    path = tostring(path or "")
    if path:sub(1, 1) == "/" then
        return normalize_abs(path)
    end
    local base = cwd()
    if base:sub(-1) == "/" then
        return normalize_abs(base .. path)
    end
    return normalize_abs(base .. "/" .. path)
end

local function append_lua_path(prefix)
    package.path = prefix .. "/?.lua;" .. prefix .. "/?/init.lua;" .. package.path
end

local function file_exists(path)
    local handle = io.open(path, "rb")
    if not handle then
        return false
    end
    handle:close()
    return true
end

local function package_searchpath(module_name, search_path)
    local module_path = tostring(module_name or ""):gsub("%.", "/")
    for template in tostring(search_path or ""):gmatch("[^;]+") do
        local candidate = template:gsub("%?", module_path)
        if file_exists(candidate) then
            return candidate
        end
    end
end

local function install_test_module_alias()
    local searchers = rawget(package, "searchers") or rawget(package, "loaders")
    if type(searchers) ~= "table" then
        return
    end

    local alias_prefix = "vim.tests."
    local target_prefix = "tests."

    local function alias_searcher(module_name)
        if module_name:sub(1, #alias_prefix) ~= alias_prefix then
            return nil
        end

        local alias_name = target_prefix .. module_name:sub(#alias_prefix + 1)
        local file_path = package_searchpath(alias_name, package.path)
        if not file_path then
            return nil
        end

        local chunk, load_err = loadfile(file_path)
        if not chunk then
            error(load_err, 0)
        end
        return chunk, file_path
    end

    table.insert(searchers, 1, alias_searcher)
end

local source = debug.getinfo(1, "S").source
local script_path = (arg and arg[0]) or ""
if script_path == "" and type(source) == "string" and source:sub(1, 1) == "@" then
    script_path = source:sub(2)
end
script_path = make_absolute(script_path)

local root = dirname(dirname(script_path))
append_lua_path(root)
append_lua_path(dirname(root))
install_test_module_alias()

local has_lfs, lfs = pcall(require, "lfs")
if not has_lfs then
    error("compare_colorscheme_allocators.lua requires LuaFileSystem (lfs)")
end

local LuaEditorBackend = require("tests.framework.backends.lua_editor")

local function unpack_rgb(rgb)
    local r = math.floor(rgb / 65536) % 256
    local g = math.floor(rgb / 256) % 256
    local b = rgb % 256
    return r, g, b
end

local function rgb_hex(rgb)
    return string.format("#%06x", rgb)
end

local function srgb_to_linear(channel)
    channel = channel / 255
    if channel <= 0.04045 then
        return channel / 12.92
    end
    return ((channel + 0.055) / 1.055) ^ 2.4
end

local OKLAB_CACHE = {}
local YIQ_CACHE = {}

local function rgb_to_oklab(rgb)
    local cached = OKLAB_CACHE[rgb]
    if cached then
        return cached[1], cached[2], cached[3]
    end

    local r8, g8, b8 = unpack_rgb(rgb)
    local r = srgb_to_linear(r8)
    local g = srgb_to_linear(g8)
    local b = srgb_to_linear(b8)

    local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b

    local l_ = l ^ (1 / 3)
    local m_ = m ^ (1 / 3)
    local s_ = s ^ (1 / 3)

    local out = {
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    }
    OKLAB_CACHE[rgb] = out
    return out[1], out[2], out[3]
end

local function rgb_to_yiq(rgb)
    local cached = YIQ_CACHE[rgb]
    if cached then
        return cached[1], cached[2], cached[3]
    end

    local r, g, b = unpack_rgb(rgb)
    r = r / 255
    g = g / 255
    b = b / 255
    local out = {
        0.299 * r + 0.587 * g + 0.114 * b,
        0.596 * r - 0.274 * g - 0.322 * b,
        0.211 * r - 0.523 * g + 0.312 * b,
    }
    YIQ_CACHE[rgb] = out
    return out[1], out[2], out[3]
end

local DISTANCES = {
    rgb_luma = function(a, b)
        local ar, ag, ab = unpack_rgb(a)
        local br, bg, bb = unpack_rgb(b)
        local dr = ar - br
        local dg = ag - bg
        local db = ab - bb
        return math.sqrt(0.30 * dr * dr + 0.59 * dg * dg + 0.11 * db * db)
    end,
    rgb_equal = function(a, b)
        local ar, ag, ab = unpack_rgb(a)
        local br, bg, bb = unpack_rgb(b)
        local dr = ar - br
        local dg = ag - bg
        local db = ab - bb
        return math.sqrt(dr * dr + dg * dg + db * db)
    end,
    yiq = function(a, b)
        local ay, ai, aq = rgb_to_yiq(a)
        local by, bi, bq = rgb_to_yiq(b)
        local dy = ay - by
        local di = ai - bi
        local dq = aq - bq
        return math.sqrt(4 * dy * dy + 1.5 * di * di + 1.5 * dq * dq)
    end,
    oklab = function(a, b)
        local al, aa, ab = rgb_to_oklab(a)
        local bl, ba, bb = rgb_to_oklab(b)
        local dl = al - bl
        local da = aa - ba
        local db = ab - bb
        return math.sqrt(dl * dl + da * da + db * db)
    end,
    oklab_chroma = function(a, b)
        local al, aa, ab = rgb_to_oklab(a)
        local bl, ba, bb = rgb_to_oklab(b)
        local dl = al - bl
        local da = aa - ba
        local db = ab - bb
        return math.sqrt(dl * dl + 2.5 * da * da + 2.5 * db * db)
    end,
}

local IMPORTANT_GROUPS = {
    Normal = 8,
    StatusLine = 6,
    StatusLineNC = 4,
    WinSeparator = 4,
    VertSplit = 4,
    TabLine = 4,
    TabLineSel = 5,
    NonText = 5,
    EndOfBuffer = 5,
    CursorLine = 3,
    CursorLineNr = 3,
    CursorColumn = 3,
    Visual = 3,
    Search = 3,
    IncSearch = 3,
    Pmenu = 3,
    PmenuSel = 3,
    Error = 4,
    ErrorMsg = 4,
    WarningMsg = 3,
    Todo = 3,
    Comment = 2,
    Constant = 2,
    Identifier = 2,
    Statement = 2,
    PreProc = 2,
    Type = 2,
    Special = 2,
    Directory = 2,
    Title = 2,
}

local WEIGHTS = {
    occurrence = function()
        return 1
    end,
    semantic = function(entry)
        return IMPORTANT_GROUPS[entry.group] or 1
    end,
    semantic_bg = function(entry)
        local weight = IMPORTANT_GROUPS[entry.group] or 1
        if entry.role == "bg" then
            weight = weight * 1.75
        end
        return weight
    end,
}

local function palette_cost(items, centers, distance)
    local total = 0
    for i = 1, #items do
        local item = items[i]
        local best = math.huge
        for j = 1, #centers do
            local dist = distance(item.rgb, centers[j])
            if dist < best then
                best = dist
            end
        end
        total = total + best * item.weight
    end
    return total
end

local function copy_list(list)
    local out = {}
    for i = 1, #list do
        out[i] = list[i]
    end
    return out
end

local function build_items(entries, weight_fn)
    local usage = {}
    local total_weight = 0
    for i = 1, #entries do
        local entry = entries[i]
        local weight = weight_fn(entry)
        usage[entry.rgb] = (usage[entry.rgb] or 0) + weight
        total_weight = total_weight + weight
    end

    local items = {}
    for rgb, weight in pairs(usage) do
        items[#items + 1] = { rgb = rgb, weight = weight }
    end
    table.sort(items, function(a, b)
        if a.weight == b.weight then
            return a.rgb < b.rgb
        end
        return a.weight > b.weight
    end)
    return items, total_weight
end

local function top_weight_centers(items, wanted)
    local centers = {}
    for i = 1, math.min(wanted, #items) do
        centers[i] = items[i].rgb
    end
    return centers
end

local function greedy_reduction_centers(items, wanted, distance)
    local centers = {}
    if #items == 0 then
        return centers
    end
    if #items <= wanted then
        return top_weight_centers(items, wanted)
    end

    local selected = {}
    local best_cost = math.huge
    local best_rgb
    for i = 1, #items do
        local rgb = items[i].rgb
        local cost = palette_cost(items, { rgb }, distance)
        if cost < best_cost or (cost == best_cost and (best_rgb == nil or rgb < best_rgb)) then
            best_cost = cost
            best_rgb = rgb
        end
    end
    centers[1] = best_rgb
    selected[best_rgb] = true

    while #centers < wanted do
        local next_rgb
        local next_cost = math.huge
        for i = 1, #items do
            local rgb = items[i].rgb
            if not selected[rgb] then
                local trial = copy_list(centers)
                trial[#trial + 1] = rgb
                local cost = palette_cost(items, trial, distance)
                if cost < next_cost or (cost == next_cost and (next_rgb == nil or rgb < next_rgb)) then
                    next_rgb = rgb
                    next_cost = cost
                end
            end
        end
        centers[#centers + 1] = next_rgb
        selected[next_rgb] = true
    end

    return centers
end

local function weighted_farthest_centers(items, wanted, distance)
    local centers = {}
    if #items == 0 then
        return centers
    end
    if #items <= wanted then
        return top_weight_centers(items, wanted)
    end

    local first_rgb = items[1].rgb
    local first_cost = palette_cost(items, { first_rgb }, distance)
    for i = 2, #items do
        local rgb = items[i].rgb
        local cost = palette_cost(items, { rgb }, distance)
        if cost < first_cost or (cost == first_cost and rgb < first_rgb) then
            first_rgb = rgb
            first_cost = cost
        end
    end
    centers[1] = first_rgb

    local selected = { [first_rgb] = true }
    while #centers < wanted do
        local best_rgb
        local best_score = -1
        for i = 1, #items do
            local item = items[i]
            if not selected[item.rgb] then
                local nearest = math.huge
                for j = 1, #centers do
                    local dist = distance(item.rgb, centers[j])
                    if dist < nearest then
                        nearest = dist
                    end
                end
                local score = nearest * item.weight
                if score > best_score or (score == best_score and (best_rgb == nil or item.rgb < best_rgb)) then
                    best_rgb = item.rgb
                    best_score = score
                end
            end
        end
        centers[#centers + 1] = best_rgb
        selected[best_rgb] = true
    end
    return centers
end

local function snap_means(items, seeds, distance, rounds)
    local centers = copy_list(seeds)
    if #centers == 0 then
        return centers
    end

    for _ = 1, rounds do
        local clusters = {}
        for i = 1, #centers do
            clusters[i] = { members = {}, sum_r = 0, sum_g = 0, sum_b = 0, total = 0 }
        end

        for i = 1, #items do
            local item = items[i]
            local best_idx = 1
            local best_dist = distance(item.rgb, centers[1])
            for j = 2, #centers do
                local dist = distance(item.rgb, centers[j])
                if dist < best_dist then
                    best_idx = j
                    best_dist = dist
                end
            end

            local cluster = clusters[best_idx]
            cluster.members[#cluster.members + 1] = item
            local r, g, b = unpack_rgb(item.rgb)
            cluster.sum_r = cluster.sum_r + r * item.weight
            cluster.sum_g = cluster.sum_g + g * item.weight
            cluster.sum_b = cluster.sum_b + b * item.weight
            cluster.total = cluster.total + item.weight
        end

        for i = 1, #clusters do
            local cluster = clusters[i]
            if cluster.total > 0 then
                local mean_r = cluster.sum_r / cluster.total
                local mean_g = cluster.sum_g / cluster.total
                local mean_b = cluster.sum_b / cluster.total
                local mean_rgb = math.floor(mean_r + 0.5) * 65536
                    + math.floor(mean_g + 0.5) * 256
                    + math.floor(mean_b + 0.5)

                local best_rgb = cluster.members[1].rgb
                local best_dist = distance(best_rgb, mean_rgb)
                for j = 2, #cluster.members do
                    local candidate = cluster.members[j].rgb
                    local dist = distance(candidate, mean_rgb)
                    if dist < best_dist or (dist == best_dist and candidate < best_rgb) then
                        best_rgb = candidate
                        best_dist = dist
                    end
                end
                centers[i] = best_rgb
            end
        end
    end

    return centers
end

local function refine_swaps(items, centers, distance)
    if #items <= #centers then
        return centers
    end

    local selected = {}
    for i = 1, #centers do
        selected[centers[i]] = true
    end

    local current_cost = palette_cost(items, centers, distance)
    local improved = true
    while improved do
        improved = false
        for i = 1, #centers do
            local old_rgb = centers[i]
            selected[old_rgb] = nil
            for j = 1, #items do
                local candidate = items[j].rgb
                if not selected[candidate] then
                    centers[i] = candidate
                    local cost = palette_cost(items, centers, distance)
                    if cost < current_cost then
                        current_cost = cost
                        selected[candidate] = true
                        improved = true
                        break
                    end
                end
            end
            if improved then
                break
            end
            centers[i] = old_rgb
            selected[old_rgb] = true
        end
    end

    return centers
end

local SELECTORS = {
    top_weight = function(items, wanted)
        return top_weight_centers(items, wanted)
    end,
    greedy = function(items, wanted, distance)
        return greedy_reduction_centers(items, wanted, distance)
    end,
    farthest = function(items, wanted, distance)
        return weighted_farthest_centers(items, wanted, distance)
    end,
    kmeans_snap = function(items, wanted, distance)
        local seeds = weighted_farthest_centers(items, wanted, distance)
        return snap_means(items, seeds, distance, 6)
    end,
}

local function nearest_color(rgb, palette, distance)
    local best_rgb = palette[1]
    local best_dist = distance(rgb, best_rgb)
    for i = 2, #palette do
        local candidate = palette[i]
        local dist = distance(rgb, candidate)
        if dist < best_dist then
            best_rgb = candidate
            best_dist = dist
        end
    end
    return best_rgb, best_dist
end

local function list_colorschemes()
    local schemes = {}
    local seen = {}
    local colors_dir = root .. "/runtime/colors"
    for name in lfs.dir(colors_dir) do
        if name ~= "." and name ~= ".." and name ~= "README.txt" then
            local scheme = name:match("^(.*)%.vim$") or name:match("^(.*)%.lua$")
            if scheme and not seen[scheme] then
                seen[scheme] = true
                schemes[#schemes + 1] = scheme
            end
        end
    end
    table.sort(schemes)
    return schemes
end

local function collect_scheme_entries(name)
    local backend = LuaEditorBackend.new({ ccvim_path = root })
    local code = string.format([=[
        local colors = _G.colors
        local Highlight = loadModule("lib.highlight")

        local function rgb_of(value)
            if type(value) ~= "table" then
                return nil
            end
            if type(value.rgb) == "number" then
                return value.rgb
            end
            if type(value.palette) == "number" then
                local r, g, b = term.getPaletteColor(value.palette)
                return colors.packRGB(r, g, b)
            end
            return nil
        end

        vim.cmd.colorscheme(%q)

        local names = Highlight.ListNames(0)
        local out = { name = vim.g.colors_name, entries = {} }
        for i = 1, #names do
            local group = names[i]
            local raw = Highlight.RawFor(group, 0)
            if type(raw) == "table" and #raw > 0 then
                local fg = rgb_of(raw._raw_fg)
                local bg = rgb_of(raw._raw_bg)
                if fg ~= nil then
                    out.entries[#out.entries + 1] = { group = group, role = "fg", rgb = fg }
                end
                if bg ~= nil then
                    out.entries[#out.entries + 1] = { group = group, role = "bg", rgb = bg }
                end
            end
        end
        return out
    ]=], name)

    local result, err = backend:eval_block(code)
    backend:cleanup()
    if err then
        return nil, err
    end
    return result
end

local function evaluate_method(method, scheme_data)
    local weight_fn = WEIGHTS[method.weight]
    local distance = DISTANCES[method.distance]
    local selector = SELECTORS[method.selector]
    local scheme_scores = {}
    local sum_scores = 0
    local darkblue_details = nil
    local worst_name, worst_score = nil, -1

    for i = 1, #scheme_data do
        local scheme = scheme_data[i]
        local items, total_weight = build_items(scheme.entries, weight_fn)
        local centers = selector(items, 16, distance)
        if method.refine == "swap" then
            centers = refine_swaps(items, centers, distance)
        end

        local total = 0
        for j = 1, #scheme.entries do
            local entry = scheme.entries[j]
            local mapped_rgb, dist = nearest_color(entry.rgb, centers, distance)
            local weight = weight_fn(entry)
            total = total + dist * weight
            if scheme.name == "darkblue" then
                darkblue_details = darkblue_details or {}
                if entry.group == "Normal" and entry.role == "bg" then
                    darkblue_details.normal_bg = {
                        target = entry.rgb,
                        mapped = mapped_rgb,
                        distance = dist,
                    }
                elseif entry.group == "StatusLine" and entry.role == "fg" then
                    darkblue_details.statusline_fg = {
                        target = entry.rgb,
                        mapped = mapped_rgb,
                        distance = dist,
                    }
                elseif entry.group == "StatusLine" and entry.role == "bg" then
                    darkblue_details.statusline_bg = {
                        target = entry.rgb,
                        mapped = mapped_rgb,
                        distance = dist,
                    }
                end
            end
        end

        local score = total / total_weight
        scheme_scores[#scheme_scores + 1] = { name = scheme.name, score = score }
        sum_scores = sum_scores + score
        if score > worst_score then
            worst_score = score
            worst_name = scheme.name
        end
    end

    table.sort(scheme_scores, function(a, b)
        if a.score == b.score then
            return a.name < b.name
        end
        return a.score < b.score
    end)

    local darkblue_score = nil
    for i = 1, #scheme_scores do
        if scheme_scores[i].name == "darkblue" then
            darkblue_score = scheme_scores[i].score
            break
        end
    end

    return {
        label = table.concat({
            method.selector,
            method.refine,
            method.distance,
            method.weight,
        }, "/"),
        selector = method.selector,
        refine = method.refine,
        distance = method.distance,
        weight = method.weight,
        mean = sum_scores / #scheme_data,
        worst_scheme = worst_name,
        worst_score = worst_score,
        darkblue_score = darkblue_score,
        darkblue = darkblue_details,
    }
end

local function format_darkblue(detail)
    if not detail then
        return "n/a"
    end
    return string.format("%s -> %s (%.4f)", rgb_hex(detail.target), rgb_hex(detail.mapped), detail.distance)
end

local function print_ranked(title, rows, count)
    print(title)
    for i = 1, math.min(count, #rows) do
        local row = rows[i]
        print(string.format(
            "%2d. mean=%0.4f darkblue=%0.4f worst=%s:%0.4f %s",
            i,
            row.mean,
            row.darkblue_score or -1,
            row.worst_scheme or "?",
            row.worst_score or -1,
            row.label
        ))
    end
    print("")
end

local function print_reference_methods(rows, labels)
    print("Reference methods")
    for i = 1, #labels do
        local wanted = labels[i]
        for rank = 1, #rows do
            local row = rows[rank]
            if row.label == wanted then
                print(string.format(
                    "  rank=%2d mean=%0.4f darkblue=%0.4f worst=%s:%0.4f %s",
                    rank,
                    row.mean,
                    row.darkblue_score or -1,
                    row.worst_scheme or "?",
                    row.worst_score or -1,
                    row.label
                ))
                break
            end
        end
    end
    print("")
end

local function compare_numeric(a, b)
    if a == b then
        return 0
    end
    if a < b then
        return -1
    end
    return 1
end

local function stable_sort(rows, key)
    table.sort(rows, function(a, b)
        local cmp = compare_numeric(a[key], b[key])
        if cmp == 0 then
            return a.label < b.label
        end
        return cmp < 0
    end)
end

local top_n = tonumber(arg and arg[1]) or 10

local schemes = list_colorschemes()
local scheme_data = {}
local failures = {}

for i = 1, #schemes do
    local name = schemes[i]
    io.write(string.format("Loading %s...\n", name))
    local data, err = collect_scheme_entries(name)
    if err then
        failures[#failures + 1] = { name = name, err = tostring(err) }
    elseif data and #data.entries > 0 then
        scheme_data[#scheme_data + 1] = data
    else
        failures[#failures + 1] = { name = name, err = "no explicit colors collected" }
    end
end

if #scheme_data == 0 then
    error("Could not collect any colorscheme data")
end

print(string.format("\nCollected %d colorschemes with explicit colors.", #scheme_data))
if #failures > 0 then
    print(string.format("Skipped %d colorschemes:", #failures))
    for i = 1, #failures do
        print(string.format("  - %s: %s", failures[i].name, failures[i].err))
    end
    print("")
end

local methods = {}
for selector in pairs(SELECTORS) do
    for distance in pairs(DISTANCES) do
        for weight in pairs(WEIGHTS) do
            methods[#methods + 1] = {
                selector = selector,
                refine = "none",
                distance = distance,
                weight = weight,
            }
            methods[#methods + 1] = {
                selector = selector,
                refine = "swap",
                distance = distance,
                weight = weight,
            }
        end
    end
end

table.sort(methods, function(a, b)
    local la = table.concat({ a.selector, a.refine, a.distance, a.weight }, "/")
    local lb = table.concat({ b.selector, b.refine, b.distance, b.weight }, "/")
    return la < lb
end)

local ranked = {}
for i = 1, #methods do
    ranked[#ranked + 1] = evaluate_method(methods[i], scheme_data)
end

local by_mean = copy_list(ranked)
stable_sort(by_mean, "mean")
print_ranked(string.format("Top %d by mean scheme error", top_n), by_mean, top_n)
print_reference_methods(by_mean, {
    "greedy/swap/rgb_luma/occurrence",
    "greedy/swap/rgb_luma/semantic",
    "greedy/swap/oklab/semantic",
})

local by_darkblue = copy_list(ranked)
stable_sort(by_darkblue, "darkblue_score")
print_ranked(string.format("Top %d for darkblue", top_n), by_darkblue, top_n)

print("Darkblue details for the best overall methods:")
for i = 1, math.min(top_n, #by_mean) do
    local row = by_mean[i]
    print(string.format("  %2d. %s", i, row.label))
    print(string.format("      Normal.bg    %s", format_darkblue(row.darkblue and row.darkblue.normal_bg)))
    print(string.format("      StatusLine.fg %s", format_darkblue(row.darkblue and row.darkblue.statusline_fg)))
    print(string.format("      StatusLine.bg %s", format_darkblue(row.darkblue and row.darkblue.statusline_bg)))
end
