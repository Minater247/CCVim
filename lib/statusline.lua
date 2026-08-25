local Statusline = {}

local Options = loadModule("lib.options")
local VimFs = loadModule("lib.luaapi.fs")
local Runtime = loadModule("lib.excmd.runtime")
local Scopes = loadModule("lib.luaapi.scopes")
local Utf8 = loadModule("lib.utf8")

-- Highlight mark indicators
local HL_PUSH    = "\2" -- beginning of a new HL group
local HL_POP     = "\3" -- reset to previous highlight
local HL_SETN    = "\4" -- set numbered highlight group

local currfill -- character to use for fill from fillchars

local function user_group_name(n)
    n = tonumber(n) or 0
    return (n >= 1 and n <= 9) and ("User" .. n) or "StatusLine"
end

local function eval_statusline_expr(expr, winid)
    local rt = Runtime.new(Runtime._CURRENT_STATE)
    local out = ""
    local prior_winid = Scopes._g.statusline_winid
    Scopes._g.statusline_winid = winid

    local ok_run, rv = pcall(rt.eval_expr, rt, expr)
    if ok_run then
        out = tostring(rv or "")
    end

    Scopes._g.statusline_winid = prior_winid
    return out
end

local function evaluate_top_expr(fmt, window)
    if type(fmt) ~= "string" then
        fmt = tostring(fmt or "")
    end
    if fmt:sub(1, 2) ~= "%!" then
        return fmt
    end
    return eval_statusline_expr(fmt:sub(3), window.winnr)
end


local function apply_field(s, is_num, left_justify, zero_pad, minwid, maxwid)
    s = tostring(s or "")

    if minwid and minwid > 50 then minwid = 50 end

    -- maxwid handling
    if maxwid and maxwid >= 0 and #s > maxwid then
        if is_num then
            -- Numeric: keep tail and append '>dropcount', ensuring final width <= maxwid.
            -- Preserve leading sign outside the digits budget.
            local sign = s:sub(1, 1) == "-" and "-" or ""
            local digits = s:gsub("%D", "")
            local dlen = #digits

            if maxwid == 0 then
                s = ""
            else
                -- Budget excludes sign (if present).
                local budget = maxwid - (sign ~= "" and 1 or 0)
                if budget <= 0 then
                    -- No room for digits; try to show the indicator within budget.
                    local ind = ">" .. tostring(dlen)
                    local tail = ind:sub(-math.max(0, budget))
                    s = (sign ~= "" and sign or "") .. tail
                else
                    -- Choose k so: k + 1 + #tostring(dlen - k) <= budget
                    local k = math.min(dlen, budget)
                    local function over(kv)
                        return (kv + 1 + #tostring(dlen - kv)) > budget
                    end
                    while k > 0 and over(k) do k = k - 1 end
                    if k > 0 then
                        s = sign .. digits:sub(dlen - k + 1) .. ">" .. tostring(dlen - k)
                    else
                        local ind = ">" .. tostring(dlen)
                        s = (sign ~= "" and sign or "") .. ind:sub(-budget)
                    end
                end
            end
        else
            -- Text/group: left-truncate with a leading '<'
            if maxwid <= 0 then
                s = ""
            elseif maxwid == 1 then
                s = "<"
            else
                s = "<" .. s:sub(#s - (maxwid - 1) + 1)
            end
        end
    end

    -- padding (minwid)
    if minwid and minwid > #s then
        if left_justify then zero_pad = false end
        local padlen = minwid - #s
        local padch = (zero_pad and is_num and not left_justify) and "0" or currfill
        local pad = string.rep(padch, padlen)
        if left_justify then
            s = s .. pad
        else
            s = pad .. s
        end
    end

    return s
end

-- Parse one segment (no top-level %= split) into chunks:
-- chunks[i] = { kind="text"|"group"|"truncmark"|"hl"|"click", ... }
local function parse_segment(fmt, window)
    -- Move the locals in here since they're common
    local byte, sub, upper = string.byte, string.sub, string.upper
    local concat                = table.concat
    local floor                 = math.floor
    local tonumber, tostring    = tonumber, tostring

    -- Cache window fields (avoid hash lookups in inner loops)
    local buf                   = window.buffer
    local bopts                 = buf.opts
    local wopts                 = window.opts
    local lines                 = buf:lines_ref(true)

    local chunks                = {}

    local function emit_text(s)
        if s ~= "" then
            local last = chunks[#chunks]
            if last and last.kind == "text" then
                last.s = last.s .. s
            else
                chunks[#chunks + 1] = { kind = "text", s = s }
            end
        end
    end

    local function emit_truncmark()
        chunks[#chunks + 1] = { kind = "truncmark" }
    end

    local function emit_hl(ctrl, payload)
        chunks[#chunks + 1] = { kind = "hl", s = "", hl = { ctrl = ctrl, payload = payload or "" } }
    end

    local function emit_click(mode, click)
        chunks[#chunks + 1] = { kind = "click", mode = mode, click = click }
    end

    local function parse_flags_and_widths(j)
        -- Returns: j_after, left_justify, zero_pad, minwid, maxwid, raw_minwid
        local left_justify, zero_pad = false, false
        local minwid, maxwid, raw_minwid
        local n = #fmt

        -- flags
        while j <= n do
            local b = byte(fmt, j)
            if b == 45 then     -- '-'
                left_justify = true; j = j + 1
            elseif b == 48 then -- '0'
                zero_pad = true; j = j + 1
            else
                break
            end
        end

        -- minwid
        do
            local acc, any = 0, false
            while j <= n do
                local b = byte(fmt, j) - 48
                if b >= 0 and b <= 9 then
                    acc = acc * 10 + b; any = true; j = j + 1
                else
                    break
                end
            end
            if any then
                raw_minwid = acc
                minwid = acc
                if minwid > 50 then minwid = 50 end
            end
        end

        -- .maxwid
        if byte(fmt, j) == 46 then -- '.'
            j = j + 1
            local acc, any = 0, false
            while j <= n do
                local b = byte(fmt, j) - 48
                if b >= 0 and b <= 9 then
                    acc = acc * 10 + b; any = true; j = j + 1
                else
                    break
                end
            end
            if any then maxwid = acc end
        end

        return j, left_justify, zero_pad, minwid, maxwid, raw_minwid
    end

    local i, n = 1, #fmt
    while i <= n do
        if byte(fmt, i) ~= 37 then -- not '%'
            emit_text(sub(fmt, i, i))
            i = i + 1
        else
            local j                                               = i + 1
            local j_after, left_justify, zero_pad, minwid, maxwid, raw_minwid = parse_flags_and_widths(j)
            local nxtb                                                     = byte(fmt, j_after)
            local nxt                                                      = nxtb and sub(fmt, j_after, j_after) or ""

            if nxt == "" then
                emit_text("%")
                i = j_after
            elseif nxtb == 37 then -- '%'
                emit_text(apply_field("%", false, left_justify, zero_pad, minwid, maxwid))
                i = j_after + 1
            elseif nxtb == 60 then -- '<'
                emit_truncmark()
                i = j_after + 1
            elseif nxtb == 61 then -- '='
                emit_text(apply_field("%=", false, false, false, nil, nil))
                i = j_after + 1

                -- Highlight controls
            elseif nxtb == 35 then -- '#'
                local k = j_after + 1
                local start = k
                while k <= n and byte(fmt, k) ~= 35 do k = k + 1 end -- until '#'
                local name = (k > start) and sub(fmt, start, k - 1) or ""
                if k <= n and byte(fmt, k) == 35 then k = k + 1 end
                emit_hl(HL_PUSH, name)
                i = k
            elseif nxtb == 42 then -- '*'
                -- %* or %N*
                local kk = i + 1
                local num_start = kk
                while kk <= n do
                    local d = byte(fmt, kk) - 48
                    if d < 0 or d > 9 then break end
                    kk = kk + 1
                end
                if kk > num_start and byte(fmt, kk) == 42 then
                    local num = sub(fmt, num_start, kk - 1)
                    emit_hl(HL_SETN, num)
                    i = kk + 1
                else
                    emit_hl(HL_POP, "")
                    i = j_after + 1
                end
            elseif nxtb == 84 or nxtb == 88 then -- 'T'/'X'
                if raw_minwid ~= nil then
                    emit_click("start", { kind = nxtb == 84 and "tab" or "close_tab", tabnr = raw_minwid })
                else
                    emit_click("end")
                end
                i = j_after + 1
            elseif nxtb == 64 then -- '@'
                local k = j_after + 1
                local start = k
                while k <= n and byte(fmt, k) ~= 64 do k = k + 1 end
                if k <= n then
                    emit_click("start", {
                        kind = "function",
                        func = sub(fmt, start, k - 1),
                        minwid = raw_minwid or 0,
                    })
                    i = k + 1
                else
                    emit_text("%@")
                    i = j_after + 1
                end
            elseif nxtb == 123 then -- '{'
                -- %{expr} -> evaluate expression via excmd compiler/runtime
                local depth, k = 1, j_after + 1
                while k <= n and depth > 0 do
                    local c = byte(fmt, k)
                    if c == 123 then
                        depth = depth + 1 -- '{'
                    elseif c == 125 then
                        depth = depth - 1 -- '}'
                    end
                    k = k + 1
                end
                local inner = sub(fmt, j_after + 1, k - 2) or ""

                local out_s = eval_statusline_expr(inner, window.winnr)

                emit_text(apply_field(out_s, false, left_justify, zero_pad, minwid, maxwid))
                i = k
            elseif nxtb == 40 then -- '('
                -- %( ... %) group
                local depth, k = 1, j_after + 1
                local inner = {}
                while k <= n and depth > 0 do
                    local c = byte(fmt, k)
                    if c == 37 and byte(fmt, k + 1) == 40 then     -- "%("
                        depth = depth + 1; inner[#inner + 1] = "%("; k = k + 2
                    elseif c == 37 and byte(fmt, k + 1) == 41 then -- "%)"
                        depth = depth - 1
                        if depth > 0 then inner[#inner + 1] = "%)" end
                        k = k + 2
                    else
                        inner[#inner + 1] = sub(fmt, k, k)
                        k = k + 1
                    end
                end
                local inner_fmt = concat(inner)
                local inner_chunks = parse_segment(inner_fmt, window)
                local inner_str_tbl = {}
                for _, ck in ipairs(inner_chunks) do inner_str_tbl[#inner_str_tbl + 1] = ck.s end
                local rendered = apply_field(concat(inner_str_tbl), false, left_justify, zero_pad, minwid, maxwid)
                if rendered ~= "" then
                    chunks[#chunks + 1] = { kind = "group", s = rendered }
                end
                i = k
            else
                -- %-item (single-letter or single control)
                local out
                local is_num = false

                -- Paths / names
                if nxtb == 102 then -- 'f'
                    local path = buf.name or "[No Name]"
                    local j1 = path:match("^.*()[/\\]")
                    out = j1 and path:sub(j1 + 1) or path
                elseif nxtb == 70 then  -- 'F'
                    out = (buf.name and VimFs.abspath(buf.name)) or "[No Name]"
                elseif nxtb == 116 then -- 't'
                    local path = buf.name
                    if path then
                        local j1 = path:match("^.*()[/\\]")
                        out = j1 and path:sub(j1 + 1) or path
                    else
                        out = ""
                    end

                    -- Flags
                elseif nxtb == 109 then -- 'm'
                    if bopts.modified then
                        out = (bopts.modifiable == false) and "[-]" or "[+]"
                    else
                        out = ""
                    end
                elseif nxtb == 77 then -- 'M'
                    if bopts.modified then
                        out = (bopts.modifiable == false) and ",-" or ",+"
                    else
                        out = ""
                    end
                elseif nxtb == 114 then -- 'r'
                    out = bopts.readonly and "[RO]" or ""
                elseif nxtb == 82 then  -- 'R'
                    out = bopts.readonly and ",RO" or ""
                elseif nxtb == 104 then -- 'h'
                    out = (bopts.buftype == "help") and "[help]" or ""
                elseif nxtb == 72 then  -- 'H'
                    out = (bopts.buftype == "help") and ",HLP" or ""
                elseif nxtb == 119 then -- 'w'
                    out = wopts.previewwindow and "[Preview]" or ""
                elseif nxtb == 87 then  -- 'W'
                    out = wopts.previewwindow and ",PRV" or ""
                elseif nxtb == 121 then -- 'y'
                    local ft = bopts.filetype
                    out = ft and ("[" .. ft .. "]") or ""
                elseif nxtb == 89 then -- 'Y'
                    local ft = bopts.filetype
                    out = ft and ("," .. upper(ft)) or ""

                    -- Quickfix / showcmd / arglist
                elseif nxtb == 113 then -- 'q'
                    local qf = window.quickfix
                    if qf == "quickfix" then
                        out = "[Quickfix List]"
                    elseif qf == "loclist" then
                        out = "[Location List]"
                    else
                        out = ""
                    end
                elseif nxtb == 83 then -- 'S'
                    out = window.showcmd or ""
                elseif nxtb == 97 then -- 'a'
                    local args = window.args
                    if args and type(args.idx) == "number" and type(args.count) == "number" and args.count > 1 then
                        -- avoid string.format
                        out = tostring(args.idx) .. " of " .. tostring(args.count)
                    else
                        out = ""
                    end

                    -- Numbers / positions
                elseif nxtb == 110 then -- 'n'
                    out, is_num = tostring(buf.bufnr), true
                elseif nxtb == 108 then -- 'l'
                    out, is_num = tostring(window.cursory), true
                elseif nxtb == 99 then  -- 'c'
                    out, is_num = tostring(window.cursorx), true
                elseif nxtb == 76 then  -- 'L'
                    out, is_num = tostring(#lines), true
                elseif nxtb == 112 then -- 'p'
                    local ln = window.cursory
                    local lc = #lines
                    if type(ln) == "number" and type(lc) == "number" and lc > 0 then
                        out, is_num = tostring(floor((ln * 100) / lc + 0.5)), true
                    else
                        out, is_num = "100", true
                    end
                elseif nxtb == 80 then -- 'P': Top/Bot/All or NN%
                    local lc = #lines
                    local top = window.view_top
                    local bot = window.view_bottom
                    if top <= 1 and bot >= lc then
                        out = "All"
                    elseif top <= 1 then
                        out = "Top"
                    elseif bot >= lc then
                        out = "Bot"
                    else
                        local pct = floor(((top - 1) * 100) / lc + 0.5)
                        if pct < 0 then pct = 0 elseif pct > 99 then pct = 99 end
                        -- TODO: should this use fillchars? needs testing
                        if pct < 10 then
                            out = " " .. tostring(pct) .. "%"
                        else
                            out = tostring(pct) .. "%"
                        end
                    end

                    -- Character/byte/offset
                elseif nxtb == 98 or nxtb == 66 or nxtb == 111 or nxtb == 79 then -- b/B/o/O
                    local ln = window.cursory or 1
                    local col = window.cursorx or 1
                    local line = lines[ln] or ""
                    local ch = Utf8.codepoint_at(line, col) or 0

                    if nxtb == 98 then     -- 'b'
                        out, is_num = tostring(ch), true
                    elseif nxtb == 66 then -- 'B'
                        out, is_num = string.format("%X", ch), true
                    else                   -- 'o' or 'O'
                        local offset = buf:line_byte_index(ln, col, true, true) - 1
                        if ln > 1 then
                            for idx = 1, ln - 1 do
                                offset = offset + #(lines[idx] or "") + 1
                            end
                        end
                        offset = offset + 1
                        if nxtb == 111 then -- 'o'
                            out, is_num = tostring(offset), true
                        else                -- 'O'
                            out, is_num = string.format("%X", offset), true
                        end
                    end

                    -- Virtual column (approx)
                elseif nxtb == 118 then -- 'v'
                    local vcol = tonumber(window.cursorx) or 1
                    out, is_num = tostring(vcol), true
                elseif nxtb == 86 then -- 'V'
                    local ccol = tonumber(window.cursorx) or 1
                    local vcol = ccol
                    out = (vcol ~= ccol) and ("-" .. tostring(vcol)) or ""
                else
                    -- unknown -> literal
                    out = "%" .. nxt
                end

                out = apply_field(out, is_num, left_justify, zero_pad, minwid, maxwid)
                if out ~= "" then
                    emit_text(out)
                end
                i = j_after + 1
            end
        end
    end
    return chunks
end

-- Split a top-level format string into up to three sections on %=
-- (not inside %(...) or %{...}).
local function split_on_equals(fmt)
    local byte, sub = string.byte, string.sub
    local parts, buf = {}, {}
    local i, n = 1, #fmt
    local depth_group, depth_expr = 0, 0

    local function flush()
        parts[#parts + 1] = table.concat(buf); buf = {}
    end

    while i <= n do
        local b = byte(fmt, i)
        if b == 37 then                                                   -- '%'
            local b2 = byte(fmt, i + 1)
            if b2 == 40 then                                              -- '('
                depth_group = depth_group + 1; buf[#buf + 1] = "%("; i = i + 2
            elseif b2 == 41 and depth_group > 0 then                      -- ')'
                depth_group = depth_group - 1; buf[#buf + 1] = "%)"; i = i + 2
            elseif b2 == 123 then                                         -- '{'
                depth_expr = depth_expr + 1; buf[#buf + 1] = "%{"; i = i + 2
            elseif b2 == 61 and depth_group == 0 and depth_expr == 0 then -- '=' at top level
                flush(); i = i + 2
            else
                buf[#buf + 1] = "%"; i = i + 1
            end
        else
            -- Track braces inside %{...}
            if depth_expr > 0 then
                if b == 123 then depth_expr = depth_expr + 1 end
                if b == 125 then depth_expr = depth_expr - 1 end
            end
            buf[#buf + 1] = sub(fmt, i, i)
            i = i + 1
        end
    end

    flush()
    if #parts > 3 then
        local a, b = parts[1], parts[2]
        local rest = table.concat({ table.unpack(parts, 3) }, "")
        parts = { a, b, rest }
    end
    return parts
end

local function visible_len_chunks(chunks)
    local n = 0
    for _, ck in ipairs(chunks) do
        if ck.kind == "text" or ck.kind == "group" then
            n = n + Utf8.len(ck.s)
        end
    end
    return n
end


local function has_truncmark(chunks)
    for _, ck in ipairs(chunks) do
        if ck.kind == "truncmark" then return true end
    end
    return false
end

local function clone_chunks(chunks)
    local out = {}
    for i = 1, #chunks do
        local ck = chunks[i]
        if ck.kind == "hl" then
            out[i] = { kind = "hl", s = "", hl = { ctrl = ck.hl.ctrl, payload = ck.hl.payload } }
        elseif ck.kind == "click" then
            local click = ck.click
            out[i] = {
                kind = "click",
                mode = ck.mode,
                click = click and {
                    kind = click.kind,
                    tabnr = click.tabnr,
                    func = click.func,
                    minwid = click.minwid,
                },
            }
        else
            out[i] = { kind = ck.kind, s = ck.s }
        end
    end
    return out
end


local function drop_left_visible(chunks, n_drop)
    if n_drop <= 0 then return clone_chunks(chunks) end
    local out, remain = {}, n_drop
    for _, ck in ipairs(chunks) do
        if ck.kind == "text" or ck.kind == "group" then
            local s = ck.s
            local L = Utf8.len(s)
            if remain >= L then
                remain = remain - L
                -- drop entire text chunk
            else
                out[#out + 1] = { kind = ck.kind, s = Utf8.sub(s, remain + 1) }
                remain = 0
            end
        else
            -- keep zero-width controls/marks so HL state stays consistent
            if ck.kind == "hl" then
                out[#out + 1] = { kind = "hl", s = "", hl = { ctrl = ck.hl.ctrl, payload = ck.hl.payload } }
            elseif ck.kind == "click" then
                local click = ck.click
                out[#out + 1] = {
                    kind = "click",
                    mode = ck.mode,
                    click = click and {
                        kind = click.kind,
                        tabnr = click.tabnr,
                        func = click.func,
                        minwid = click.minwid,
                    },
                }
            else
                out[#out + 1] = { kind = "truncmark", s = ck.s }
            end
        end
    end
    return out
end

local function keep_right_visible(chunks, want)
    local have = visible_len_chunks(chunks)
    local drop = have - want
    if drop <= 0 then return clone_chunks(chunks) end
    return drop_left_visible(chunks, drop)
end

local function append_spaces(chunks, n)
    if n > 0 then chunks[#chunks + 1] = { kind = "text", s = string.rep(currfill, n) } end
end

local function remove_truncmarks(chunks)
    local out = {}
    for _, ck in ipairs(chunks) do
        if ck.kind ~= "truncmark" then out[#out + 1] = ck end
    end
    return out
end

local function ensure_left_trunc_indicator(chunks, width)
    -- Force the first visible char to be '<'
    for _, ck in ipairs(chunks) do
        if (ck.kind == "text" or ck.kind == "group") and Utf8.len(ck.s) > 0 then
            ck.s = "<" .. Utf8.sub(ck.s, 2)
            return chunks
        end
    end
    -- No visible chars; if we have width, insert a literal '<'
    if width > 0 then
        table.insert(chunks, 1, { kind = "text", s = "<" })
    end
    return chunks
end

local function concat_chunk_arrays(...)
    local out = {}
    for i = 1, select("#", ...) do
        local arr = select(i, ...)
        for j = 1, #arr do out[#out + 1] = arr[j] end
    end
    return out
end

-- Turn final chunk stream (no truncmarks) into { {text, group}, ... }
local function chunks_to_render(chunks, default_group)
    local spans = {}
    local click_zones = {}
    local group_stack, cur = {}, (default_group or "StatusLine")
    local click_stack = {}
    local buf = ""
    local col = 1

    local function flush()
        if #buf > 0 then
            spans[#spans + 1] = { buf, cur }
            col = col + Utf8.len(buf)
            buf = ""
        end
    end

    local function close_click_zone(end_col)
        local active = click_stack[#click_stack]
        if not active then
            return
        end
        click_stack[#click_stack] = nil
        local finish = end_col - 1
        if finish >= active.start_col then
            click_zones[#click_zones + 1] = {
                start_col = active.start_col,
                end_col = finish,
                kind = active.kind,
                tabnr = active.tabnr,
                func = active.func,
                minwid = active.minwid,
            }
        end
    end

    for _, ck in ipairs(chunks) do
        if ck.kind == "hl" then
            flush()
            local ctrl, payload = ck.hl.ctrl, ck.hl.payload or ""
            if ctrl == HL_PUSH then
                group_stack[#group_stack + 1] = cur
                if payload ~= "" then cur = payload end
            elseif ctrl == HL_SETN then
                group_stack[#group_stack + 1] = cur
                cur = user_group_name(payload)
            elseif ctrl == HL_POP then
                cur = group_stack[#group_stack] or (default_group or "StatusLine")
                group_stack[#group_stack] = nil
            end
        elseif ck.kind == "click" then
            flush()
            if ck.mode == "start" and ck.click then
                if #click_stack > 0 then
                    close_click_zone(col)
                end
                local click = ck.click
                click_stack[#click_stack + 1] = {
                    start_col = col,
                    kind = click.kind,
                    tabnr = click.tabnr,
                    func = click.func,
                    minwid = click.minwid or 0,
                }
            else
                close_click_zone(col)
            end
        elseif ck.kind == "text" or ck.kind == "group" then
            if #ck.s > 0 then
                buf = buf .. ck.s
            end
        end
        -- truncmark ignored
    end
    flush()
    while #click_stack > 0 do
        close_click_zone(col)
    end
    return spans, click_zones
end


-- Assemble sections into a chunk stream honoring width, %<, and centering
local function assemble_sections_chunks(sections, window, overrideWidth)
    local W = overrideWidth or window.frame.width

    -- Parse each section into chunks
    local Lc = parse_segment(sections[1] or "", window)
    local Mc = parse_segment(sections[2] or "", window)
    local Rc = parse_segment(sections[3] or "", window)

    local function vislen_LMR()
        return visible_len_chunks(Lc), visible_len_chunks(Mc), visible_len_chunks(Rc)
    end

    local function first_has_trunc()
        return has_truncmark(Lc)
    end

    -- 1 section
    if #sections == 1 then
        local L = clone_chunks(Lc)
        -- Global finishing: remove truncmarks, pad/truncate to W
        L = remove_truncmarks(L)
        local lv = visible_len_chunks(L)
        if lv < W then
            append_spaces(L, W - lv)
        elseif lv > W then
            L = keep_right_visible(L, W)
        end
        return L
    end

    -- 2 sections
    if #sections == 2 then
        local lL, lM = vislen_LMR()
        local need = W - (lL + lM)

        if need >= 0 then
            -- fits: L .. gap .. M
            local out = concat_chunk_arrays(clone_chunks(Lc))
            append_spaces(out, need)
            out = concat_chunk_arrays(out, clone_chunks(Mc))
            out = remove_truncmarks(out)
            return out
        end

        -- overflow
        if first_has_trunc() then
            -- drop only from LEFT; keep RIGHT intact
            local over = -need
            local Ld = drop_left_visible(Lc, over)
            Ld = remove_truncmarks(Ld)
            local Mclean = remove_truncmarks(Mc)
            local out = concat_chunk_arrays(Ld, Mclean)

            -- force '<' at column 1 if anything was dropped
            if over > 0 then out = ensure_left_trunc_indicator(out, W) end

            -- hard fit to width
            local ov = visible_len_chunks(out)
            if ov < W then
                append_spaces(out, W - ov)
            elseif ov > W then
                out = keep_right_visible(out, W)
            end
            return out
        else
            -- no %<: keep rightmost W of (L+M)
            local both = concat_chunk_arrays(remove_truncmarks(Lc), remove_truncmarks(Mc))
            both = keep_right_visible(both, W)
            return both
        end
    end

    -- 3 sections
    do
        local lL, lM, lR = vislen_LMR()

        -- Fits: center M between L and right-aligned R
        if (lL + lM + lR) <= W then
            local gap_before_R = W - lR - lL
            local gap1 = math.floor(math.max(0, gap_before_R - lM) / 2)
            local gap2 = math.max(0, gap_before_R - lM - gap1)
            local out = concat_chunk_arrays(
                clone_chunks(Lc),
                { { kind = "text", s = string.rep(currfill, gap1) } },
                clone_chunks(Mc),
                { { kind = "text", s = string.rep(currfill, gap2) } },
                clone_chunks(Rc)
            )
            out = remove_truncmarks(out)
            return out
        end

        -- Overflow: preserve R; fit (L+M) into remaining rem
        local rem = W - lR
        if rem <= 0 then
            -- R alone overflows: keep rightmost of R and show '<'
            local Rc0 = remove_truncmarks(Rc)
            local outR = keep_right_visible(Rc0, W)
            outR = ensure_left_trunc_indicator(outR, W)
            return outR
        end

        local lm_len = lL + lM
        if lm_len <= rem then
            -- Pack (L+M) flush-left, pad up to rem, then R
            local left_mid = concat_chunk_arrays(remove_truncmarks(Lc), remove_truncmarks(Mc))
            local lv = visible_len_chunks(left_mid)
            if lv < rem then append_spaces(left_mid, rem - lv) end
            return concat_chunk_arrays(left_mid, remove_truncmarks(Rc))
        end

        -- Need to drop from left of L, then M; show '<' if anything dropped
        local need_drop = lm_len - rem
        local L_only = remove_truncmarks(Lc)
        local M_only = remove_truncmarks(Mc)

        local lL2 = visible_len_chunks(L_only)
        local drop_L = math.min(need_drop, lL2)
        local Lk = drop_left_visible(L_only, drop_L)
        local need_drop2 = need_drop - drop_L
        local Mk = (need_drop2 > 0) and drop_left_visible(M_only, need_drop2) or M_only

        local left_mid = concat_chunk_arrays(Lk, Mk)
        if (drop_L > 0 or need_drop2 > 0) then
            left_mid = ensure_left_trunc_indicator(left_mid, rem)
        end

        local lv = visible_len_chunks(left_mid)
        if lv < rem then
            append_spaces(left_mid, rem - lv)
        elseif lv > rem then
            left_mid = keep_right_visible(left_mid, rem)
        end

        return concat_chunk_arrays(left_mid, remove_truncmarks(Rc))
    end
end




function Statusline.RenderInfo(fmt, window, overrideWidth, opts)
    opts = opts or {}
    local width = overrideWidth or window.frame.width

    if opts.fillchar ~= nil then
        currfill = tostring(opts.fillchar)
    elseif window.winnr == curwin then
        currfill = Options.ParseKeyedCSL(options.get("fillchars", window), { [":"] = true }).stl or " "
    else
        currfill = Options.ParseKeyedCSL(options.get("fillchars", window), { [":"] = true }).stlnc or " "
    end

    fmt = evaluate_top_expr(fmt, window)

    -- Split into up to three sections on top-level %=
    local sections = split_on_equals(fmt)
    if #sections == 0 then sections = { fmt } end

    -- Build final chunk stream at exactly window width (visible)
    local final_chunks = assemble_sections_chunks(sections, window, overrideWidth)

    -- Safety: clamp/pad (should already be exact)
    local vis = visible_len_chunks(final_chunks)
    if vis > width then
        final_chunks = keep_right_visible(final_chunks, width)
    elseif vis < width then
        append_spaces(final_chunks, width - vis)
    end

    local default_group = opts.default_group
    if not default_group then
        default_group = (window.winnr == curwin) and "StatusLine" or "StatusLineNC"
    end

    local spans, click_zones = chunks_to_render(final_chunks, default_group)
    return {
        spans = spans,
        click_zones = click_zones,
    }
end

function Statusline.Parse(fmt, window, overrideWidth)
    return Statusline.RenderInfo(fmt, window, overrideWidth).spans
end

return Statusline
