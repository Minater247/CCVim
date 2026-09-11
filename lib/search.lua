local Search = {}

local Scopes = loadModule("lib.luaapi.scopes")
local Utf8 = loadModule("lib.utf8")
local VimRegex = loadModule("lib.excmd.vim_regex")

local accepted_pattern
local accepted_direction = 1
local active
local VimFn
local pattern_cache = {}

function Search.prepare_pattern(pattern, use_ignorecase_opt)
    local raw = tostring(pattern or "")
    local ignorecase = use_ignorecase_opt ~= false and options.get("ignorecase") or false
    local smartcase = ignorecase and options.get("smartcase") or false
    local cache_key = table.concat({ raw, ignorecase and "1" or "0", smartcase and "1" or "0" }, "\0")
    local cached = pattern_cache[cache_key]
    if cached then
        return cached.compiled, cached.case_sensitive, cached.err
    end

    local case_override
    local stripped = raw:gsub("\\[cC]", function(marker)
        case_override = marker == "\\C"
        return ""
    end)

    local case_sensitive
    if case_override ~= nil then
        case_sensitive = case_override
    elseif ignorecase then
        case_sensitive = smartcase and stripped:find("%u") ~= nil
    else
        case_sensitive = true
    end

    local compiled, err = VimRegex.compile(stripped)
    cached = {
        compiled = compiled,
        case_sensitive = case_sensitive,
        err = err,
    }
    pattern_cache[cache_key] = cached
    return compiled, case_sensitive, err
end

function Search.line_matches(pattern, line)
    local compiled, case_sensitive, err = Search.prepare_pattern(pattern)
    if not compiled then
        return nil, err
    end

    line = tostring(line or "")
    local matches = {}
    local from = 1
    while from <= #line + 1 do
        local start_byte, end_byte = VimRegex.find_compiled(line, compiled, case_sensitive, from)
        if not start_byte then
            break
        end
        matches[#matches + 1] = {
            start_byte = start_byte,
            end_byte = end_byte or start_byte,
        }
        local next_from = (end_byte or start_byte) + 1
        if next_from <= from then
            next_from = from + 1
        end
        from = next_from
    end
    return matches
end

local function position(win)
    return {
        buffer = win.buffer,
        line = win.cursory,
        col = win.cursorx,
        scrollx = win.scrollx,
        scrolly = { win.scrolly[1], win.scrolly[2] },
    }
end

local function restore(win, pos)
    win:_set_cursor_raw(pos.line, pos.col)
    win.scrollx = pos.scrollx
    win.scrolly[1] = pos.scrolly[1]
    win.scrolly[2] = pos.scrolly[2]
    win:mark_redraw()
end

local function perform(win, pattern, direction, count, origin)
    restore(win, origin)
    VimFn = VimFn or loadModule("lib.luaapi.fn")
    local found = false
    local ok, err = pcall(function()
        for _ = 1, count or 1 do
            if VimFn.fn.search(pattern, direction < 0 and "b" or "") == 0 then
                found = false
                return
            end
            found = true
        end
    end)
    if not ok or not found then
        restore(win, origin)
        return false, err
    end

    local line, col = win.cursory, win.cursorx
    restore(win, origin)
    win:cursorSet(col, line)
    return true
end

local function accept(pattern, direction)
    accepted_pattern = pattern
    accepted_direction = direction
    registers["/"] = { "charwise", pattern }
    Scopes._v.searchforward = direction > 0 and 1 or 0
    Scopes._v.hlsearch = 1
end

function Search.begin(win, direction, count)
    Scopes._v.hlsearch = 1
    active = {
        win = win,
        origin = position(win),
        direction = direction,
        count = count or 1,
        pattern = "",
        valid = false,
    }
    win:mark_redraw()
end

function Search.change(pattern)
    if not active then
        return
    end
    active.pattern = tostring(pattern or "")
    active.valid = false
    active.current = nil
    restore(active.win, active.origin)

    if active.pattern == "" or not options.get("incsearch") then
        return
    end
    local compiled = Search.prepare_pattern(active.pattern)
    if not compiled then
        return
    end

    local ok = perform(active.win, active.pattern, active.direction, active.count, active.origin)
    if ok then
        active.valid = true
        active.current = position(active.win)
    end
end

function Search.cancel()
    if not active then
        return
    end
    restore(active.win, active.origin)
    active = nil
end

function Search.finish(pattern)
    if not active then
        return false, nil, nil
    end

    local state = active
    active = nil
    pattern = tostring(pattern or "")
    local effective = pattern ~= "" and pattern or accepted_pattern
    if not effective then
        restore(state.win, state.origin)
        return false, state.origin, "E35: No previous regular expression"
    end

    accept(effective, state.direction)
    if options.get("incsearch") and pattern ~= "" and state.valid then
        state.win:mark_redraw()
        return true, state.origin
    end

    local ok = perform(state.win, effective, state.direction, state.count, state.origin)
    if not ok then
        return false, state.origin, "E486: Pattern not found: " .. effective
    end
    return true, state.origin
end

function Search.execute(pattern, direction, count, remember_direction)
    local win = windows[curwin]
    local origin = position(win)
    pattern = tostring(pattern or "")
    local effective = pattern ~= "" and pattern or accepted_pattern
    if not effective then
        return false, origin, "E35: No previous regular expression"
    end

    if pattern ~= "" then
        accept(pattern, remember_direction and direction or accepted_direction)
    elseif remember_direction then
        accepted_direction = direction
        Scopes._v.searchforward = direction > 0 and 1 or 0
        Scopes._v.hlsearch = 1
    else
        Scopes._v.hlsearch = 1
    end

    local ok = perform(win, effective, direction, count or 1, origin)
    if not ok then
        return false, origin, "E486: Pattern not found: " .. effective
    end
    return true, origin
end

function Search.direction()
    return accepted_direction
end

function Search.is_active_for(win)
    return active ~= nil and active.win == win
end

function Search.matches(win, line_number, line)
    local pattern
    local current
    local show_all

    if active then
        if not options.get("incsearch") or not active.valid or active.pattern == "" then
            return nil
        end
        pattern = active.pattern
        current = active.current
        show_all = options.get("hlsearch") and Scopes._v.hlsearch ~= 0
    else
        if not accepted_pattern or not options.get("hlsearch") or Scopes._v.hlsearch == 0 then
            return nil
        end
        pattern = accepted_pattern
        current = { win = win, line = win.cursory, col = win.cursorx }
        show_all = true
    end

    local matches = Search.line_matches(pattern, line)
    if not matches then
        return nil
    end

    local out = {}
    for i = 1, #matches do
        local match = matches[i]
        local start_col = Utf8.col_from_byte(line, match.start_byte, true)
        local is_current = current
            and current.line == line_number
            and current.col == start_col
            and (not active or active.win == win)
        if is_current then
            match.group = active and "IncSearch" or "CurSearch"
            out[#out + 1] = match
        elseif show_all then
            match.group = "Search"
            out[#out + 1] = match
        end
    end
    return #out > 0 and out or nil
end

function Search.suspend()
    Scopes._v.hlsearch = 0
    what_redraw.windows = true
    need_redraw = true
end

return Search
