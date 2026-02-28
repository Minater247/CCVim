local Sign = {}
local Utf8 = loadModule("lib.utf8")

local defined_signs = {}

local function normalize_group(group)
    if group == nil then
        return ""
    end
    return tostring(group)
end

local function normalize_sign_name(name)
    if type(name) == "number" then
        return tostring(math.floor(name))
    end
    local s = tostring(name or "")
    if s:match("^%d+$") then
        return tostring(tonumber(s) or 0)
    end
    return s
end

local function resolve_buffer(buf)
    if type(buf) == "table" then
        return buf
    end
    if buf == nil or buf == "" or buf == 0 or buf == "%" then
        return windows[curwin].buffer
    end
    if type(buf) == "number" then
        return buffers[buf]
    end
    local name = tostring(buf)
    for _, b in pairs(buffers) do
        if b.name == name then
            return b
        end
    end
    return nil
end

local function iter_target_buffers(buf)
    if buf == nil then
        local all = {}
        for _, b in pairs(buffers) do
            all[#all + 1] = b
        end
        table.sort(all, function(a, b)
            return a.bufnr < b.bufnr
        end)
        return all
    end
    local one = resolve_buffer(buf)
    return one and { one }
end

local function ensure_buffer_sign_state(buf)
    buf.signs = buf.signs or {}
    buf.signs_byln = buf.signs_byln or {}
    buf.signs_nextid = buf.signs_nextid or { [""] = 1 }
end

local function request_redraw(buf)
    for _, win in pairs(windows) do
        if win.buffer == buf then
            win.need_redraw = true
        end
    end
    what_redraw["windows"] = true
    need_redraw = true
end

local function request_redraw_all()
    for _, win in pairs(windows) do
        win.need_redraw = true
    end
    what_redraw["windows"] = true
    need_redraw = true
end

local function export_definition(name, def)
    local out = {
        name = name,
        icon = def.icon,
        text = def.text,
        priority = def.priority or 10,
    }
    if def.linehl ~= nil then out.linehl = def.linehl end
    if def.numhl ~= nil then out.numhl = def.numhl end
    if def.texthl ~= nil then out.texthl = def.texthl end
    if def.culhl ~= nil then out.culhl = def.culhl end
    return out
end

local function rebuild_by_line(buf)
    buf.signs_byln = {}
    for _, signs_for_group in pairs(buf.signs) do
        for _, placed in pairs(signs_for_group) do
            local lnum = placed.lnum
            local line_bucket = buf.signs_byln[lnum]
            if not line_bucket then
                line_bucket = {}
                buf.signs_byln[lnum] = line_bucket
            end
            line_bucket[#line_bucket + 1] = placed
        end
    end
    for _, bucket in pairs(buf.signs_byln) do
        table.sort(bucket, function(a, b)
            if a.priority ~= b.priority then
                return a.priority > b.priority
            end
            if a.id ~= b.id then
                return a.id < b.id
            end
            return a.group < b.group
        end)
    end
end

local function next_sign_id(buf, group)
    ensure_buffer_sign_state(buf)
    local group_tbl = buf.signs[group] or {}
    buf.signs[group] = group_tbl
    local nextid = buf.signs_nextid[group] or 1
    while group_tbl[nextid] do
        nextid = nextid + 1
    end
    buf.signs_nextid[group] = nextid + 1
    return nextid
end

local function normalize_define_opts(opts)
    opts = type(opts) == "table" and opts or {}
    local out = {}
    if opts.icon ~= nil then out.icon = tostring(opts.icon) end
    if opts.linehl ~= nil then out.linehl = tostring(opts.linehl) end
    if opts.numhl ~= nil then out.numhl = tostring(opts.numhl) end
    if opts.text ~= nil then out.text = tostring(opts.text) end
    if opts.texthl ~= nil then out.texthl = tostring(opts.texthl) end
    if opts.culhl ~= nil then out.culhl = tostring(opts.culhl) end
    local prio = tonumber(opts.priority)
    if prio ~= nil then
        out.priority = prio
    end
    return out
end

local function normalize_opts(opts)
    if type(opts) ~= "table" then
        return nil
    end
    if next(opts) == nil then
        return nil
    end
    return opts
end

function Sign.define(name, opts)
    local key = normalize_sign_name(name)
    if key == "" then
        return -1
    end
    defined_signs[key] = normalize_define_opts(opts)
    request_redraw_all()
    return 0
end

function Sign.getdefined(name)
    if name ~= nil then
        local key = normalize_sign_name(name)
        local def = defined_signs[key]
        if not def then
            return {}
        end
        return { export_definition(key, def) }
    end

    local keys = {}
    for key in pairs(defined_signs) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    local out = {}
    for i = 1, #keys do
        local key = keys[i]
        out[#out + 1] = export_definition(key, defined_signs[key])
    end
    return out
end

function Sign.undefine(name)
    if name == nil then
        defined_signs = {}
        request_redraw_all()
        return 0
    end

    local key = normalize_sign_name(name)
    if not defined_signs[key] then
        return -1
    end
    defined_signs[key] = nil
    request_redraw_all()
    return 0
end

function Sign.place(id, group, name, buf, opts)
    local sign_name = normalize_sign_name(name)
    local sign_def = defined_signs[sign_name]
    if not sign_def then
        return -1
    end

    local target = resolve_buffer(buf)
    if not target then
        return -1
    end
    target:ensure_loaded(true)
    ensure_buffer_sign_state(target)

    local sign_group = normalize_group(group)
    local group_tbl = target.signs[sign_group]
    if not group_tbl then
        group_tbl = {}
        target.signs[sign_group] = group_tbl
    end

    local sid = tonumber(id) or 0
    if sid < 0 then
        return -1
    end
    if sid == 0 then
        sid = next_sign_id(target, sign_group)
    end

    local existing = group_tbl[sid]
    opts = normalize_opts(opts)
    if not opts and not existing then
        return -1
    end

    local lnum = (opts and tonumber(opts.lnum))
        or (opts and tonumber(opts.line))
        or (existing and existing.lnum)
    if not lnum then
        return -1
    end

    local max_lnum = target:line_count(true)
    if lnum < 1 or lnum > max_lnum then
        return -1
    end

    local priority = (opts and tonumber(opts.priority))
        or (existing and existing.priority)
        or sign_def.priority
        or 10

    group_tbl[sid] = {
        group = sign_group,
        id = sid,
        lnum = lnum,
        name = sign_name,
        priority = priority,
    }

    local nextid = target.signs_nextid[sign_group] or 1
    if sid >= nextid then
        target.signs_nextid[sign_group] = sid + 1
    end

    rebuild_by_line(target)
    request_redraw(target)
    return sid
end

local function collect_group_signs(buf, group, id, lnum)
    local out = {}
    local function add_sign(sig)
        if (id == nil or sig.id == id) and (lnum == nil or sig.lnum == lnum) then
            out[#out + 1] = {
                group = sig.group,
                id = sig.id,
                lnum = sig.lnum,
                name = sig.name,
                priority = sig.priority,
            }
        end
    end

    if group == "*" then
        for _, signs_for_group in pairs(buf.signs or {}) do
            for _, sig in pairs(signs_for_group) do
                add_sign(sig)
            end
        end
    else
        local signs_for_group = (buf.signs or {})[group]
        if signs_for_group then
            for _, sig in pairs(signs_for_group) do
                add_sign(sig)
            end
        end
    end

    table.sort(out, function(a, b)
        if a.lnum ~= b.lnum then
            return a.lnum < b.lnum
        end
        if a.priority ~= b.priority then
            return a.priority > b.priority
        end
        if a.id ~= b.id then
            return a.id < b.id
        end
        return a.group < b.group
    end)

    return out
end

function Sign.getplaced(buf, opts)
    opts = opts or {}
    local group = opts.group
    if group == nil or group == "" then
        group = ""
    else
        group = tostring(group)
    end
    local id = tonumber(opts.id)
    local lnum = tonumber(opts.lnum)

    local targets = iter_target_buffers(buf)
    if not targets then
        return {}
    end

    local out = {}
    for i = 1, #targets do
        local target = targets[i]
        ensure_buffer_sign_state(target)
        local placed = collect_group_signs(target, group, id, lnum)
        if buf ~= nil or #placed > 0 then
            out[#out + 1] = {
                bufnr = target.bufnr,
                signs = placed,
            }
        end
    end
    return out
end

function Sign.jump(id, group, buf)
    local target = resolve_buffer(buf)
    if not target then
        return -1
    end
    local sid = tonumber(id)
    if not sid then
        return -1
    end
    local sign_group = normalize_group(group)
    local placed = target.signs and target.signs[sign_group] and target.signs[sign_group][sid]
    if not placed then
        return -1
    end

    local target_win = windows[curwin]
    if target_win.buffer ~= target then
        for _, win in pairs(windows) do
            if win.buffer == target then
                target_win = win
                break
            end
        end
    end

    if target_win.winnr ~= curwin then
        enterWindow(target_win.winnr)
    end
    target_win:cursorSet(target_win.cursorx, placed.lnum)
    return placed.lnum
end

local function unplace_from_buffer(buf, group, id)
    ensure_buffer_sign_state(buf)
    local changed = false
    if group == "*" then
        if id == nil then
            for g, _ in pairs(buf.signs) do
                buf.signs[g] = nil
                changed = true
            end
        else
            for _, signs_for_group in pairs(buf.signs) do
                if signs_for_group[id] then
                    signs_for_group[id] = nil
                    changed = true
                end
            end
        end
    else
        local signs_for_group = buf.signs[group]
        if signs_for_group then
            if id == nil then
                if next(signs_for_group) ~= nil then
                    buf.signs[group] = nil
                    changed = true
                end
            elseif signs_for_group[id] then
                signs_for_group[id] = nil
                changed = true
            end
            if buf.signs[group] and next(buf.signs[group]) == nil then
                buf.signs[group] = nil
            end
        end
    end
    if changed then
        rebuild_by_line(buf)
    end
    return changed
end

function Sign.unplace(group, opts)
    opts = opts or {}
    local sign_group = normalize_group(group)
    if sign_group == "" and group == nil then
        sign_group = ""
    end
    local id = tonumber(opts.id)
    local targets = iter_target_buffers(opts.buffer)
    if not targets then
        return -1
    end

    for i = 1, #targets do
        local target = targets[i]
        local changed = unplace_from_buffer(target, sign_group, id)
        if changed then
            request_redraw(target)
        end
    end
    return 0
end

function Sign.on_lines_changed(buf, start1, removed_count, inserted_count)
    if removed_count == 0 and inserted_count == 0 then
        return
    end

    ensure_buffer_sign_state(buf)
    local remove_start = start1
    local remove_end = start1 + removed_count - 1
    local delta = inserted_count - removed_count
    local changed = false

    for group, signs_for_group in pairs(buf.signs) do
        for id, sig in pairs(signs_for_group) do
            if removed_count > 0 and sig.lnum >= remove_start and sig.lnum <= remove_end then
                signs_for_group[id] = nil
                changed = true
            elseif sig.lnum >= (remove_start + removed_count) then
                sig.lnum = sig.lnum + delta
                changed = true
            elseif removed_count == 0 and inserted_count > 0 and sig.lnum >= remove_start then
                sig.lnum = sig.lnum + inserted_count
                changed = true
            end
        end
        if next(signs_for_group) == nil then
            buf.signs[group] = nil
        end
    end

    if changed then
        rebuild_by_line(buf)
        request_redraw(buf)
    end
end

function Sign.get_line_signs(buf, lnum)
    ensure_buffer_sign_state(buf)
    return buf.signs_byln[lnum] or {}
end

function Sign.max_signs_per_line(buf)
    ensure_buffer_sign_state(buf)
    local max = 0
    for _, bucket in pairs(buf.signs_byln) do
        if #bucket > max then
            max = #bucket
        end
    end
    return max
end

function Sign.get_definition(name)
    return defined_signs[name]
end

function Sign.get_line_numhl(buf, lnum)
    local signs = Sign.get_line_signs(buf, lnum)
    for i = 1, #signs do
        local def = defined_signs[signs[i].name]
        if def and def.numhl and def.numhl ~= "" then
            return def.numhl
        end
    end
    return nil
end

function Sign.get_line_linehl(buf, lnum)
    local signs = Sign.get_line_signs(buf, lnum)
    for i = 1, #signs do
        local def = defined_signs[signs[i].name]
        if def and def.linehl and def.linehl ~= "" then
            return def.linehl
        end
    end
    return nil
end

function Sign.get_sign_text(sign)
    local def = defined_signs[sign.name] or {}
    return Utf8.format_sign_text(def.text)
end

function Sign.get_sign_texthl(sign, cursorline_active)
    local def = defined_signs[sign.name] or {}
    if cursorline_active and def.culhl and def.culhl ~= "" then
        return def.culhl
    end
    if def.texthl and def.texthl ~= "" then
        return def.texthl
    end
    return nil
end

return Sign
