local ScreenDraw = {}

local Highlight = loadModule("lib.highlight")
local Color = loadModule("lib.color")
local Utf8 = loadModule("lib.utf8")

local HEX_TO_SLOT = {
    ["0"] = 0, ["1"] = 1, ["2"] = 2, ["3"] = 3,
    ["4"] = 4, ["5"] = 5, ["6"] = 6, ["7"] = 7,
    ["8"] = 8, ["9"] = 9, a = 10, b = 11, c = 12, d = 13, e = 14, f = 15,
}

local BLIT_HL_CACHE = {}

local function append_text_cells(cells, text, hl_id)
    Utf8.each_codepoint(text, function(cp)
        local ch, swap = screen.normalize_codepoint(cp)
        cells[#cells + 1] = { ch, hl_id, 1, swap }
    end)
end

local function blit_hl_id(fg_ch, bg_ch)
    local cache_key = fg_ch .. bg_ch
    local hl_id = BLIT_HL_CACHE[cache_key]
    if hl_id then
        return hl_id
    end

    local fg_slot = HEX_TO_SLOT[fg_ch]
    local bg_slot = HEX_TO_SLOT[bg_ch]
    local fr, fg, fb = screen.get_palette_slot(fg_slot)
    local br, bg, bb = screen.get_palette_slot(bg_slot)
    hl_id = screen.hl_id_for({
        fg = Color.pack(fr, fg, fb),
        bg = Color.pack(br, bg, bb),
    })
    BLIT_HL_CACHE[cache_key] = hl_id
    return hl_id
end

function ScreenDraw.invalidate_blit_cache()
    BLIT_HL_CACHE = {}
end

function ScreenDraw.put_text(row, col, text, group, ns, wrap)
    local cells = {}
    append_text_cells(cells, text, Highlight.GetId(group, ns))
    if #cells > 0 then
        screen.grid_line(1, row, col, cells, wrap)
    end
end

function ScreenDraw.put_spans(row, col, spans, ns, wrap)
    local cells = {}
    for i = 1, #spans do
        append_text_cells(cells, spans[i][1], Highlight.GetId(spans[i][2], ns))
    end
    if #cells > 0 then
        screen.grid_line(1, row, col, cells, wrap)
    end
end

function ScreenDraw.put_blit(row, col, text, fg, bg, wrap)
    text = tostring(text or "")
    fg = tostring(fg or "")
    bg = tostring(bg or "")
    local len = #text
    if len == 0 then
        return
    end

    local cells = {}
    for i = 1, len do
        cells[#cells + 1] = {
            Utf8.char_for_codepoint(text:byte(i)),
            blit_hl_id(fg:sub(i, i), bg:sub(i, i)),
            1,
        }
    end
    screen.grid_line(1, row, col, cells, wrap)
end

function ScreenDraw.put_hl_text(row, col, text, hl_line, wrap, swap_line)
    local cells = {}
    local cell_idx = 0
    Utf8.each_codepoint(text, function(cp)
        cell_idx = cell_idx + 1
        cells[#cells + 1] = {
            Utf8.char_for_codepoint(cp),
            hl_line and hl_line[cell_idx] or nil,
            1,
            swap_line and swap_line[cell_idx] or false,
        }
    end)
    if #cells > 0 then
        screen.grid_line(1, row, col, cells, wrap)
    end
end

function ScreenDraw.fill(row, col, width, group, ns, ch)
    if width <= 0 then
        return
    end

    local cells = {}
    local fill = ch or " "
    local hl_id = Highlight.GetId(group, ns)
    for i = 1, width do
        cells[i] = { fill, hl_id, 1 }
    end
    screen.grid_line(1, row, col, cells, false)
end

function ScreenDraw.clear_line(row, group, ns, start_col)
    local col = start_col or 0
    local width = screen.width - col
    if width > 0 then
        ScreenDraw.fill(row, col, width, group, ns, " ")
    end
end

function ScreenDraw.cursor(row, col)
    screen.grid_cursor_goto(1, row, col)
end

return ScreenDraw
