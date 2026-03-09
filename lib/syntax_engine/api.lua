local Api = {}

local State = loadModule("lib.syntax_engine.state")
local Runtime = loadModule("lib.syntax_engine.runtime")
local Profile = loadModule("lib.syntax_engine.profile")
local CommandParser = loadModule("lib.syntax_engine.command_parser")
local Compiler = loadModule("lib.syntax_engine.compiler")
local Options = loadModule("lib.options")
local Highlight = loadModule("lib.highlight")
local VimRegex = loadModule("lib.excmd.vim_regex")

local treesitter_mod
local function treesitter()
    treesitter_mod = treesitter_mod or loadModule("lib.luaapi.treesitter")
    return treesitter_mod
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function active_window(window)
    return window or windows[curwin]
end

local function ensure_buffer_ctx(buffer)
    local ctx = buffer.syntax_ctx
    if ctx then return ctx end

    local syntax = Options.get("syntax", nil, buffer, true)
    local synmaxcol = Options.get("synmaxcol", nil, buffer, true)
    return State.ensure_context(buffer, syntax, synmaxcol)
end

local function active_ctx(window)
    local win = active_window(window)
    return win.syntax_ctx_override or ensure_buffer_ctx(win.buffer)
end

local function ensure_compiled(ctx)
    if not ctx.syntax_ir_dirty then
        return ctx.syntax_ir
    end
    ctx.syntax_ir = Compiler.compile(ctx.syntax_commands)
    ctx.syntax_ir_dirty = false
    return ctx.syntax_ir
end

local function ensure_match_state(win)
    local state = win.syntax_match_state
    if state then return state end
    state = { slots = {} }
    win.syntax_match_state = state
    return state
end

local function has_active_window_match(win)
    local state = win.syntax_match_state
    if not state then return false end
    local slots = state.slots
    return slots[1] ~= nil or slots[2] ~= nil or slots[3] ~= nil
end

local function parse_delimited_pattern(raw)
    local text = trim(raw)
    local delim = text:sub(1, 1)
    if delim == "" then
        return nil, "Missing pattern"
    end

    local esc = false
    local in_class = false
    local class_count = 0
    local class_leading_caret = false
    for i = 2, #text do
        local ch = text:sub(i, i)
        if esc then
            esc = false
            if in_class then
                class_count = class_count + 1
            end
        elseif ch == "\\" then
            esc = true
        elseif in_class then
            class_count = class_count + 1
            if class_count == 1 and ch == "^" then
                class_leading_caret = true
            elseif ch == "]" then
                if class_count > 1 and not (class_leading_caret and class_count == 2) then
                    in_class = false
                end
            end
        elseif ch == "[" then
            in_class = true
            class_count = 0
            class_leading_caret = false
        elseif ch == delim then
            local tail = trim(text:sub(i + 1))
            if tail ~= "" then
                return nil, "Trailing characters"
            end
            return text:sub(2, i - 1), nil
        end
    end

    return nil, "Missing closing delimiter"
end

local function compile_match_pattern(raw_pattern)
    local pattern = tostring(raw_pattern or "")
    local case_override = nil
    pattern = pattern:gsub("\\[cC]", function(m)
        case_override = (m == "\\C")
        return ""
    end)

    local case_sensitive = case_override ~= nil and case_override or true
    local compiled, err = VimRegex.compile(pattern)
    if not compiled then
        return nil, nil, nil, tostring(err)
    end
    return pattern, compiled, case_sensitive, nil
end

local function normal_blit_for_line(line)
    local len = #line
    if len == 0 then
        return { fg = "", bg = "" }
    end
    local normal = Highlight.For("Normal")
    local fg = string.rep(colors.toBlit(normal[1]), len)
    local bg = string.rep(colors.toBlit(normal[2]), len)
    return { fg = fg, bg = bg }
end

local function buffer_line_count(buffer)
    return buffer:line_count(true)
end

local function buffer_get_line(buffer, line_nr)
    return buffer:get_line(line_nr, true) or ""
end

local function apply_match_slot(line, fg_chars, bg_chars, slot)
    local matched = false
    local pos = 1
    local len = #line
    local hl = Highlight.For(slot.group)
    local fg = colors.toBlit(hl[1])
    local bg = colors.toBlit(hl[2])

    while pos <= len do
        local s, e = VimRegex.find_compiled(line, slot.compiled, slot.case_sensitive, pos)
        if not s then
            break
        end
        if e >= s then
            matched = true
            for i = s, e do
                fg_chars[i] = fg
                bg_chars[i] = bg
            end
            pos = e + 1
        else
            pos = s + 1
        end
    end

    return matched
end

local function apply_window_matches(win, buffer, first_line, last_line, blits)
    if not has_active_window_match(win) then
        return blits
    end

    local state = ensure_match_state(win)
    local slots = state.slots
    local out = blits or {}

    for ln = first_line, last_line do
        local line = buffer_get_line(buffer, ln)
        if line ~= "" then
            local entry = out[ln] or normal_blit_for_line(line)
            local fg_chars = {}
            local bg_chars = {}
            for i = 1, #line do
                fg_chars[i] = entry.fg:sub(i, i)
                bg_chars[i] = entry.bg:sub(i, i)
            end

            local any = false
            for slot = 3, 1, -1 do
                local item = slots[slot]
                if item then
                    local matched = apply_match_slot(line, fg_chars, bg_chars, item)
                    if matched then any = true end
                end
            end

            if any then
                out[ln] = {
                    fg = table.concat(fg_chars),
                    bg = table.concat(bg_chars),
                }
            end
        end
    end

    return out
end

local function syntax_group_name(ctx, group_id)
    local ir = ctx.syntax_ir
    local g = ir and ir.groups and ir.groups[group_id]
    return g and g.name
end

function Api.invalidate_from_line(buffer, line)
    local ctx = ensure_buffer_ctx(buffer)
    return State.mark_dirty(ctx, line)
end

function Api.line_to_blit(buffer, line, window)
    local win = active_window(window)
    local ctx = (win.buffer == buffer and win.syntax_ctx_override) or ensure_buffer_ctx(buffer)
    ensure_compiled(ctx)

    local out = Runtime.line_to_blit(ctx, buffer, line)
    local blits = {}
    if out then
        blits[line] = out
    end

    if has_active_window_match(win) then
        blits = apply_window_matches(win, buffer, line, line, blits)
    end

    blits = treesitter()._apply_highlight_blits(buffer, line, line, blits)
    return blits and blits[line]
end

function Api.lines_to_blit(buffer, first_line, last_line, window)
    local win = active_window(window)
    local ctx = (win.buffer == buffer and win.syntax_ctx_override) or ensure_buffer_ctx(buffer)
    ensure_compiled(ctx)

    local out = Runtime.lines_to_blit(ctx, buffer, first_line, last_line)
    local overlaid = apply_window_matches(win, buffer, first_line, last_line, out)
    return treesitter()._apply_highlight_blits(buffer, first_line, last_line, overlaid)
end

function Api.on_syntax_option(buffer, value)
    local ctx = ensure_buffer_ctx(buffer)
    return State.set_syntax(ctx, value)
end

function Api.on_synmaxcol_option(buffer, value)
    local ctx = ensure_buffer_ctx(buffer)
    return State.set_synmaxcol(ctx, value)
end

function Api.clear_buffer(buffer)
    local ctx = ensure_buffer_ctx(buffer)
    return State.clear(ctx)
end

function Api.ownsyntax(window, name)
    local win = active_window(window)

    local synmaxcol = Options.get("synmaxcol", nil, win.buffer, true)

    local ctx = State.new_context({
        syntax = name,
        synmaxcol = synmaxcol,
    })
    ctx.window_local = true
    win.syntax_ctx_override = ctx
    return true
end

function Api.on_window_buffer_changed(window)
    local win = active_window(window)
    win.syntax_ctx_override = nil
    return true
end

function Api.syntime_set(window, enabled)
    local ctx = active_ctx(window)
    return Profile.set_enabled(ctx, enabled)
end

function Api.syntime_clear(window)
    local ctx = active_ctx(window)
    return Profile.clear(ctx)
end

function Api.syntime_report(window)
    local ctx = active_ctx(window)
    return Profile.report(ctx)
end

function Api.syntax_command(window, raw_cmd)
    local ctx = active_ctx(window)
    local parsed = CommandParser.parse(raw_cmd)

    if parsed.kind == "list" then
        ensure_compiled(ctx)
        return true
    end

    local commands = ctx.syntax_commands
    commands[#commands + 1] = parsed
    ctx.syntax_ir_dirty = true
    State.mark_dirty(ctx, 1)
    return true
end

function Api.match_clear(window, slot)
    local win = active_window(window)
    local state = ensure_match_state(win)
    state.slots[slot] = nil
    return true
end

function Api.match_set(window, slot, group, pattern)
    local win = active_window(window)
    local state = ensure_match_state(win)
    local compiled_pattern, compiled, case_sensitive, err = compile_match_pattern(pattern)
    if err then
        return nil, err
    end
    state.slots[slot] = {
        group = group,
        pattern = compiled_pattern,
        compiled = compiled,
        case_sensitive = case_sensitive,
    }
    return true
end

function Api.match_get(window)
    local win = active_window(window)
    local state = ensure_match_state(win)
    local out = {}
    for slot = 1, 3 do
        local item = state.slots[slot]
        if item then
            out[#out + 1] = {
                group = item.group,
                pattern = item.pattern,
                priority = 10,
                id = slot,
            }
        end
    end
    return out
end

function Api.match_command(window, slot, argstr)
    local raw = trim(argstr)
    if raw == "" or raw:lower() == "none" then
        return Api.match_clear(window, slot)
    end

    local group, rest = raw:match("^(%S+)%s*(.*)$")
    if not group or group == "" then
        return nil, "Missing highlight group"
    end
    if rest == "" then
        return nil, "Missing pattern"
    end

    local pattern, perr = parse_delimited_pattern(rest)
    if perr then
        return nil, perr
    end

    return Api.match_set(window, slot, group, pattern)
end

function Api.syn_query(window, lnum, col)
    local win = active_window(window)
    local buffer = win.buffer
    local line_count = buffer_line_count(buffer)

    if lnum < 1 or lnum > line_count then
        return { ids = {}, top_id = 0, conceal = 0, cchar = "" }
    end

    local line = buffer_get_line(buffer, lnum)
    if line == "" then
        return { ids = {}, top_id = 0, conceal = 0, cchar = "" }
    end

    if col < 1 then col = 1 end
    if col > #line then col = #line end

    local ctx = active_ctx(win)
    ensure_compiled(ctx)

    local ir = ctx.syntax_ir
    if not ir or not ir.item_order or #ir.item_order == 0 then
        return { ids = {}, top_id = 0, conceal = 0, cchar = "" }
    end

    Runtime.line_to_blit(ctx, buffer, lnum)
    local cache = ctx.span_cache[lnum]
    if not cache then
        return { ids = {}, top_id = 0, conceal = 0, cchar = "" }
    end

    local ids = {}
    local top_span = nil
    local top_name = nil
    for i = 1, #(cache.spans or {}) do
        local span = cache.spans[i]
        if col >= (span.s or 1) and col <= (span.e or 0) then
            local name = syntax_group_name(ctx, span.group_id)
            if name and name ~= "" then
                local id = Highlight.IdByName(name)
                if #ids == 0 or ids[#ids] ~= id then
                    ids[#ids + 1] = id
                end
                top_name = name
            end
            top_span = span
        end
    end

    local top_id = ids[#ids] or 0
    return {
        ids = ids,
        top_id = top_id,
        top_name = top_name or "",
        conceal = (top_span and top_span.conceal) and 1 or 0,
        cchar = (top_span and top_span.cchar) or "",
    }
end

return Api
