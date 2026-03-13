-- texren.lua - fast text renderer with wrapping, tabs, and optional blit output
local TexRen = {}

---@class TexRenParseParams
---@field wraplen integer      wrap column (>0)
---@field wordwrap boolean|nil if true, prefer breaking on space/tab
---@field breakat string|nil   if wordwrap, characters eligible for breaking
---@field listcfg table|nil   listchars config { space?, tab_head?, tab_fill? }
---@field tabcfg table         tab state configuration from Tab

local Tab = loadModule("lib.tab")
local Utf8 = loadModule("lib.utf8")

-- Localize frequently used funcs (Lua 5.1 compatible)
local s_byte  = string.byte
local s_char  = string.char
local s_sub   = string.sub
local t_concat= table.concat

local function each_char_with_byte(s, visitor)
    if utf8 and utf8.codes then
        local ok = pcall(function()
            for bpos, cp in utf8.codes(s) do
                visitor(bpos, cp)
            end
        end)
        if ok then
            return
        end
    end

    for i = 1, #s do
        local by = s_byte(s, i)
        visitor(i, by)
    end
end

local function strip_trailing_eols(s)
    local n = #s
    while n > 0 do
        local c = s_byte(s, n)
        if c ~= 10 and c ~= 13 then break end
        n = n - 1
    end
    if n == #s then return s end
    if n <= 0 then return "" end
    return s_sub(s, 1, n)
end

-- ============
-- Glyph building (two tight inner variants to avoid hot-path branches)
-- ============

-- Build glyphs (flat arrays) and optional glyph colors from a blit pair or
-- highlight-id array.
-- Returns:
--   gch[]     : array of single-char strings (rendered glyphs)
--   issp[]    : parallel array of booleans (true if space)
--   gfg[]?    : parallel array of fg blit chars (present if want_blit)
--   gbg[]?    : parallel array of bg blit chars (present if want_blit)
--   ghl[]?    : parallel array of hl ids (present if want_hl)
--   target    : 1-based glyph index of first display cell for bytepos (or nil)
--   n         : #gch

local function build_glyphs_with_map_noblit(s, bytepos, cfg, listcfg)
    local gch, issp, gsrc = {}, {}, {}
    local target = nil
    local col = 0
    local list_space = listcfg and listcfg.space
    local tab_head = listcfg and listcfg.tab_head
    local tab_fill = listcfg and listcfg.tab_fill or tab_head

    local function push(ch, src_i)
        local k = #gch + 1
        if ch == " " and list_space then
            gch[k] = list_space
        else
            gch[k] = ch
        end
        issp[k] = (ch == " ")
        gsrc[k] = src_i
        if bytepos and src_i == bytepos and not target then target = k end
        col = col + 1
    end

    each_char_with_byte(s, function(i, cp)
        if cp == 9 then
            local stop = Tab.next_display_tabstop(col, cfg)
            local n = stop - col; if n <= 0 then n = 1 end
            local k0 = #gch
            for k = 1, n do
                local idx = k0 + k
                if tab_head then
                    if k == 1 then
                        gch[idx] = tab_head
                    else
                        gch[idx] = tab_fill or tab_head
                    end
                else
                    gch[idx] = " "
                end
                issp[idx] = true
                gsrc[idx] = i
            end
            if bytepos and i == bytepos and not target then target = k0 + 1 end
            col = col + n
        elseif cp < 32 or cp == 127 then
            local second = (cp == 127) and "?" or s_char(cp + 64)
            push("^", i); push(second, i)
        else
            local ch = screen.normalize_codepoint(cp)
            push(ch, i)
        end
    end)
    return gch, issp, nil, nil, nil, nil, target, #gch, gsrc
end

local function build_glyphs_with_map_blit(s, bytepos, cfg, blitfg, blitbg, listcfg)
    local gch, issp, gfg, gbg, gsrc = {}, {}, {}, {}, {}
    local target = nil
    local col = 0
    local list_space = listcfg and listcfg.space
    local tab_head = listcfg and listcfg.tab_head
    local tab_fill = listcfg and listcfg.tab_fill or tab_head

    local function color_at(i)
        local f = s_sub(blitfg, i, i); if f == "" then f = "0" end
        local b = s_sub(blitbg, i, i); if b == "" then b = "0" end
        return f, b
    end

    local function push(ch, src_i, f, b)
        local k = #gch + 1
        if ch == " " and list_space then
            gch[k] = list_space
        else
            gch[k] = ch
        end
        issp[k] = (ch == " ")
        gfg[k] = f; gbg[k] = b
        gsrc[k] = src_i
        if bytepos and src_i == bytepos and not target then target = k end
        col = col + 1
    end

    each_char_with_byte(s, function(i, cp)
        local f, b = color_at(i)
        if cp == 9 then
            local stop = Tab.next_display_tabstop(col, cfg)
            local n = stop - col; if n <= 0 then n = 1 end
            local k0 = #gch
            for k = 1, n do
                local idx = k0 + k
                if tab_head then
                    if k == 1 then
                        gch[idx] = tab_head
                    else
                        gch[idx] = tab_fill or tab_head
                    end
                else
                    gch[idx] = " "
                end
                issp[idx] = true; gfg[idx] = f; gbg[idx] = b; gsrc[idx] = i
            end
            if bytepos and i == bytepos and not target then target = k0 + 1 end
            col = col + n
        elseif cp < 32 or cp == 127 then
            local second = (cp == 127) and "?" or s_char(cp + 64)
            push("^", i, f, b); push(second, i, f, b)
        else
            local ch, swap = screen.normalize_codepoint(cp)
            if swap then
                f, b = b, f
            end
            push(ch, i, f, b)
        end
    end)
    return gch, issp, gfg, gbg, nil, nil, target, #gch, gsrc
end

local function build_glyphs_with_map_hl(s, bytepos, cfg, hlline, listcfg)
    local gch, issp, ghl, gswap, gsrc = {}, {}, {}, {}, {}
    local target = nil
    local col = 0
    local list_space = listcfg and listcfg.space
    local tab_head = listcfg and listcfg.tab_head
    local tab_fill = listcfg and listcfg.tab_fill or tab_head

    local function push(ch, src_i, hl, swap)
        local k = #gch + 1
        if ch == " " and list_space then
            gch[k] = list_space
        else
            gch[k] = ch
        end
        issp[k] = (ch == " ")
        ghl[k] = hl
        gswap[k] = swap == true
        gsrc[k] = src_i
        if bytepos and src_i == bytepos and not target then target = k end
        col = col + 1
    end

    each_char_with_byte(s, function(i, cp)
        local hl = hlline and hlline[i]
        if cp == 9 then
            local stop = Tab.next_display_tabstop(col, cfg)
            local n = stop - col
            if n <= 0 then n = 1 end
            local k0 = #gch
            for k = 1, n do
                local idx = k0 + k
                if tab_head then
                    if k == 1 then
                        gch[idx] = tab_head
                    else
                        gch[idx] = tab_fill or tab_head
                    end
                else
                    gch[idx] = " "
                end
                issp[idx] = true
                ghl[idx] = hl
                gswap[idx] = false
                gsrc[idx] = i
            end
            if bytepos and i == bytepos and not target then target = k0 + 1 end
            col = col + n
        elseif cp < 32 or cp == 127 then
            local second = (cp == 127) and "?" or s_char(cp + 64)
            push("^", i, hl, false)
            push(second, i, hl, false)
        else
            local ch, swap = screen.normalize_codepoint(cp)
            push(ch, i, hl, swap)
        end
    end)
    return gch, issp, nil, nil, ghl, gswap, target, #gch, gsrc
end

local function build_glyphs_with_map(s, bytepos, cfg, blitfg, blitbg, hlline, want_blit, want_hl, listcfg)
    if want_blit then
        return build_glyphs_with_map_blit(s, bytepos, cfg, blitfg, blitbg, listcfg)
    elseif want_hl then
        return build_glyphs_with_map_hl(s, bytepos, cfg, hlline, listcfg)
    else
        return build_glyphs_with_map_noblit(s, bytepos, cfg, listcfg)
    end
end

-- Emit glyphs i..j to rv[ri]; if colors requested, emit to rbfg[ri]/rbbg[ri].
-- Returns next ri and (maybe) mapped_col if target in [i..j].
local function emit_line_from_glyphs(rv, rbfg, rbbg, rbhl, rbswap, ri, gch, gfg, gbg, ghl, gswap, i, j, want_pos, target_idx, want_blit, want_hl)
    rv[ri] = t_concat(gch, "", i, j)
    if want_blit then
        rbfg[ri] = t_concat(gfg, "", i, j)
        rbbg[ri] = t_concat(gbg, "", i, j)
    elseif want_hl then
        local out, swap_out = {}, {}
        for k = i, j do
            out[#out + 1] = ghl[k]
            swap_out[#swap_out + 1] = gswap[k]
        end
        rbhl[ri] = out
        rbswap[ri] = swap_out
    end
    local mapped_col = nil
    if want_pos and target_idx and target_idx >= i and target_idx <= j then
        mapped_col = target_idx - i + 1
    end
    return ri + 1, mapped_col
end

local function parse_internal(str, params, bytepos, blit_pair, want_ranges)
    local rv = {}
    local ri = 1

    -- Strip trailing EOLs
    str = strip_trailing_eols(str)

    -- Normalize blit inputs
    local blitfg, blitbg
    local hlline
    if type(blit_pair) == "table" then
        blitfg = blit_pair.fg or blit_pair[1]
        blitbg = blit_pair.bg or blit_pair[2]
        hlline = blit_pair.hl
    end
    local want_blit = (type(blitfg) == "string")
                   and (type(blitbg) == "string")
    local want_hl = type(hlline) == "table"

    -- Only allocate blit output tables if needed
    local rbfg, rbbg, rbhl, rbswap = nil, nil, nil, nil
    if want_blit then
        rbfg, rbbg = {}, {}
    elseif want_hl then
        rbhl = {}
        rbswap = {}
    end

    -- Build glyph arrays (+colors if requested)
    local gch, issp, gfg, gbg, ghl, gswap, target_idx, total_cols, gsrc =
        build_glyphs_with_map(str, bytepos, params.tabcfg, blitfg, blitbg, hlline, want_blit, want_hl, params.listcfg)

    local want_pos = (bytepos ~= nil)

    local wl = params.wraplen or 0
    local wordwrap = params.wordwrap
    local breakset = nil
    local src_is_break = nil
    if wordwrap and params.breakat and type(params.breakat) == "string" then
        breakset = {}
        each_char_with_byte(params.breakat, function(_, cp)
            local ch = screen.normalize_codepoint(cp)
            breakset[ch] = true
        end)
        src_is_break = {}
        each_char_with_byte(str, function(si, cp)
            local ch = screen.normalize_codepoint(cp)
            if breakset[ch] then src_is_break[si] = true end
        end)
    end

    local mapped_line, mapped_col, mapped_ch_explicit
    local ranges = want_ranges and {}

    local function finish_pos(line, col)
        local ch = mapped_ch_explicit or gch[target_idx]
        return { line = line, column = col, ch = ch }
    end

    local function emit_line(i, j)
        local line_idx = ri
        local mapped_col_local
        ri, mapped_col_local =
            emit_line_from_glyphs(
                rv,
                rbfg,
                rbbg,
                rbhl,
                rbswap,
                ri,
                gch,
                gfg,
                gbg,
                ghl,
                gswap,
                i,
                j,
                want_pos,
                target_idx,
                want_blit,
                want_hl
            )
        if ranges then
            ranges[line_idx] = { i = i, j = j }
        end
        if want_pos and mapped_col_local and not mapped_line then
            mapped_line, mapped_col = line_idx, mapped_col_local
        end
    end

    -- No wrapping or single-line
    if wl <= 0 or total_cols <= wl then
        emit_line(1, #gch)
        if want_pos then
            local col = mapped_col or ((rv[1] and Utf8.len(rv[1]) or 0) + 1)
            if not mapped_col then mapped_ch_explicit = " " end
            if wl > 0 and (not target_idx) then
                local line_len = (rv[1] and Utf8.len(rv[1])) or 0
                if line_len > 0 and col == line_len + 1 and line_len == wl then
                    return rv, (want_blit and { fg = rbfg, bg = rbbg } or want_hl and { hl = rbhl, swap = rbswap }), finish_pos(2, 1), ranges, gsrc
                end
            end
            return rv, (want_blit and { fg = rbfg, bg = rbbg } or want_hl and { hl = rbhl, swap = rbswap }), finish_pos(1, col), ranges, gsrc
        end
        return rv, (want_blit and { fg = rbfg, bg = rbbg } or want_hl and { hl = rbhl, swap = rbswap }), nil, ranges, gsrc
    end

    local i, n = 1, #gch
    while i <= n do
        local j = (i + wl - 1); if j > n then j = n end
        if j == n then
            emit_line(i, j)
            break
        end
        if wordwrap and breakset then
            -- Prefer breaking at a break-at character
            local break_at = nil
            local last_src = nil
            for k = j, i, -1 do
                local src_i = gsrc[k]
                if src_i and src_i ~= last_src and src_is_break and src_is_break[src_i] then
                    break_at = k
                    break
                end
                last_src = src_i
            end

            if break_at then
                -- Include the break character on this line.
                emit_line(i, break_at)
                i = break_at + 1
            else
                -- No break point -> hard break
                emit_line(i, j)
                i = j + 1
            end
        elseif wordwrap then
            -- Wordwrap requested but no breakset: fall back to spaces only
            local break_at = nil
            for k = j, i, -1 do
                if issp[k] then break_at = k; break end
            end

            if break_at then
                emit_line(i, break_at)
                i = break_at + 1
            else
                emit_line(i, j)
                i = j + 1
            end
        else
            -- Hard wrap at j
            emit_line(i, j)
            i = j + 1
        end
    end

    if want_pos then
        if not (mapped_line and mapped_col) then
            mapped_line = ri - 1
            mapped_col = (rv[mapped_line] and Utf8.len(rv[mapped_line]) or 0) + 1
            mapped_ch_explicit = " "
        end
        if wl > 0 and (not target_idx) then
            local line_len = (rv[mapped_line] and Utf8.len(rv[mapped_line])) or 0
            if line_len > 0 and mapped_col == line_len + 1 and line_len == wl then
                mapped_line = mapped_line + 1
                mapped_col = 1
                mapped_ch_explicit = " "
            end
        end
        return rv, (want_blit and { fg = rbfg, bg = rbbg } or want_hl and { hl = rbhl, swap = rbswap }), finish_pos(mapped_line, mapped_col), ranges, gsrc
    else
        return rv, (want_blit and { fg = rbfg, bg = rbbg } or want_hl and { hl = rbhl, swap = rbswap }), nil, ranges, gsrc
    end
end

--- Parse & wrap.
--- If `bytepos` is provided, also returns {line,column,ch} for the rendered cell.
--- If a blit pair { fg, bg } is provided (4th arg), returns rendered blits
--- as the SECOND return value: { fg = {..lines..}, bg = {..lines..} }.
--- Additional return values expose layout mapping metadata used by window
--- decorations:
--- - ranges: per-rendered-row glyph bounds
--- - gsrc: glyph index -> source byte index
---@param str string
---@param params TexRenParseParams
---@param bytepos integer|nil
---@param blit_pair table|nil  -- { fg=string, bg=string } or { [1]=fg, [2]=bg }
---@return string[] lines, table|nil rendered_blits, table|nil pos, table ranges, table gsrc
TexRen.parse = function(str, params, bytepos, blit_pair)
    local lines, blits, pos, ranges, gsrc = parse_internal(str, params, bytepos, blit_pair, true)
    return lines, blits, pos, ranges, gsrc
end

--- Parse & wrap, returning additional layout info for cursor/scroll helpers.
--- Returns:
---   lines   : rendered line strings
---   ranges  : glyph index ranges for each rendered line {i=..., j=...}
---   gsrc    : glyph index -> source byte index map
---   pos     : (optional) position mapping for bytepos
---@param str string
---@param params TexRenParseParams
---@param bytepos integer|nil
---@return string[] lines, table ranges, table gsrc, table|nil pos
TexRen.layout = function(str, params, bytepos)
    local lines, _, pos, ranges, gsrc = parse_internal(str, params, bytepos, nil, true)
    return lines, ranges, gsrc, pos
end

return TexRen
