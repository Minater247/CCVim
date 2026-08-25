local BufAttach = {}

local Scopes = loadModule("lib.luaapi.scopes")

local state_by_buf = {}

local function ensure_buf_scope(bufnr)
    local bt = Scopes._b_by_buf[bufnr]
    if not bt then
        bt = {}
        Scopes._b_by_buf[bufnr] = bt
    end
    if type(bt.changedtick) ~= "number" then
        bt.changedtick = 0
    end
    return bt
end

local function ensure_state(bufnr)
    local st = state_by_buf[bufnr]
    if not st then
        st = {
            next_id = 1,
            listeners = {},
            order = {},
            utf_sizes_on_lines = 0,
        }
        state_by_buf[bufnr] = st
    end
    return st
end

local function remove_listener(st, id)
    local listener = st.listeners[id]
    if not listener then
        return
    end
    if listener.utf_sizes and type(listener.on_lines) == "function" then
        st.utf_sizes_on_lines = st.utf_sizes_on_lines - 1
    end
    st.listeners[id] = nil
    for i = 1, #st.order do
        if st.order[i] == id then
            table.remove(st.order, i)
            break
        end
    end
end

local function emit_one(listener, cb_name, args, detach_ids)
    local cb = listener and listener[cb_name]
    if type(cb) ~= "function" then
        return
    end

    local ok, rv = pcall(cb, table.unpack(args))
    if not ok then
        LOG_DEBUG("nvim_buf_attach callback error cb=%s err=%s", tostring(cb_name), tostring(rv))
        return
    end
    if rv ~= nil and rv ~= false then
        detach_ids[#detach_ids + 1] = listener.id
    end
end

local function emit(bufnr, cb_name, args)
    local st = state_by_buf[bufnr]
    if not st or #st.order == 0 then
        return
    end

    local detach_ids = {}
    for i = 1, #st.order do
        local id = st.order[i]
        local listener = st.listeners[id]
        if listener then
            emit_one(listener, cb_name, args, detach_ids)
        end
    end

    for i = 1, #detach_ids do
        local id = detach_ids[i]
        local listener = st.listeners[id]
        remove_listener(st, id)
        local cb = listener and listener.on_detach
        if type(cb) == "function" then
            local ok, err = pcall(cb, "detach", bufnr)
            if not ok then
                LOG_DEBUG("nvim_buf_attach callback error cb=on_detach err=%s", tostring(err))
            end
        end
    end

    if #st.order == 0 then
        state_by_buf[bufnr] = nil
    end
end

function BufAttach.ensure_buffer(bufnr)
    ensure_buf_scope(bufnr)
end

function BufAttach.get_changedtick(bufnr)
    return ensure_buf_scope(bufnr).changedtick
end

function BufAttach.bump_changedtick(bufnr)
    local bt = ensure_buf_scope(bufnr)
    bt.changedtick = bt.changedtick + 1
    return bt.changedtick
end

function BufAttach.attach(bufnr, opts)
    if type(bufnr) ~= "number" then
        return false
    end
    opts = opts or {}
    local st = ensure_state(bufnr)

    local id = st.next_id
    st.next_id = id + 1
    opts.id = id

    st.listeners[id] = opts
    st.order[#st.order + 1] = id
    if opts.utf_sizes and type(opts.on_lines) == "function" then
        st.utf_sizes_on_lines = st.utf_sizes_on_lines + 1
    end
    ensure_buf_scope(bufnr)
    return true, id
end

function BufAttach.detach(bufnr)
    local st = state_by_buf[bufnr]
    if not st then
        return false
    end

    local listeners = {}
    for i = 1, #st.order do
        local id = st.order[i]
        listeners[#listeners + 1] = st.listeners[id]
    end
    state_by_buf[bufnr] = nil

    for i = 1, #listeners do
        local listener = listeners[i]
        local cb = listener and listener.on_detach
        if type(cb) == "function" then
            local ok, err = pcall(cb, "detach", bufnr)
            if not ok then
                LOG_DEBUG("nvim_buf_attach callback error cb=on_detach err=%s", tostring(err))
            end
        end
    end
    return true
end

function BufAttach.notify_reload(bufnr)
    emit(bufnr, "on_reload", { "reload", bufnr })
end

function BufAttach.notify_changedtick(bufnr)
    local tick = BufAttach.bump_changedtick(bufnr)
    emit(bufnr, "on_changedtick", { "changedtick", bufnr, tick })
    return tick
end

function BufAttach.has_listeners(bufnr)
    local st = state_by_buf[bufnr]
    return st ~= nil and #st.order > 0
end

function BufAttach.has_utf_sizes_listener(bufnr)
    local st = state_by_buf[bufnr]
    return st ~= nil and st.utf_sizes_on_lines > 0
end

function BufAttach.notify_lines(bufnr, payload)
    payload = payload or {}
    local tick = BufAttach.bump_changedtick(bufnr)

    local first = payload.firstline or 0
    local last_old = payload.lastline or first
    local new_last = payload.new_lastline or first
    local byte_count = payload.byte_count or 0

    local line_args = { "lines", bufnr, tick, first, last_old, new_last, byte_count }
    if payload.deleted_codepoints ~= nil then
        line_args[#line_args + 1] = payload.deleted_codepoints
        line_args[#line_args + 1] = payload.deleted_codeunits or payload.deleted_codepoints
    end
    emit(bufnr, "on_lines", line_args)

    local bytes = payload.bytes
    if bytes then
        emit(bufnr, "on_bytes", {
            "bytes",
            bufnr,
            tick,
            bytes.start_row or 0,
            bytes.start_col or 0,
            bytes.start_byte or 0,
            bytes.old_end_row or 0,
            bytes.old_end_col or 0,
            bytes.old_end_byte or 0,
            bytes.new_end_row or 0,
            bytes.new_end_col or 0,
            bytes.new_end_byte or 0,
        })
    end

    return tick
end

return BufAttach
