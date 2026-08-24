local Command                     = {}

local Event                       = loadModule("lib.event")
local ExMsg                       = loadModule("lib.excmd.exmsg")
local PopupMenu                   = loadModule("lib.popupmenu")
local Key                         = loadModule("lib.key")
local RegisterUtil                = loadModule("lib.registers")
local Scopes                      = loadModule("lib.luaapi.scopes")
local VimExpr                     = loadModule("lib.excmd.vimxpr")
local Error                       = loadModule("lib.error")
local Visual                      = loadModule("lib.visual")

local POLICY_FULL, POLICY_CB_ONLY, POLICY_NOREMAP = 1, 2, 3
Command.POLICY_FULL = POLICY_FULL
Command.POLICY_CB_ONLY = POLICY_CB_ONLY
Command.POLICY_NOREMAP = POLICY_NOREMAP

local state
local cancel_ambiguous_timer
local reset_state
local execute_node
local clear_count
local select_mapping_context
local select_once

local macro_state = {
    recording_register = nil,
    executing_register = nil,
    last_recorded_register = nil,
    pending_action = nil, -- "record" | "execute" | nil
    recorded_keys = {},
    replaying_internal = false,
    defer_executing_clear = false,
}

-- =========================
-- Host-settable hooks / options
-- =========================
-- Called when a key must be emitted "raw" (i.e., no mapping matched).
-- Receives an array { key, ... }.
Command.emit_raw                  = function(keys_seq)
    local win = windows[curwin]

    for i = 1, #(keys_seq or {}) do
        local key = keys_seq[i]
        if vimmode == "insert" then
            local printable = key:printable()
            if printable == "<C-[>" then
                setMode("normal")
            else
                local emitted = key:emittable()
                if emitted ~= nil then
                    win:insertText(emitted)
                end
            end
        elseif vimmode == "select" then
            local emitted = key:emittable()
            if emitted ~= nil and emitted ~= "\b" and emitted ~= "\t" and Command.replace_select then
                Command.replace_select(emitted)
            end
        end
    end
end

-- In which modes counts are enabled (default: only normal mode).
Command.count_modes               = { normal = true }

-- Where to send keystrokes if overridden
Command.override_emitter          = {}
Command.emitter_names             = {}


local function seq_tostring(seq)
    local t = {}
    for i = 1, #seq do t[#t + 1] = seq[i]:printable() end
    return "{" .. table.concat(t, ",") .. "}"
end

local function node_keys_tostring(node)
    if not node or not node.children then return "{}" end
    local t = {}
    for k, _ in pairs(node.children) do t[#t + 1] = tostring(k) end
    table.sort(t)
    return "{" .. table.concat(t, ",") .. "}"
end

function Command.Log(...)
    if Command.debug then
        LOG_DEBUG(...)
    end
end

-- =========================
-- Utilities
-- =========================

local function normalize_seq(seq)
    local out = {}
    for i = 1, #seq do out[i] = seq[i] end
    return out
end

local function current_count_value()
    return state and state.count_committed and state.count_value or nil
end

local function top_level_normal_input()
    return vimmode == "normal"
        and #Command.override_emitter == 0
        and not state.pending_op
        and ((not state.active) or (#state.seq == 0 and state.best_node == nil))
end

local function key_char(key)
    local ch = key:emittable()
    if ch ~= nil and #ch == 1 then
        return ch
    end
    local printable = key:printable()
    if printable ~= nil and #printable == 1 then
        return printable
    end
    return nil
end

local function key_is_char(key, ch)
    return key_char(key) == ch
end

local function macro_register_info(key)
    local ch = key_char(key)
    if ch == nil then
        return nil
    end
    if ch:match("%a") then
        local lower = string.lower(ch)
        return lower, lower ~= ch
    end
    if ch:match("[%d\"%-#%*%+/:.=]") then
        return ch, false
    end
    return nil
end

local function append_recorded_key(key)
    if macro_state.recording_register == nil then
        return
    end
    local seq = macro_state.recorded_keys
    seq[#seq + 1] = key
end

local function start_macro_recording(reg, append)
    macro_state.recording_register = reg
    if append then
        macro_state.recorded_keys = RegisterUtil.entry_to_sequence(RegisterUtil.get_entry(reg))
    else
        macro_state.recorded_keys = {}
    end
end

local function stop_macro_recording()
    local reg = macro_state.recording_register
    if reg == nil then
        return
    end
    RegisterUtil.set_entry(reg, RegisterUtil.sequence_to_entry(macro_state.recorded_keys, "charwise"))
    macro_state.last_recorded_register = reg
    macro_state.recording_register = nil
    macro_state.recorded_keys = {}
end

local function finalize_pending_input()
    if #Command.override_emitter > 0 then
        reset_state()
        return true
    end

    if state.active then
        if state.best_node then
            local node = state.best_node
            cancel_ambiguous_timer()
            execute_node(node)
            reset_state()
            return true
        end
        reset_state()
    end
    return false
end

local function execute_macro(reg, count)
    local seq = RegisterUtil.entry_to_sequence(RegisterUtil.get_entry(reg))
    if not seq or #seq == 0 then
        return true
    end

    count = math.max(1, math.floor(tonumber(count) or 1))
    local prev_pending = macro_state.pending_action
    local prev_executing = macro_state.executing_register
    local prev_replaying = macro_state.replaying_internal
    local prev_defer = macro_state.defer_executing_clear
    macro_state.pending_action = nil
    macro_state.executing_register = reg
    macro_state.replaying_internal = true
    macro_state.defer_executing_clear = false

    local ok, err = xpcall(function()
        for _ = 1, count do
            for i = 1, #seq do
                Command.HandleKey(seq[i])
            end
            finalize_pending_input()
        end
    end, debug.traceback)

    macro_state.replaying_internal = prev_replaying
    macro_state.defer_executing_clear = true
    if prev_replaying then
        macro_state.executing_register = prev_executing
        macro_state.defer_executing_clear = prev_defer
    end
    macro_state.pending_action = prev_pending
    if not ok then
        if not prev_replaying then
            macro_state.executing_register = prev_executing
            macro_state.defer_executing_clear = prev_defer
        end
        error(err)
    end
    return true
end

local function handle_macro_control_key(k)
    if not top_level_normal_input() then
        return false
    end

    if macro_state.pending_action == "record" then
        local reg, append = macro_register_info(k)
        macro_state.pending_action = nil
        clear_count()
        if reg ~= nil then
            start_macro_recording(reg, append)
        end
        return true
    end

    if macro_state.pending_action == "execute" then
        local reg
        if key_is_char(k, "@") then
            reg = macro_state.last_recorded_register
        else
            reg = macro_register_info(k)
        end
        local count = current_count_value()
        macro_state.pending_action = nil
        clear_count()
        if reg ~= nil then
            return execute_macro(reg, count)
        end
        return true
    end

    if macro_state.recording_register ~= nil and key_is_char(k, "q") then
        stop_macro_recording()
        clear_count()
        return true
    end

    if macro_state.recording_register == nil and key_is_char(k, "q") then
        macro_state.pending_action = "record"
        clear_count()
        return true
    end

    if key_is_char(k, "@") then
        macro_state.pending_action = "execute"
        return true
    end

    return false
end

local function node_has_children(node)
    if not node or not node.children then return false end
    return next(node.children) ~= nil
end

-- Mode expansion: accept full names, alias string like "ni", or list/table
local MODE_ALIASES = {
    n = "normal",
    i = "insert",
    v = { "visual", "select" },
    x = "visual",
    s = "select",
    o = "operator",
    l = "lang",
    c = "cmdline",
    t = "terminal",
}
local VALID_MODES  = {
    normal = true,
    insert = true,
    visual = true,
    select = true,
    operator = true,
    lang = true,
    cmdline = true,
    terminal = true,
}

local function expand_modes(modes)
    local out, seen = {}, {}
    local t = type(modes)
    if t == "string" then
        if modes == "" then
            -- Match Neovim `:map` semantics for empty mode.
            out[1] = "normal"
            out[2] = "visual"
            out[3] = "select"
            out[4] = "operator"
            return out
        end
        if VALID_MODES[modes] then
            out[1] = modes
        else
            -- Treat as alias string like "ni"
            for i = 1, #modes do
                local ch = modes:sub(i, i)
                local expanded = MODE_ALIASES[ch]
                if not expanded then
                    error(("unknown mode alias '%s' in '%s'"):format(ch, modes))
                end
                if type(expanded) == "string" then expanded = { expanded } end
                for j = 1, #expanded do
                    local full = expanded[j]
                    if not seen[full] then
                        out[#out + 1] = full
                        seen[full] = true
                    end
                end
            end
        end
    elseif t == "table" then
        for _, m in ipairs(modes) do
            if VALID_MODES[m] then
                if not seen[m] then
                    out[#out + 1] = m; seen[m] = true
                end
            elseif type(m) == "string" and #m == 1 and MODE_ALIASES[m] then
                local full = MODE_ALIASES[m]
                if not seen[full] then
                    out[#out + 1] = full; seen[full] = true
                end
            else
                error(("unknown mode '%s'"):format(tostring(m)))
            end
        end
    else
        error("modes must be string or table")
    end
    return out
end

-- =========================
-- Mapping storage (per-mode tries)
-- node: { children={ [keynum]=node }, callback|rhs_seq, recursive, ... }
-- =========================
local user_global_mappings = {} -- user_global_mappings[mode_fullname] = root node
local builtin_mappings = {}     -- builtin_mappings[mode_fullname] = root node
local mapping_generation = 0
local composite_cache = setmetatable({}, { __mode = "k" })

local function mappings_changed()
    mapping_generation = mapping_generation + 1
end

local function root_for_mode(storage, mode_full)
    local r = storage[mode_full]
    if not r then
        r = { children = {} }
        storage[mode_full] = r
    end
    return r
end

local function user_global_root_for_mode(mode_full)
    return root_for_mode(user_global_mappings, mode_full)
end

local function builtin_root_for_mode(mode_full)
    return root_for_mode(builtin_mappings, mode_full)
end

-- Are all keys in a sequence digits?
local function seq_is_digit_only(seq)
    if not seq or #seq == 0 then return false end
    for i = 1, #seq do
        if seq[i]:ToDigit() == nil then return false end
    end
    return true
end

-- Parse leading digits from a key sequence into a number (without committing state.count_*)
local function leading_digits_value(seq)
    if not seq or #seq == 0 then return nil end
    local val = nil
    for i = 1, #seq do
        local d = seq[i]:ToDigit()
        if d == nil then break end
        val = (val or 0) * 10 + d
    end
    return val
end


-- Ensure a buffer-local root for a mode, creating tables as needed.
local function ensure_buffer_local_root(buf, mode_full)
    if not buf.local_mappings then buf.local_mappings = {} end
    local r = buf.local_mappings[mode_full]
    if not r then
        r = { children = {} }
        buf.local_mappings[mode_full] = r
    end
    return r
end

-- Build a composite node that prefers buffer-local leaves but merges children from both.
local function _composite_node(buf_node, glob_node)
    if not buf_node then return glob_node or { children = {} } end
    if not glob_node then return buf_node end

    local composite = { children = {} }
    local buf_has_leaf = (buf_node.callback ~= nil) or (buf_node.rhs_seq ~= nil) or (buf_node.expr_rhs ~= nil)
        or (buf_node.operator_cb ~= nil) or (buf_node.motion_root ~= nil)
    local glob_has_leaf = (glob_node.callback ~= nil) or (glob_node.rhs_seq ~= nil) or (glob_node.expr_rhs ~= nil)
        or (glob_node.operator_cb ~= nil) or (glob_node.motion_root ~= nil)

    if buf_has_leaf then
        composite.callback    = buf_node.callback
        composite.rhs_seq     = buf_node.rhs_seq
        composite.expr        = buf_node.expr
        composite.expr_rhs    = buf_node.expr_rhs
        composite.replace_keycodes = buf_node.replace_keycodes
        composite.recursive   = buf_node.recursive
        composite.operator_cb = buf_node.operator_cb
        composite.motion_root = buf_node.motion_root
        composite.map_meta    = buf_node.map_meta
        composite.select_as_visual = buf_node.select_as_visual
    else
        composite.callback    = glob_node.callback
        composite.rhs_seq     = glob_node.rhs_seq
        composite.expr        = glob_node.expr
        composite.expr_rhs    = glob_node.expr_rhs
        composite.replace_keycodes = glob_node.replace_keycodes
        composite.recursive   = glob_node.recursive
        composite.operator_cb = glob_node.operator_cb
        composite.motion_root = glob_node.motion_root
        composite.map_meta    = glob_node.map_meta
        composite.select_as_visual = glob_node.select_as_visual
    end

    local keys = {}
    if buf_has_leaf then
        if buf_node.children then
            for k in pairs(buf_node.children) do
                keys[k] = true
            end
        end
    elseif glob_has_leaf then
        if glob_node.children then
            for k in pairs(glob_node.children) do
                keys[k] = true
            end
        end
    else
        if buf_node.children then for k in pairs(buf_node.children) do keys[k] = true end end
        if glob_node.children then for k in pairs(glob_node.children) do keys[k] = true end end
    end
    for k in pairs(keys) do
        composite.children[k] = _composite_node(
            buf_node.children and buf_node.children[k],
            glob_node.children and glob_node.children[k]
        )
    end
    return composite
end


-- Composite *active* root for the current buffer+mode.
-- Precedence: buffer-local user > global user > builtin.
local function composite_root_for_mode(mode_full)
    local buf = windows[curwin].buffer
    local by_mode = composite_cache[buf]
    if by_mode then
        local cached = by_mode[mode_full]
        if cached and cached.generation == mapping_generation then
            return cached.root
        end
    else
        by_mode = {}
        composite_cache[buf] = by_mode
    end

    local builtin = builtin_mappings[mode_full] or { children = {} }
    local global_user = user_global_mappings[mode_full] or { children = {} }
    local local_user = buf.local_mappings and buf.local_mappings[mode_full]
    local global_root = _composite_node(global_user, builtin)
    local root = _composite_node(local_user, global_root)
    by_mode[mode_full] = {
        generation = mapping_generation,
        root = root,
    }
    return root
end

local function _get_user_insert_root(mode_full, opts)
    opts = opts or {}
    if opts.buffer then
        return ensure_buffer_local_root(opts.buffer, mode_full)
    elseif opts.buffer_local then
        local buf = windows[curwin].buffer
        return ensure_buffer_local_root(buf, mode_full)
    else
        return user_global_root_for_mode(mode_full)
    end
end

local function _get_existing_user_root(mode_full, opts)
    if opts and opts.buffer then
        local buf = opts.buffer
        return buf.local_mappings and buf.local_mappings[mode_full]
    elseif opts and opts.buffer_local then
        local buf = windows[curwin].buffer
        return buf.local_mappings and buf.local_mappings[mode_full]
    else
        return user_global_mappings[mode_full]
    end
end

local function _clear_leaf(node)
    node.callback = nil
    node.callback_takes_count = nil
    node.rhs_seq = nil
    node.expr = nil
    node.expr_rhs = nil
    node.replace_keycodes = nil
    node.recursive = nil
    node.operator_cb = nil
    node.motion_root = nil
    node.map_meta = nil
    node.select_as_visual = nil
end

local function _node_is_empty(node)
    return (not node.callback)
        and (not node.rhs_seq)
        and (not node.expr_rhs)
        and (not node.operator_cb)
        and (not node.motion_root)
        and (not node_has_children(node))
end

local function _delete_mapping(root, seq_nums)
    if not root then return false end
    if not seq_nums or #seq_nums == 0 then return false end

    local stack = {}
    local node = root
    for i = 1, #seq_nums do
        local keynum = seq_nums[i].numeric
        local child = node.children and node.children[keynum]
        if not child then return false end
        stack[#stack + 1] = { parent = node, key = keynum, node = child }
        node = child
    end

    _clear_leaf(node)
    for i = #stack, 1, -1 do
        local frame = stack[i]
        if _node_is_empty(frame.node) then
            frame.parent.children[frame.key] = nil
        else
            break
        end
    end
    return true
end

local function _clear_root(root)
    if not root then return end
    root.children = {}
    _clear_leaf(root)
end

local function insert_callback_mapping(mode_full, seq_nums, callback, opts)
    opts = opts or {}
    local node = _get_user_insert_root(mode_full, opts)
    local is_buffer_local = (opts.buffer ~= nil) or opts.buffer_local
    local scope_suffix = ""
    if is_buffer_local then
        scope_suffix = " [buf-local]"
    end
    for i = 1, #seq_nums do
        local k = seq_nums[i]
        local child = node.children[k.numeric]
        if not child then
            child = { children = {} }
            node.children[k.numeric] = child
        end
        node = child
    end
    node.callback  = callback
    node.callback_takes_count = false
    node.rhs_seq   = nil
    node.expr_rhs  = nil
    node.recursive = nil
    node.map_meta  = opts.map_meta
    node.select_as_visual = opts.select_as_visual == true
    if opts.expr == true then
        node.expr = true
        node.replace_keycodes = opts.replace_keycodes ~= false
    else
        node.expr = nil
        node.replace_keycodes = nil
    end
    Command.Log(
        "map-callback  mode=%s seq=%s cb=%s%s",
        mode_full,
        seq_tostring(seq_nums),
        tostring(callback),
        scope_suffix
    )
    mappings_changed()
end

local function insert_builtin_callback_mapping(mode_full, seq_nums, callback)
    local node = builtin_root_for_mode(mode_full)
    for i = 1, #seq_nums do
        local k = seq_nums[i]
        local child = node.children[k.numeric]
        if not child then
            child = { children = {} }
            node.children[k.numeric] = child
        end
        node = child
    end
    node.callback  = callback
    node.callback_takes_count = true
    node.rhs_seq   = nil
    node.recursive = nil
    Command.Log("map-builtin-callback mode=%s seq=%s cb=%s", mode_full, seq_tostring(seq_nums), tostring(callback))
    mappings_changed()
end

local function insert_keys_mapping(mode_full, seq_nums, rhs_seq, recursive, opts)
    opts = opts or {}
    local node = _get_user_insert_root(mode_full, opts)
    local is_buffer_local = (opts.buffer ~= nil) or opts.buffer_local
    local scope_suffix = ""
    if is_buffer_local then
        scope_suffix = " [buf-local]"
    end
    for i = 1, #seq_nums do
        local k = seq_nums[i]
        local child = node.children[k.numeric]
        if not child then
            child = { children = {} }
            node.children[k.numeric] = child
        end
        node = child
    end
    node.callback  = nil
    if opts.expr == true then
        node.expr = true
        node.expr_rhs = opts.expr_rhs
        node.rhs_seq = nil
        node.replace_keycodes = opts.replace_keycodes ~= false
    else
        node.expr = nil
        node.expr_rhs = nil
        node.rhs_seq = normalize_seq(rhs_seq)
        node.replace_keycodes = nil
    end
    node.recursive = recursive ~= false
    node.map_meta  = opts.map_meta
    node.select_as_visual = opts.select_as_visual == true

    local rhs_log
    if node.expr then
        rhs_log = node.expr_rhs
    else
        rhs_log = seq_tostring(node.rhs_seq)
    end

    Command.Log(
        "map-keys      mode=%s lhs=%s rhs=%s recursive=%s%s",
        mode_full,
        seq_tostring(seq_nums),
        rhs_log,
        tostring(node.recursive),
        scope_suffix
    )
    mappings_changed()
end

local function _seq_to_map_text(seq)
    local out = {}
    for i = 1, #(seq or {}) do
        out[#out + 1] = Key.to_termcode_string(seq[i], { force_keycode = false, from_expr = false })
    end
    return Key.keytrans(table.concat(out))
end


-- =========================
-- Public API: map / noremap with mode(s)
-- modes: full names ("normal","insert","visual"), alias string ("ni"), or list
-- =========================
local function expanded_user_modes(modes, opts)
    local expanded = expand_modes(modes)
    local visual, select_mode
    for i = 1, #expanded do
        visual = visual or expanded[i] == "visual"
        select_mode = select_mode or expanded[i] == "select"
    end
    if not (visual and select_mode) then return expanded, opts end

    local select_opts = {}
    for k, v in pairs(opts or {}) do select_opts[k] = v end
    select_opts.select_as_visual = true
    return expanded, opts, select_opts
end

function Command.map_callback(modes, lhs_seq, callback, opts)
    local seq = normalize_seq(lhs_seq)
    local expanded, default_opts, select_opts = expanded_user_modes(modes, opts)
    for _, m in ipairs(expanded) do
        insert_callback_mapping(m, seq, callback, m == "select" and select_opts or default_opts)
    end
end

function Command.map_builtin_callback(modes, lhs_seq, callback)
    local seq = normalize_seq(lhs_seq)
    for _, m in ipairs(expand_modes(modes)) do
        insert_builtin_callback_mapping(m, seq, callback)
    end
end

function Command.remap_keys(modes, lhs_seq, rhs_seq, opts)
    opts = opts or {}
    local lhs = normalize_seq(lhs_seq)
    local expanded, default_opts, select_opts = expanded_user_modes(modes, opts)
    for _, m in ipairs(expanded) do
        insert_keys_mapping(m, lhs, rhs_seq, true, m == "select" and select_opts or default_opts)
    end
end

function Command.noremap_keys(modes, lhs_seq, rhs_seq, opts)
    opts = opts or {}
    local lhs = normalize_seq(lhs_seq)
    local expanded, default_opts, select_opts = expanded_user_modes(modes, opts)
    for _, m in ipairs(expanded) do
        insert_keys_mapping(m, lhs, rhs_seq, false, m == "select" and select_opts or default_opts)
    end
end

function Command.unmap_keys(modes, lhs_seq, opts)
    local lhs = normalize_seq(lhs_seq)
    for _, m in ipairs(expand_modes(modes)) do
        local root = _get_existing_user_root(m, opts)
        if _delete_mapping(root, lhs) then
            mappings_changed()
        end
    end
end

function Command.clear_mappings(modes, opts)
    for _, m in ipairs(expand_modes(modes)) do
        local root = _get_existing_user_root(m, opts)
        if root then
            _clear_root(root)
            mappings_changed()
        end
    end
end

local function _rhs_seq_to_text(rhs_seq)
    local out = {}
    for i = 1, #rhs_seq do
        local key = rhs_seq[i]
        local ch = key:emittable()
        if ch == nil then
            ch = key:printable()
        end
        out[#out + 1] = ch
    end
    return table.concat(out)
end

local function _subtree_has_rhs(node, needle)
    if not node then return false end

    if node.rhs_seq or node.expr_rhs ~= nil then
        local rhs = node.expr_rhs or _rhs_seq_to_text(node.rhs_seq)
        if rhs:find(needle, 1, true) then
            return true
        end
    end

    for _, child in pairs(node.children or {}) do
        if _subtree_has_rhs(child, needle) then
            return true
        end
    end
    return false
end

function Command.has_map_to(modes, what)
    local needle = tostring(what or "")
    local buf = windows[curwin].buffer

    for _, m in ipairs(expand_modes(modes)) do
        if _subtree_has_rhs(user_global_mappings[m], needle) then
            return true
        end
        if _subtree_has_rhs(buf.local_mappings and buf.local_mappings[m], needle) then
            return true
        end
    end
    return false
end

local function _node_rhs(node)
    if not node then
        return nil
    end
    if node.expr_rhs ~= nil then
        return node.expr_rhs
    end
    if not node.rhs_seq then
        return nil
    end
    if #node.rhs_seq == 0 then
        return "<Nop>"
    end
    return _rhs_seq_to_text(node.rhs_seq)
end

local function _find_rhs_in_subtree(node)
    if not node then return nil end

    local rhs = _node_rhs(node)
    if rhs then
        return rhs
    end

    for _, child in pairs(node.children or {}) do
        local found = _find_rhs_in_subtree(child)
        if found then
            return found
        end
    end
    return nil
end

local function _mapcheck_in_root(root, lhs_seq)
    if not root then
        return nil
    end

    local node = root
    local prefix_rhs = _node_rhs(node)

    for i = 1, #lhs_seq do
        local child = node.children and node.children[lhs_seq[i].numeric]
        if not child then
            return prefix_rhs
        end
        node = child
        local here_rhs = _node_rhs(node)
        if here_rhs then
            prefix_rhs = here_rhs
        end
    end

    if prefix_rhs then
        return prefix_rhs
    end
    return _find_rhs_in_subtree(node)
end

local function _lookup_node_in_root(root, lhs_seq)
    if not root then
        return nil
    end
    local node = root
    for i = 1, #lhs_seq do
        local child = node.children and node.children[lhs_seq[i].numeric]
        if not child then
            return nil
        end
        node = child
    end
    return node
end

local function _node_has_mapping(node)
    if not node then
        return false
    end
    if node.callback ~= nil or node.rhs_seq ~= nil or node.expr_rhs ~= nil or node.operator_cb ~= nil then
        return true
    end
    return node_has_children(node)
end

function Command.mapcheck(modes, lhs_seq)
    local buf = windows[curwin].buffer

    for _, m in ipairs(expand_modes(modes)) do
        local local_root = buf.local_mappings and buf.local_mappings[m]
        local local_rhs = _mapcheck_in_root(local_root, lhs_seq)
        if local_rhs then
            return local_rhs
        end

        local global_rhs = _mapcheck_in_root(user_global_mappings[m], lhs_seq)
        if global_rhs then
            return global_rhs
        end
    end

    return ""
end

function Command.has_mapping(modes, lhs_seq)
    local buf = windows[curwin].buffer

    for _, m in ipairs(expand_modes(modes)) do
        local local_root = buf.local_mappings and buf.local_mappings[m]
        if _node_has_mapping(_lookup_node_in_root(local_root, lhs_seq)) then
            return true
        end

        if _node_has_mapping(_lookup_node_in_root(user_global_mappings[m], lhs_seq)) then
            return true
        end

        if _node_has_mapping(_lookup_node_in_root(builtin_mappings[m], lhs_seq)) then
            return true
        end
    end

    return false
end

function Command.maparg(modes, lhs_seq)
    local buf = windows[curwin].buffer

    for _, m in ipairs(expand_modes(modes)) do
        local local_root = buf.local_mappings and buf.local_mappings[m]
        local local_node = _lookup_node_in_root(local_root, lhs_seq)
        if local_node and (
            local_node.callback ~= nil
            or local_node.rhs_seq ~= nil
            or local_node.expr_rhs ~= nil
            or local_node.operator_cb ~= nil
        ) then
            return local_node, true
        end

        local global_node = _lookup_node_in_root(user_global_mappings[m], lhs_seq)
        if global_node and (
            global_node.callback ~= nil
            or global_node.rhs_seq ~= nil
            or global_node.expr_rhs ~= nil
            or global_node.operator_cb ~= nil
        ) then
            return global_node, false
        end
    end

    return nil, false
end

function Command.mapping_to_string(node)
    if not node then
        return ""
    end
    if node.expr_rhs ~= nil then
        return node.expr_rhs
    end
    if not node.rhs_seq then
        return ""
    end
    local meta = node.map_meta or {}
    return meta.expanded_rhs or _seq_to_map_text(node.rhs_seq)
end

function Command.mapping_to_dict(node, is_buffer_local, lhs_seq)
    if not node or (not node.rhs_seq and node.expr_rhs == nil) then
        return {}
    end

    local meta = node.map_meta or {}
    local sid = tonumber(meta.sid)
    if sid == nil then
        sid = 0
    end

    return {
        lhs = meta.expanded_lhs or _seq_to_map_text(lhs_seq),
        rhs = meta.raw_rhs or node.expr_rhs or _seq_to_map_text(node.rhs_seq),
        sid = sid,
        buffer = is_buffer_local and 1 or 0,
        noremap = (node.recursive == false) and 1 or 0,
    }
end

-- Convenience wrappers for mappings
function Command.nmap_callback(lhs_seq, cb, opts) return Command.map_callback("normal", lhs_seq, cb, opts) end

function Command.imap_callback(lhs_seq, cb, opts) return Command.map_callback("insert", lhs_seq, cb, opts) end

function Command.nimap_callback(lhs_seq, cb, opts) return Command.map_callback("ni", lhs_seq, cb, opts) end

function Command.nmap_builtin_callback(lhs_seq, cb) return Command.map_builtin_callback("normal", lhs_seq, cb) end

function Command.imap_builtin_callback(lhs_seq, cb) return Command.map_builtin_callback("insert", lhs_seq, cb) end

function Command.nimap_builtin_callback(lhs_seq, cb) return Command.map_builtin_callback("ni", lhs_seq, cb) end

function Command.vmap_builtin_callback(lhs_seq, cb) return Command.map_builtin_callback("visual", lhs_seq, cb) end

function Command.smap_builtin_callback(lhs_seq, cb) return Command.map_builtin_callback("select", lhs_seq, cb) end

function Command.nnoremap_keys(lhs, rhs, opts) return Command.noremap_keys("normal", lhs, rhs, opts) end

function Command.inoremap_keys(lhs, rhs, opts) return Command.noremap_keys("insert", lhs, rhs, opts) end

function Command.nmap_keys(lhs, rhs, opts) return Command.remap_keys("normal", lhs, rhs, opts) end

function Command.imap_keys(lhs, rhs, opts) return Command.remap_keys("insert", lhs, rhs, opts) end

-- =========================
-- Operators with explicit, per-operator motions (normal mode)
-- Motions do not have callbacks; the operator's callback receives the motion *name*.
-- =========================
local function _insert_operator_with_motions(op_lhs_seq, operator_cb, motions_spec, is_builtin)
    local op_seq = normalize_seq(op_lhs_seq)
    local node = is_builtin and builtin_root_for_mode("normal") or user_global_root_for_mode("normal")
    for i = 1, #op_seq do
        local k = op_seq[i]
        local child = node.children[k.numeric]
        if not child then
            child = { children = {} }; node.children[k.numeric] = child
        end
        node = child
    end
    node.operator_cb = operator_cb
    node.callback    = nil
    node.rhs_seq     = nil
    node.recursive   = nil
    if not node.motion_root then node.motion_root = { children = {} } end
    Command.Log("map-operator(mode=normal builtin=%s) seq=%s", tostring(is_builtin == true), seq_tostring(op_seq))

    local function add_motion(lhs_seq, motion_name)
        local mnode = node.motion_root
        local mseq = normalize_seq(lhs_seq)
        for i = 1, #mseq do
            local k = mseq[i]
            local child = mnode.children[k.numeric]
            if not child then
                child = { children = {} }; mnode.children[k.numeric] = child
            end
            mnode = child
        end
        mnode.motion_name = motion_name
        Command.Log("  op-motion name=%s lhs=%s", motion_name, seq_tostring(mseq))
    end

    assert(type(motions_spec) == "table", "motions_spec must be a table")
    local is_map = false
    for k, _ in pairs(motions_spec) do
        if type(k) ~= "number" then
            is_map = true; break
        end
    end
    if is_map then
        for name, lhs in pairs(motions_spec) do add_motion(lhs, name) end
    else
        for _, item in ipairs(motions_spec) do
            assert(type(item) == "table" and item.name and item.lhs, "motion item must have name,lhs")
            add_motion(item.lhs, item.name)
        end
    end
    mappings_changed()
    return node
end

function Command.nmap_operator_with_motions(op_lhs_seq, operator_cb, motions_spec)
    return _insert_operator_with_motions(op_lhs_seq, operator_cb, motions_spec, false)
end

function Command.nmap_builtin_operator_with_motions(op_lhs_seq, operator_cb, motions_spec)
    return _insert_operator_with_motions(op_lhs_seq, operator_cb, motions_spec, true)
end

-- =========================
-- State machine
-- =========================
state = {
    active          = false,
    mode            = "normal", -- always full name; kept in sync with vimmode below
    node            = nil,
    seq             = {},

    -- Best complete match so far (node that has callback or rhs_seq)
    best_node       = nil,

    timer_id        = nil,

    -- Count handling
    count_tentative = false, -- leading digits typed while also following a digit-leading mapping path
    count_committed = false, -- we decided it's definitely a count (no digit-leading mapping path exists)
    count_value     = nil,   -- integer count value
    count_codes     = {},    -- digits seen (integers 0..9)

    -- Operator handling
    pending_op      = nil,   -- { cb=function, op_count_base=number|nil, motion_root=node }
    op_motion       = nil,   -- { active=true, node, seq, best_node, count_committed, count_value, count_codes }
    skip_op_once    = false, -- suppress global-operator recognition once
}

local function _cancel_timer(id)
    Event.CancelTimer(id)
end

cancel_ambiguous_timer = function()
    if state.timer_id ~= nil then
        _cancel_timer(state.timer_id)
        Command.Log("TIMER cancel")
        state.timer_id = nil
    end
end

local function reset_mapping_only()
    cancel_ambiguous_timer()

    state.active = false
    state.node = nil
    state.seq = {}
    state.best_node = nil
    state.mode = vimmode -- vimmode should be "normal"/"insert"/"visual"
end

clear_count = function()
    state.count_tentative = false
    state.count_committed = false
    state.count_value     = nil
    state.count_codes     = {}
end

local function _clear_op_pending()
    state.pending_op = nil
    state.op_motion  = nil
end

reset_state = function()
    reset_mapping_only()
    clear_count()
    _clear_op_pending()
end

local function start_ambiguous_timer()
    cancel_ambiguous_timer()
    if not options.get("timeout") then return end
    Command.Log("TIMER start (best=%s)", tostring(state.best_node))
    local id = Event.StartTimer(options.get("timeoutlen") / 1000, Command._on_timeout)
    state.timer_id = id
end

-- =========================
-- Execution helpers
-- =========================
local function _with_undo_block(fn)
    local win = windows[curwin]
    local buf = win.buffer
    buf:undo_begin(win)
    local ok, rv = pcall(fn)
    buf:undo_end(win)
    if not ok then
        error(rv)
    end
    return rv
end

local function _set_v_count_context(count)
    local current = count or 0
    local vvars = Scopes._v
    vvars.prevcount = vvars.count
    vvars.count = current
    vvars.count1 = (current ~= 0) and current or 1
end

local function _expr_result_to_text(rv)
    local t = type(rv)
    if t == "string" then
        return rv
    end
    if t == "number" then
        return tostring(rv)
    end
    return ""
end

local function _vim_expr_result_to_text(rv)
    local t = type(rv)
    if t == "string" then
        return rv
    end
    if t == "number" then
        return tostring(rv)
    end
    if t == "boolean" then
        return rv and "v:true" or "v:false"
    end
    if t == "nil" then
        return "v:null"
    end
    return tostring(rv)
end

local function execute_node_inner(node)
    local cnt = (state.count_committed and state.count_value)
    Command.Log(
        "execute cb=%s rhs_len=%d recursive=%s count=%d",
        tostring(node.callback),
        node.rhs_seq and #node.rhs_seq or 0,
        tostring(node.recursive),
        cnt
    )

    if node.callback then
        _set_v_count_context(cnt)
        local rv
        if node.expr then
            local policy = node.recursive and POLICY_FULL or POLICY_NOREMAP
            cancel_ambiguous_timer()
            reset_mapping_only()
            _with_undo_block(function()
                if node.callback_takes_count then
                    rv = node.callback(cnt)
                else
                    rv = node.callback()
                end
                if rv and Error.IsError(rv) then
                    ExMsg.echoerr(rv:toString())
                    return
                end

                local text = _expr_result_to_text(rv)
                if text == "" then
                    return
                end

                if node.replace_keycodes == false then
                    text = text:gsub("<", "<lt>")
                end

                local seq = Key.strtoseq(text)
                if #seq > 0 then
                    Command._feed_seq_with_policy(seq, policy)
                end
            end)
            return
        end

        rv = _with_undo_block(function()
            if node.callback_takes_count then
                return node.callback(cnt)
            end
            return node.callback()
        end)
        if rv and Error.IsError(rv) then ExMsg.echoerr(rv:toString()) end
        return
    end

    if node.expr_rhs ~= nil then
        _set_v_count_context(cnt)
        local policy = node.recursive and POLICY_FULL or POLICY_NOREMAP
        cancel_ambiguous_timer()
        reset_mapping_only()
        _with_undo_block(function()
            local rv = VimExpr.evaluate(node.expr_rhs)
            if rv and Error.IsError(rv) then
                ExMsg.echoerr(rv:toString())
                return
            end

            local text = _vim_expr_result_to_text(rv)
            if text == "" then
                return
            end

            if node.replace_keycodes == false then
                text = text:gsub("<", "<lt>")
            end

            local seq = Key.strtoseq(text)
            if #seq > 0 then
                Command._feed_seq_with_policy(seq, policy)
            end
        end)
        return
    end

    if node.rhs_seq and #node.rhs_seq > 0 then
        _set_v_count_context(cnt)
        local rhs = node.rhs_seq
        cancel_ambiguous_timer()
        reset_mapping_only()
        _with_undo_block(function()
            Command._feed_seq_with_policy(rhs, node.recursive and POLICY_FULL or POLICY_CB_ONLY)
        end)
        return
    end
end

local function restore_select(win, selection)
    if vimmode == "visual" and win.visual_anchor then
        setMode("select")
        return
    end
    win.visual_anchor = {
        lnum = selection.anchor.lnum,
        col = selection.anchor.col,
    }
    win.visual_kind = selection.kind
    win:cursorSet(selection.cursor.col, selection.cursor.lnum)
    setMode("select")
end

execute_node = function(node)
    if vimmode ~= "select" or not node.select_as_visual then
        return execute_node_inner(node)
    end

    local win = windows[curwin]
    local context = {
        win = win,
        buf = win.buffer,
        selection = Visual.selection(win),
        previous = select_mapping_context,
    }
    select_mapping_context = context
    win.select_operator_charwise = true
    setMode("visual")
    local ok, result = pcall(execute_node_inner, node)

    local same_target = windows[curwin] == win and win.buffer == context.buf
    if ok and same_target and not context.cancel and context.selection
        and vimmode ~= "insert" and vimmode ~= "cmdline" and vimmode ~= "select"
    then
        restore_select(win, context.selection)
    end
    win.select_operator_charwise = nil
    select_mapping_context = context.previous
    if not ok then error(result) end
    return result
end

function Command.cancel_select_reselect()
    if select_mapping_context then select_mapping_context.cancel = true end
    if select_once then select_once.cancel = true end
end

function Command.begin_select_once()
    local win = windows[curwin]
    select_once = {
        win = win,
        buf = win.buffer,
        armed = false,
    }
    win.select_operator_charwise = true
    setMode("visual")
end

local function finish_select_once()
    local context = select_once
    if not context then return end
    if not context.armed then
        context.armed = true
        return
    end
    if state.active or #Command.override_emitter > 0 then return end

    local win = context.win
    if not context.cancel and windows[curwin] == win and win.buffer == context.buf
        and vimmode == "visual" and win.visual_anchor
    then
        setMode("select")
    end
    win.select_operator_charwise = nil
    select_once = nil
end


-- ===== Operator-pending motion helpers =====
local function _new_motion_state(motion_root)
    return {
        active          = true,
        node            = motion_root or { children = {} },
        seq             = {},
        best_node       = nil,
        count_value     = nil,
        count_codes     = {},
        count_committed = false,
        count_tentative = false,
    }
end

-- Enter operator-pending via GLOBAL recognition (single-key operator).
-- Snapshot an op_count base from committed count OR the leading digits already typed in state.seq.
local function _enter_op_pending_global(op_node)
    local base = state.count_committed and state.count_value or leading_digits_value(state.seq)
    state.pending_op = {
        cb            = op_node.operator_cb,
        op_count_base = base, -- may be nil; prefer committed count when executing
        motion_root   = op_node.motion_root or { children = {} },
    }
    state.op_motion = _new_motion_state(state.pending_op.motion_root)
end

local function _execute_operator_with_motion(motion_leaf)
    local op_cnt  = (state.count_committed and state.count_value) or
        (state.pending_op and state.pending_op.op_count_base)
    local ms      = state.op_motion or {}
    local mot_cnt = (ms.count_committed and ms.count_value)
    local total
    if op_cnt or mot_cnt then
        total = (op_cnt or 1) * (mot_cnt or 1)
    end
    local mname   = motion_leaf.motion_name or "<motion>"

    Command.Log("operator+motion name=%s op=%d motion=%d total=%d", mname, op_cnt, mot_cnt, total)

    cancel_ambiguous_timer()
    -- Operator callback signature:
    --   cb(total_count, motion_name, op_count, motion_count)
    _with_undo_block(function()
        state.pending_op.cb(total, mname, op_cnt, mot_cnt)
    end)
    reset_state()
end

local function _single_key_operator_node(root, keynum)
    local node = root.children[keynum]
    return (node and node.operator_cb) and node
end

local function _op_motion_step(code)
    local ms = state.op_motion
    if not ms or not ms.active then return false end

    local d = code:ToDigit()
    if #ms.seq == 0 and d ~= nil then
        -- Motion-local count: digits immediately after operator (commit directly).
        ms.count_committed                  = true
        ms.count_value                      = (ms.count_value or 0) * 10 + d
        ms.count_codes[#ms.count_codes + 1] = d
        return true
    end

    -- Only traverse this operator's motion trie; unknown keys are NOT motions.
    local next_node = ms.node and ms.node.children and ms.node.children[code.numeric]
    if not next_node then
        return false
    end

    ms.node             = next_node
    ms.seq[#ms.seq + 1] = code

    local at_leaf       = next_node.motion_name ~= nil
    local has_more      = node_has_children(next_node)

    if at_leaf then
        ms.best_node = next_node
        if not has_more then
            _execute_operator_with_motion(next_node)
            return true
        else
            start_ambiguous_timer()
            return true
        end
    end
    return true
end

-- Process a sequence through the mapper under a given policy.
function Command._feed_seq_with_policy(seq, policy, capture_counts)
    cancel_ambiguous_timer()
    reset_mapping_only()
    local allow_counts = capture_counts == true

    local consumed_any = false
    for i = 1, #seq do
        local code = seq[i]

        if handle_macro_control_key(code) then
            consumed_any = true
            goto continue
        end

        append_recorded_key(code)

        if #Command.override_emitter > 0 then
            Command.override_emitter[#Command.override_emitter](code)
            consumed_any = true
        else
            local consumed = Command._handle_key_with_policy(code, policy, allow_counts)
            if not consumed then
                if #Command.override_emitter > 0 then
                    Command.override_emitter[#Command.override_emitter](code)
                else
                    Command.emit_raw({ code })
                end
            end
            consumed_any = consumed_any or consumed
        end

        ::continue::
    end

    -- If override turned on during the loop, don't try to execute a pending leaf.
    if #Command.override_emitter > 0 then
        reset_state()
        return true
    end

    if state.active then
        if state.best_node then
            local node = state.best_node
            cancel_ambiguous_timer()
            execute_node(node)
            reset_state()
            consumed_any = true
        else
            reset_state()
        end
    end
    return consumed_any
end

-- Execute key sequence as if entered via :normal / :normal!
-- remap=true uses mapping rhs expansion (:normal), remap=false disables it (:normal!).
function Command.execute_normal_keys(seq, opts)
    opts = opts or {}
    local remap = opts.remap ~= false
    local policy = remap and POLICY_FULL or POLICY_NOREMAP
    local lazy_block = options.get("lazyredraw")
    if lazy_block then
        lazyredraw_block = lazyredraw_block + 1
    end
    local ok, rv = pcall(Command._feed_seq_with_policy, seq or {}, policy, true)
    if lazy_block then
        lazyredraw_block = lazyredraw_block - 1
    end
    if not ok then
        error(rv)
    end
    return rv
end

function Command._on_timeout()
    if state.timer_id == nil then return end
    local node = state.best_node
    cancel_ambiguous_timer()
    -- If the best pending node is an operator, do NOT execute on timeout.
    if node and node.operator_cb then
        return
    end
    if node then execute_node(node) end
    reset_state()
end

-- =========================
-- Count helpers
-- =========================
local function at_sequence_start()
    return state.active and #state.seq == 0
end

local function push_digit(d)
    state.count_value = (state.count_value or 0) * 10 + d
    state.count_codes[#state.count_codes + 1] = d
end

-- =========================
-- Core step (single key)
-- capture_counts: if true, allow starting/continuing a user count; false for injected RHS.
-- =========================
function Command._handle_key_with_policy(code, policy, capture_counts)
    if #Command.override_emitter > 0 then
        Command.override_emitter[#Command.override_emitter](code)
        return true
    end

    if code.numeric == Key.CMD then
        reset_state()
        local command = {}
        Command.override_emitter[#Command.override_emitter + 1] = function(key)
            local printable = key:printable()
            if key:emittable() == "\r" or printable == "<C-j>" or printable == "<C-J>" then
                table.remove(Command.override_emitter)
                table.remove(Command.emitter_names)
                Event.ExecuteCommand(table.concat(command))
                return
            end
            local emitted = key:emittable()
            if emitted then command[#command + 1] = emitted end
        end
        Command.emitter_names[#Command.emitter_names + 1] = "Mapping.command"
        return true
    end

    -- If mode changed externally, abort any in-flight mapping.
    if state.active and state.mode ~= vimmode then
        Command.Log("mode-change abort: from %s to %s resetting", state.mode, vimmode)
        cancel_ambiguous_timer()
        reset_state()
    end
    Command.Log("step code=%d mode=%s active=%s", code.numeric, vimmode, tostring(state.active))
    state.mode = vimmode

    local root
    if policy == POLICY_NOREMAP then
        -- noremap still executes builtin key behavior, but ignores user mappings.
        root = builtin_mappings[vimmode] or { children = {} }
    else
        root = composite_root_for_mode(vimmode)
    end

    Command.Log("root children keys=%s", node_keys_tostring(root))

    -- If no active sequence, start from the root
    if not state.active then
        state.active    = true
        state.node      = root
        state.seq       = {}
        state.best_node = nil
    end

    Command.Log("curr node children keys=%s trying=%s", node_keys_tostring(state.node), code:printable())

    -- ===== Global operator recognition (single-key operators), non-destructive =====
    local op_started_now = false
    if capture_counts and (vimmode == "normal") and not state.pending_op and not state.skip_op_once then
        local op_node = _single_key_operator_node(root, code.numeric)
        if op_node then
            _enter_op_pending_global(op_node)
            if policy == POLICY_FULL then start_ambiguous_timer() end
            op_started_now = true
            -- NOTE: we do NOT consume this key; still traverse the main trie below so
            -- a conflicting plain mapping (e.g., "3d2") can remain pending and win on timeout.
        end
    end
    state.skip_op_once = false

    if state.pending_op and not op_started_now then
        local consumed = _op_motion_step(code)
        if consumed then
            return true
        else
            cancel_ambiguous_timer()
            _clear_op_pending()
            if state.best_node and state.best_node.operator_cb then
                state.best_node = nil
            end
            state.skip_op_once = true
            return Command._handle_key_with_policy(code, policy, capture_counts)
        end
    end

    -- ===== Count-or-mapping disambiguation =====
    if capture_counts and Command.count_modes[state.mode] then
        local d = code:ToDigit()          -- 0..9 or nil
        local handled_count_digit = false -- ensures we push a digit at most once per keypress

        if d ~= nil and at_sequence_start() and state.count_committed then
            if state.node and state.node.children and state.node.children[code.numeric] then
                -- Coexistence path: let trie handle this key; don't mark tentative.
                handled_count_digit = true -- fall through to trie step below
            else
                -- No mapping edge -> extend the committed count.
                push_digit(d)
                return true
            end
        end

        if d ~= nil and state.count_tentative and #state.seq > 0 then
            local seq_all_digits = true
            for i = 1, #state.seq do
                if state.seq[i]:ToDigit() == nil then
                    seq_all_digits = false; break
                end
            end
            local has_child = state.node and state.node.children and state.node.children[code.numeric]
            if seq_all_digits and not has_child then
                -- Promote tentative digits into the count
                for i = 1, #state.seq do
                    local di = state.seq[i]:ToDigit()
                    if di ~= nil then push_digit(di) end
                end
                state.count_committed = true
                state.count_tentative = false
                reset_mapping_only()
                return Command._handle_key_with_policy(code, policy, true)
            end
        end


        if d ~= nil then
            if at_sequence_start() then
                if state.count_committed then
                    -- We already have a committed count; a new digit arrives at seq start.
                    if state.node and state.node.children and state.node.children[code.numeric] then
                        -- There IS a mapping edge for this digit (e.g. '1' is mapped):
                        -- Do NOT extend the count with this digit. Treat it as a mapping key,
                        -- but remember we're in a tentative situation so if the mapping fails,
                        -- we re-handle the next key as the first command after the count.
                        state.count_tentative = true
                        handled_count_digit = true -- suppress any tail "tentative extension" for this keypress
                        -- fall through to trie step (no push_digit here)
                    else
                        -- No mapping starts with this digit -> it definitely extends the count.
                        push_digit(d)
                        return true
                    end
                else
                    -- No committed count yet
                    if root.children and root.children[code.numeric] then
                        -- Digit-leading mapping path exists from the very start (e.g. '2k')
                        if d ~= 0 then
                            -- Do NOT extend count now; treat digit as mapping key but mark tentative.
                            state.count_tentative = true
                            handled_count_digit = true -- avoid pushing in the tail below
                            -- fall through to trie (no push_digit)
                        else
                            -- Leading 0 never starts a count; treat as real key
                            clear_count()
                            -- fall through to trie
                        end
                    else
                        -- No digit-leading mapping path from here; this digit participates in the count.
                        if d ~= 0 or state.count_tentative then
                            if not state.count_tentative then clear_count() end
                            state.count_committed = true
                            push_digit(d)
                            return true
                        end
                    end
                end
            end

            -- If we are in a tentative-count state, only extend it here when we haven't already
            -- handled this digit in the logic above. This prevents double-pushing.
            if state.count_tentative and at_sequence_start() and not handled_count_digit then
                if d ~= 0 then
                    push_digit(d)
                    handled_count_digit = true -- luacheck: ignore 311
                end
                -- fall through to trie
            end
        end
    end

    -- ===== Trie step =====
    local next_node = state.node and state.node.children and state.node.children[code.numeric]
    if not next_node then
        cancel_ambiguous_timer()

        Command.Log(
            "no-edge: children=%s trying=%s root-keys=%s count_tentative=%d count_value=%d",
            node_keys_tostring(state.node),
            code:printable(),
            node_keys_tostring(root),
            state.count_tentative,
            state.count_value
        )

        -- Special case: digit-only leaf was pending with a count context and a new digit arrived.
        do
            local retry_d      = code:ToDigit()
            local prev_best    = state.best_node
            local in_count_ctx = (state.count_committed or (#state.count_codes > 0) or state.count_tentative)
            if prev_best and retry_d ~= nil and in_count_ctx and seq_is_digit_only(state.seq) then
                if node_has_children(prev_best) then
                    -- Ambiguous leaf: execute earlier leaf with existing count (e.g., "91" -> '1' with count 9)
                    execute_node(prev_best)
                    reset_state()
                    return Command._handle_key_with_policy(code, policy, true)
                else
                    -- Non-ambiguous digit-only leaf: promote the pending digit keys
                    -- (those already in state.seq) into a committed count, but DO NOT
                    -- consume the current digit here. Re-handle the current digit as
                    -- a fresh mapping key so it becomes the leaf with the committed count.
                    for i = 1, #state.seq do
                        local di = state.seq[i]:ToDigit()
                        if di ~= nil then push_digit(di) end
                    end
                    state.count_committed = true
                    state.count_tentative = false
                    reset_mapping_only()
                    _clear_op_pending()
                    return Command._handle_key_with_policy(code, policy, true)
                end
            end
        end

        -- Non-digit broke a pending digit-only leaf (e.g. "10" then "j"):
        -- promote the typed digits into the count and re-handle the non-digit
        do
            local retry       = code
            local retry_d     = retry:ToDigit() -- nil for non-digits
            local prev_best   = state.best_node
            local digits_only = seq_is_digit_only(state.seq)

            if prev_best and retry_d == nil and digits_only then
                -- fold the pending digit keys into the count
                for i = 1, #state.seq do
                    local di = state.seq[i]:ToDigit()
                    if di ~= nil then push_digit(di) end
                end
                state.count_committed = true
                state.count_tentative = false
                reset_mapping_only()
                _clear_op_pending()
                return Command._handle_key_with_policy(retry, policy, true)
            end
        end

        if state.count_tentative then
            local retry            = code
            local retry_d          = retry:ToDigit() -- 0..9 or nil
            local prev_best        = state.best_node
            local had_count_before = state.count_committed or (#state.count_codes > 0)

            -- If we don't yet have a real count tracked, promote the leading digit keys
            -- we've already traversed in seq into the count.
            local function promote_seq_digits_into_count()
                if #state.count_codes == 0 then
                    for i = 1, #state.seq do
                        local di = state.seq[i]:ToDigit()
                        if di == nil then break end
                        push_digit(di)
                    end
                end
            end

            if retry_d ~= nil then
                -- Digit broke the tentative mapping
                if not had_count_before then
                    -- e.g. "12": treat both digits as a count, do NOT execute earlier leaf.
                    promote_seq_digits_into_count()
                    push_digit(retry_d)
                    state.count_committed = true
                    state.count_tentative = false
                    reset_mapping_only()
                    return true
                else
                    -- e.g. "91(1|...)" where 9 was already a committed count
                    if prev_best then
                        local digits_only = (#state.seq > 0)
                        for i = 1, #state.seq do
                            if state.seq[i]:ToDigit() == nil then
                                digits_only = false; break
                            end
                        end

                        local first_is_single_leaf = false
                        if #state.seq > 0 then
                            local node1 = root.children[state.seq[1].numeric]
                            first_is_single_leaf = node1 and node1.callback ~= nil
                        end

                        if digits_only and not first_is_single_leaf then
                            for i = 1, #state.seq do
                                local di = state.seq[i]:ToDigit()
                                if di ~= nil then push_digit(di) end
                            end
                            push_digit(retry_d)
                            state.count_committed = true
                            state.count_tentative = false
                            reset_mapping_only()
                            return true
                        end

                        -- But if an operator motion has already completed, prefer it.
                        if state.pending_op and state.op_motion and state.op_motion.best_node then
                            _execute_operator_with_motion(state.op_motion.best_node)
                            return true
                        end

                        execute_node(prev_best)
                        reset_state()
                        return Command._handle_key_with_policy(retry, policy, true)
                    else
                        -- No earlier leaf; just start a new count from this digit and continue.
                        reset_mapping_only()
                        state.count_committed = true
                        state.count_tentative = false
                        state.count_value     = nil
                        state.count_codes     = {}
                        push_digit(retry_d)
                        return true
                    end
                end
            else
                -- Non-digit broke the tentative mapping (e.g. "4g...").
                local digits_only = seq_is_digit_only(state.seq)
                if digits_only then
                    promote_seq_digits_into_count()
                    state.count_committed = (#state.count_codes > 0)
                    state.count_tentative = false
                    reset_mapping_only()
                    _clear_op_pending()
                    return Command._handle_key_with_policy(retry, policy, true)
                end

                if not had_count_before then
                    -- Promote the tentative leading digits into a committed count.
                    promote_seq_digits_into_count()
                    state.count_committed = (#state.count_codes > 0)
                end
                state.count_tentative = false

                if prev_best and had_count_before then
                    -- e.g. "91g": execute earlier leaf with count, then handle 'g'
                    -- But if an operator motion has already completed, prefer it.
                    if state.pending_op and state.op_motion and state.op_motion.best_node then
                        _execute_operator_with_motion(state.op_motion.best_node)
                        return true
                    end
                    execute_node(prev_best)
                    reset_state()
                    return Command._handle_key_with_policy(retry, policy, true)
                else
                    -- No earlier leaf OR we didn't have a prior committed count:
                    -- restart mapping state but keep the (now committed) count,
                    -- and re-handle this non-digit as the first command key.
                    reset_mapping_only()
                    _clear_op_pending()
                    return Command._handle_key_with_policy(retry, policy, true)
                end
            end
        end

        -- No tentative count to salvage; prefer executing a completed operator motion if present, else raw/reset.
        if state.pending_op and state.op_motion and state.op_motion.best_node then
            _execute_operator_with_motion(state.op_motion.best_node)
            return true
        end

        if state.pending_op then
            return true
        end

        if capture_counts then
            if state.active and #state.seq > 0 then
                reset_state()
                return Command._handle_key_with_policy(code, policy, true)
            end
            reset_state()
            Command.Log("emit_raw code=%s (no mapping, user input)", code:printable())
            Command.emit_raw({ code })
            return true
        else
            reset_state()
            return false
        end
    end

    -- Advance
    state.node                = next_node
    state.seq[#state.seq + 1] = code

    -- Leaves under policy
    local at_leaf_cb          = next_node.callback ~= nil
    local at_leaf_keys        = (policy == POLICY_FULL) and (next_node.rhs_seq ~= nil) or false
    local at_leaf_expr        = (policy == POLICY_FULL) and (next_node.expr_rhs ~= nil) or false
    local at_leaf             = at_leaf_cb or at_leaf_keys or at_leaf_expr or (next_node.operator_cb ~= nil)
    local has_more            = node_has_children(next_node)

    if at_leaf then
        Command.Log(
            "leaf-found cb=%s rhs_len=%d operator=%s has_mode=%s policy=%d",
            tostring(next_node.callback),
            next_node.rhs_seq and #next_node.rhs_seq or 0,
            tostring(next_node.operator_cb ~= nil),
            tostring(has_mode),
            policy
        )

        state.best_node = next_node

        -- Operator leaf: enter operator-pending instead of executing now.
        if next_node.operator_cb then
            if not state.pending_op then
                _enter_op_pending_global(next_node)
            end
            if policy == POLICY_FULL then
                start_ambiguous_timer()
            end
            return true
        end

        if policy == POLICY_FULL and #state.seq == 1 and seq_is_digit_only(state.seq) and state.count_tentative then
            start_ambiguous_timer()
            return true
        end

        -- Digit-only leaf at sequence start with a count context:
        -- delay execution (start ambiguous timer) so further digits either
        -- (a) execute the ambiguous leaf (e.g., '1' before '10'), or
        -- (b) get absorbed as part of the count for non-ambiguous leaves ('0','03').
        local in_count_ctx = (state.count_committed or (#state.count_codes > 0) or state.count_tentative)
        if policy == POLICY_FULL and in_count_ctx and seq_is_digit_only(state.seq) then
            start_ambiguous_timer()
            return true
        end

        if not has_more then
            -- If an operator motion has completed, prefer executing operator+motion.
            if state.pending_op and state.op_motion and state.op_motion.best_node then
                _execute_operator_with_motion(state.op_motion.best_node)
                return true
            else
                local node = state.best_node
                cancel_ambiguous_timer()
                execute_node(node)
                reset_state()
                return true
            end
        else
            if policy == POLICY_FULL then
                start_ambiguous_timer()
            end
            return true
        end
    else
        cancel_ambiguous_timer()
        return true
    end
end

-- Public: normal key from user input (full mapping semantics; counts allowed)
function Command.HandleKey(k)
    if macro_state.defer_executing_clear and not macro_state.replaying_internal then
        macro_state.executing_register = nil
        macro_state.defer_executing_clear = false
    end

    local finish_popup, sync_popup
    if PopupMenu.visible() then
        local handled
        handled, finish_popup, sync_popup = PopupMenu.handle_key(k)
        if handled then return handled end
    end

    if handle_macro_control_key(k) then
        finish_select_once()
        return true
    end

    append_recorded_key(k)

    if #Command.override_emitter > 0 then
        Command.override_emitter[#Command.override_emitter](k)
        if sync_popup then PopupMenu.sync_text() end
        if finish_popup and PopupMenu.visible() then PopupMenu.close(finish_popup) end
        finish_select_once()
        return
    end

    local code = k
    Command.Log("HandleKey code=%d (%s) vimmode=%s", code.numeric, code:printable(), vimmode)
    local handled = Command._handle_key_with_policy(code, POLICY_FULL, true)
    if sync_popup then PopupMenu.sync_text() end
    if finish_popup and PopupMenu.visible() then PopupMenu.close(finish_popup) end
    finish_select_once()
    return handled
end

function Command.Reset()
    cancel_ambiguous_timer()
    reset_state()
    macro_state.pending_action = nil
    select_mapping_context = nil
    select_once = nil
end

function Command.reg_recording()
    return macro_state.recording_register or ""
end

function Command.reg_executing()
    return macro_state.executing_register or ""
end

function Command.reg_recorded()
    return macro_state.last_recorded_register or ""
end

function Command._debug_dump_mode(mode_full)
    local function dfs(node, depth)
        local indent = string.rep("  ", depth)
        for k, child in pairs(node.children or {}) do
            LOG_DEBUG(indent .. tostring(k) ..
                (child.callback and " [CB]" or "") ..
                (child.rhs_seq and " [RHS]" or "") ..
                (child.operator_cb and " [OP]" or ""))
            dfs(child, depth + 1)
        end
    end
    local root = user_global_mappings[mode_full]
    LOG_DEBUG("DUMP mode=" .. tostring(mode_full))
    if not root then
        LOG_DEBUG("  <empty>"); return
    end
    dfs(root, 1)
end

function Command.PendingPrintable()
    local count_digits = state.count_codes or {}
    local seq          = (state.active and state.seq) or {}

    if (#count_digits == 0 and #seq == 0) then
        return ""
    end

    -- Build count as typed
    local count_str = ""
    if #count_digits > 0 then
        local t = {}
        for i = 1, #count_digits do t[i] = tostring(count_digits[i]) end
        count_str = table.concat(t, "")
    end

    -- Find how many leading seq keys are the same digits as count_digits
    local overlap = 0
    if not state.count_committed then
        local max_overlap = math.min(#count_digits, #seq)
        for i = 1, max_overlap do
            local d = seq[i]:ToDigit()
            if d ~= count_digits[i] then break end
            overlap = overlap + 1
        end
    end

    -- Build printable for the seq, skipping the overlapped digit prefix
    local seq_str = ""
    if #seq > overlap then
        local out = {}
        for i = overlap + 1, #seq do
            out[#out + 1] = seq[i]:printable()
        end
        seq_str = table.concat(out, "")
    end

    local motion_count_str, motion_seq_str = "", ""
    if state.pending_op and state.op_motion then
        local m = state.op_motion
        if m.count_codes and #m.count_codes > 0 then
            local t = {}
            for i = 1, #m.count_codes do t[i] = tostring(m.count_codes[i]) end
            motion_count_str = table.concat(t, "")
        end
        if m.seq and #m.seq > 0 then
            local out = {}
            for i = 1, #m.seq do out[#out + 1] = m.seq[i]:printable() end
            motion_seq_str = table.concat(out, "")
        end
    end

    return count_str .. seq_str .. motion_count_str .. motion_seq_str
end

return Command
