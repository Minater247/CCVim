local Diff = {}

local BufAttach = loadModule("lib.bufattach")
local Utf8 = loadModule("lib.utf8")

local cache = {}
local cache_order = {}

local function parse_options(raw)
    local out = {
        filler = false,
        foldcolumn = 2,
    }
    for item in tostring(raw or ""):gmatch("[^,]+") do
        if item == "filler" or item == "followwrap" or item == "icase"
            or item == "iblank" or item == "iwhite" or item == "iwhiteall"
            or item == "iwhiteeol" or item == "closeoff" or item == "horizontal"
            or item == "vertical"
        then
            out[item] = true
        else
            local name, value = item:match("^([^:]+):(.+)$")
            if name and value then
                out[name] = tonumber(value) or value
            end
        end
    end
    return out
end

local function comparable(line, opts)
    local value = line
    if opts.iblank and value:match("^%s*$") then value = "" end
    if opts.iwhiteall then
        value = value:gsub("%s+", "")
    elseif opts.iwhite then
        value = value:gsub("%s+", " "):gsub("%s+$", "")
    elseif opts.iwhiteeol then
        value = value:gsub("%s+$", "")
    end
    if opts.icase then value = value:lower() end
    return value
end

local function copy_map(map)
    local result = {}
    for key, value in pairs(map) do result[key] = value end
    return result
end

local function matching_lines(left, right, opts)
    local a, b = {}, {}
    for i = 1, #left do a[i] = comparable(left[i], opts) end
    for i = 1, #right do b[i] = comparable(right[i], opts) end

    local n, m = #a, #b
    local furthest = { [1] = 0 }
    local trace = {}
    local distance = 0
    local finished = false

    for d = 0, n + m do
        trace[d] = copy_map(furthest)
        for k = -d, d, 2 do
            local left_x = furthest[k - 1]
            local down_x = furthest[k + 1]
            local x
            if k == -d or (k ~= d and (left_x or -math.huge) < (down_x or -math.huge)) then
                x = down_x or 0
            else
                x = (left_x or 0) + 1
            end
            local y = x - k
            while x < n and y < m and a[x + 1] == b[y + 1] do
                x = x + 1
                y = y + 1
            end
            furthest[k] = x
            if x >= n and y >= m then
                distance = d
                finished = true
                break
            end
        end
        if finished then break end
    end

    local reversed = {}
    local x, y = n, m
    for d = distance, 1, -1 do
        local previous = trace[d]
        local k = x - y
        local left_x = previous[k - 1]
        local down_x = previous[k + 1]
        local previous_k
        if k == -d or (k ~= d and (left_x or -math.huge) < (down_x or -math.huge)) then
            previous_k = k + 1
        else
            previous_k = k - 1
        end
        local previous_x = previous[previous_k] or 0
        local previous_y = previous_x - previous_k
        while x > previous_x and y > previous_y do
            reversed[#reversed + 1] = { x, y }
            x = x - 1
            y = y - 1
        end
        if x == previous_x then
            y = y - 1
        else
            x = x - 1
        end
    end
    while x > 0 and y > 0 do
        reversed[#reversed + 1] = { x, y }
        x = x - 1
        y = y - 1
    end

    local result = {}
    for i = #reversed, 1, -1 do result[#result + 1] = reversed[i] end
    return result
end

local function text_bounds(left, right)
    local left_len, right_len = Utf8.len(left), Utf8.len(right)
    local shared = math.min(left_len, right_len)
    local first = 1
    while first <= shared and Utf8.char_at(left, first) == Utf8.char_at(right, first) do
        first = first + 1
    end
    local left_end, right_end = left_len, right_len
    while left_end >= first and right_end >= first
        and Utf8.char_at(left, left_end) == Utf8.char_at(right, right_end)
    do
        left_end = left_end - 1
        right_end = right_end - 1
    end
    return first, left_end, right_end
end

local function add_filler(info, line, count, line_count)
    if count <= 0 then return end
    if line > line_count then
        info.trailing_filler = (info.trailing_filler or 0) + count
    else
        info.filler_before[line] = (info.filler_before[line] or 0) + count
    end
end

local function build_pair(left_buf, right_buf, raw_options)
    local opts = parse_options(raw_options)
    local left = left_buf:lines_ref(true)
    local right = right_buf:lines_ref(true)
    local matches = matching_lines(left, right, opts)
    matches[#matches + 1] = { #left + 1, #right + 1 }

    local left_info = { lines = {}, filler_before = {}, trailing_filler = 0, hunks = {} }
    local right_info = { lines = {}, filler_before = {}, trailing_filler = 0, hunks = {} }
    local previous_left, previous_right = 0, 0

    for _, match in ipairs(matches) do
        local left_start, right_start = previous_left + 1, previous_right + 1
        local left_count = match[1] - left_start
        local right_count = match[2] - right_start
        if left_count > 0 or right_count > 0 then
            local hunk = {
                left_start = left_start,
                left_count = left_count,
                right_start = right_start,
                right_count = right_count,
            }
            left_info.hunks[#left_info.hunks + 1] = hunk
            right_info.hunks[#right_info.hunks + 1] = hunk

            local paired = math.min(left_count, right_count)
            for offset = 0, paired - 1 do
                local left_line = left_start + offset
                local right_line = right_start + offset
                local first, left_end, right_end = text_bounds(left[left_line], right[right_line])
                left_info.lines[left_line] = {
                    group = "DiffChange",
                    text_start = first,
                    text_end = left_end,
                }
                right_info.lines[right_line] = {
                    group = "DiffChange",
                    text_start = first,
                    text_end = right_end,
                }
            end
            for offset = paired, left_count - 1 do
                left_info.lines[left_start + offset] = { group = "DiffAdd" }
            end
            for offset = paired, right_count - 1 do
                right_info.lines[right_start + offset] = { group = "DiffAdd" }
            end
            if opts.filler then
                add_filler(left_info, left_start + paired, right_count - paired, #left)
                add_filler(right_info, right_start + paired, left_count - paired, #right)
            end
        end
        previous_left, previous_right = match[1], match[2]
    end

    left_info.side = "left"
    right_info.side = "right"
    left_info.other = right_buf
    right_info.other = left_buf
    return left_info, right_info
end

local function diff_windows(win)
    local tab = tabpages[win.tabpagenr or curtp]
    local result = {}
    if not tab then return result end
    for _, candidate in ipairs(tab.windows) do
        if candidate.opts.diff then result[#result + 1] = candidate end
    end
    return result
end

local function pair_for_window(win, raw_options, other_buffer)
    if not win.opts.diff then return nil end
    local peers = diff_windows(win)
    local other
    for _, candidate in ipairs(peers) do
        if candidate ~= win and candidate.buffer ~= win.buffer
            and (not other_buffer or candidate.buffer == other_buffer)
        then
            other = candidate
            break
        end
    end
    if not other then return nil end

    local left_buf, right_buf = win.buffer, other.buffer
    if left_buf.bufnr > right_buf.bufnr then
        left_buf, right_buf = right_buf, left_buf
    end
    local left_tick = BufAttach.get_changedtick(left_buf.bufnr)
    local right_tick = BufAttach.get_changedtick(right_buf.bufnr)
    local key = table.concat({
        tostring(left_buf.bufnr), tostring(left_tick),
        tostring(right_buf.bufnr), tostring(right_tick), tostring(raw_options or ""),
    }, ":")
    local entry = cache[key]
    if not entry then
        local left, right = build_pair(left_buf, right_buf, raw_options)
        entry = { left = left, right = right }
        cache[key] = entry
        cache_order[#cache_order + 1] = key
        if #cache_order > 16 then
            cache[table.remove(cache_order, 1)] = nil
        end
    end
    if win.buffer == left_buf then return entry.left end
    return entry.right
end

function Diff.options(raw)
    return parse_options(raw)
end

function Diff.info(win, raw_options, other_buffer)
    return pair_for_window(win, raw_options, other_buffer)
end

function Diff.windows(win)
    return diff_windows(win)
end

function Diff.jump(win, direction, count, raw_options)
    local info = pair_for_window(win, raw_options)
    if not info then return false end
    local amount = math.max(1, math.floor(tonumber(count) or 1))
    local line = win.cursory
    local target
    for _ = 1, amount do
        target = nil
        if direction > 0 then
            for _, hunk in ipairs(info.hunks) do
                local start = info.side == "left" and hunk.left_start or hunk.right_start
                local size = info.side == "left" and hunk.left_count or hunk.right_count
                local effective = math.max(1, math.min(win.buffer:line_count(true), start))
                if effective > line or (size == 0 and start > line) then
                    target = effective
                    break
                end
            end
        else
            for idx = #info.hunks, 1, -1 do
                local hunk = info.hunks[idx]
                local start = info.side == "left" and hunk.left_start or hunk.right_start
                local size = info.side == "left" and hunk.left_count or hunk.right_count
                local effective = math.max(1, math.min(win.buffer:line_count(true), start + math.max(size - 1, 0)))
                if effective < line then
                    target = math.max(1, math.min(win.buffer:line_count(true), start))
                    break
                end
            end
        end
        if not target then return false end
        line = target
    end
    win:cursorSet(1, target, true)
    return true
end

function Diff.hunk_at(win, line, raw_options, other_buffer)
    local info = pair_for_window(win, raw_options, other_buffer)
    if not info then return nil end
    line = line or win.cursory
    for _, hunk in ipairs(info.hunks) do
        local start = info.side == "left" and hunk.left_start or hunk.right_start
        local size = info.side == "left" and hunk.left_count or hunk.right_count
        if size > 0 and line >= start and line < start + size then return hunk, info end
        if size == 0 and (line == start or line == start - 1) then return hunk, info end
    end
    return nil, info
end

local function apply_hunk(win, hunk, info, put)
    if not hunk or not info then return false end
    local current_start = info.side == "left" and hunk.left_start or hunk.right_start
    local current_count = info.side == "left" and hunk.left_count or hunk.right_count
    local other_start = info.side == "left" and hunk.right_start or hunk.left_start
    local other_count = info.side == "left" and hunk.right_count or hunk.left_count
    local source, target, source_start, source_count, target_start, target_count
    if put then
        source, target = win.buffer, info.other
        source_start, source_count = current_start, current_count
        target_start, target_count = other_start, other_count
    else
        source, target = info.other, win.buffer
        source_start, source_count = other_start, other_count
        target_start, target_count = current_start, current_count
    end
    local replacement = {}
    for i = 0, source_count - 1 do
        replacement[#replacement + 1] = source:get_line(source_start + i, true)
    end
    target:set_lines(target_start - 1, target_start - 1 + target_count, false, replacement)
    if target == win.buffer then win:cursorSet(1, math.min(target_start, target:line_count(true)), true) end
    return true
end

function Diff.apply_hunk(win, put, raw_options, other_buffer)
    local hunk, info = Diff.hunk_at(win, win.cursory, raw_options, other_buffer)
    return apply_hunk(win, hunk, info, put)
end

function Diff.apply_range(win, put, first, last, raw_options, other_buffer)
    local info = pair_for_window(win, raw_options, other_buffer)
    if not info then return false end
    local selected = {}
    for _, hunk in ipairs(info.hunks) do
        local start = info.side == "left" and hunk.left_start or hunk.right_start
        local count = info.side == "left" and hunk.left_count or hunk.right_count
        local finish = start + math.max(count - 1, 0)
        if start <= last + 1 and finish >= first - 1 then selected[#selected + 1] = hunk end
    end
    local changed = false
    for index = #selected, 1, -1 do
        changed = apply_hunk(win, selected[index], info, put) or changed
    end
    return changed
end

return Diff
