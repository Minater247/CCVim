local Decoration = {}

local providers = {}
local redraw_tick = 0
local active_state = nil

local function provider_ids_sorted()
    local ids = {}
    for ns_id, _ in pairs(providers) do
        ids[#ids + 1] = ns_id
    end
    table.sort(ids)
    return ids
end

local function callback_for(ns_id, name)
    local provider = providers[ns_id]
    if type(provider) ~= "table" then
        return nil
    end
    local cb = provider[name]
    if type(cb) ~= "function" then
        return nil
    end
    return cb
end

local function call_provider(state, ns_id, cb_name, ...)
    local cb = callback_for(ns_id, cb_name)
    if not cb then
        return nil, true
    end

    local ok, rv = pcall(cb, ...)
    if ok then
        return rv, true
    end

    state.disabled[ns_id] = true
    LOG_INTERNAL(
        "decor",
        "decoration provider ns=%s callback=%s failed: %s",
        tostring(ns_id),
        tostring(cb_name),
        tostring(rv)
    )
    return nil, false
end

local function clear_mark_table(ns_marks, line_start, line_end)
    if type(ns_marks) ~= "table" then
        return
    end

    if line_start == nil then line_start = 0 end
    if line_end == nil then line_end = -1 end

    if line_start == 0 and line_end == -1 then
        for id, _ in pairs(ns_marks) do
            ns_marks[id] = nil
        end
        return
    end

    for id, mark in pairs(ns_marks) do
        local lnum = mark.line or 0
        local in_range = lnum >= line_start and (line_end < 0 or lnum < line_end)
        if in_range then
            ns_marks[id] = nil
        end
    end
end

function Decoration.set_provider(ns_id, opts)
    if opts == nil then
        providers[ns_id] = nil
        return
    end
    providers[ns_id] = opts
end

function Decoration.begin_redraw()
    redraw_tick = redraw_tick + 1

    local state = {
        tick = redraw_tick,
        ids = provider_ids_sorted(),
        disabled = {},
        seen_buf = {},
        win_skip_line = {},
        ephemeral_by_buf = {},
    }
    active_state = state

    for i = 1, #state.ids do
        local ns_id = state.ids[i]
        local rv, _ok = call_provider(state, ns_id, "on_start", "start", state.tick)
        if rv == false then
            state.disabled[ns_id] = true
        end
    end
end

function Decoration.end_redraw()
    local state = active_state
    if not state then
        return
    end

    for i = 1, #state.ids do
        local ns_id = state.ids[i]
        if not state.disabled[ns_id] then
            call_provider(state, ns_id, "on_end", "end", state.tick)
        end
    end

    active_state = nil
end

function Decoration.on_window(win, topline0, botline0)
    local state = active_state
    if not state then
        return
    end

    local bufnr = win.buffer.bufnr
    local winid = win.winnr
    state.win_skip_line[winid] = state.win_skip_line[winid] or {}
    local win_skip = state.win_skip_line[winid]

    for i = 1, #state.ids do
        local ns_id = state.ids[i]
        if not state.disabled[ns_id] then
            state.seen_buf[ns_id] = state.seen_buf[ns_id] or {}
            if not state.seen_buf[ns_id][bufnr] then
                state.seen_buf[ns_id][bufnr] = true
                call_provider(state, ns_id, "on_buf", "buf", bufnr, state.tick)
            end

            if not state.disabled[ns_id] then
                local rv, _ok = call_provider(state, ns_id, "on_win", "win", winid, bufnr, topline0, botline0)
                if rv == false then
                    win_skip[ns_id] = true
                end
            end
        end
    end
end

function Decoration.on_line(win, row0)
    local state = active_state
    if not state then
        return
    end

    local bufnr = win.buffer.bufnr
    local winid = win.winnr
    local win_skip = state.win_skip_line[winid]

    for i = 1, #state.ids do
        local ns_id = state.ids[i]
        if not state.disabled[ns_id] and not (win_skip and win_skip[ns_id]) then
            call_provider(state, ns_id, "on_line", "line", winid, bufnr, row0)
        end
    end
end

function Decoration.is_redraw_active()
    return active_state ~= nil
end

function Decoration.add_ephemeral_extmark(bufnr, ns_id, id, mark)
    local state = active_state
    if not state then
        return false
    end

    state.ephemeral_by_buf[bufnr] = state.ephemeral_by_buf[bufnr] or {}
    state.ephemeral_by_buf[bufnr][ns_id] = state.ephemeral_by_buf[bufnr][ns_id] or {}
    state.ephemeral_by_buf[bufnr][ns_id][id] = mark
    return true
end

function Decoration.del_ephemeral_extmark(bufnr, ns_id, id)
    local state = active_state
    if not state then
        return false
    end

    local by_buf = state.ephemeral_by_buf[bufnr]
    local ns_marks = by_buf and by_buf[ns_id]
    if not ns_marks or ns_marks[id] == nil then
        return false
    end

    ns_marks[id] = nil
    return true
end

function Decoration.clear_ephemeral_namespace(bufnr, ns_id, line_start, line_end)
    local state = active_state
    if not state then
        return
    end

    local by_buf = state.ephemeral_by_buf[bufnr]
    if type(by_buf) ~= "table" then
        return
    end

    if ns_id == -1 then
        for _, ns_marks in pairs(by_buf) do
            clear_mark_table(ns_marks, line_start, line_end)
        end
        return
    end

    local ns_marks = by_buf[ns_id]
    if not ns_marks then
        return
    end
    clear_mark_table(ns_marks, line_start, line_end)
end

function Decoration.iter_extmarks(buf, visitor)
    local seen = {}
    local state = active_state

    if state then
        local by_buf = state.ephemeral_by_buf[buf.bufnr]
        if type(by_buf) == "table" then
            for ns, ns_marks in pairs(by_buf) do
                if type(ns_marks) == "table" then
                    seen[ns] = seen[ns] or {}
                    for id, mark in pairs(ns_marks) do
                        seen[ns][id] = true
                        visitor(ns, id, mark)
                    end
                end
            end
        end
    end

    local all = buf._extmarks
    if type(all) ~= "table" then
        return
    end

    for ns, ns_marks in pairs(all) do
        if type(ns_marks) == "table" then
            local seen_ns = seen[ns]
            for id, mark in pairs(ns_marks) do
                if not (seen_ns and seen_ns[id]) then
                    visitor(ns, id, mark)
                end
            end
        end
    end
end

return Decoration
