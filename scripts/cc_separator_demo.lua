local entries = {
    { label = "thin rounded left  (U+E0B6 -> 0x88)", byte = 0x88, swap = false, facing = "left" },
    { label = "thin rounded right (U+E0B4 -> 0x84)", byte = 0x84, swap = false, facing = "right" },
    { label = "thin slanted left  (U+E0B2 -> 0x97, swap)", byte = 0x97, swap = true, facing = "left" },
    { label = "thin slanted right (U+E0B0 -> 0x94)", byte = 0x94, swap = false, facing = "right" },
    { label = "full slanted left  (U+E0BA -> 0x8B, swap)", byte = 0x8B, swap = true, facing = "left" },
    { label = "full slanted right (U+E0B8 -> 0x87, swap)", byte = 0x87, swap = true, facing = "right" },
}

local bg = colors.black
local label_fg = colors.white
local marker_fg = colors.black
local color_a = colors.orange
local color_b = colors.lightBlue

local function blit_of(color)
    return colors.toBlit(color)
end

local function draw_transition(y, entry)
    local width = select(1, term.getSize())
    local left_color = color_a
    local right_color = color_b
    if entry.facing == "left" then
        left_color, right_color = right_color, left_color
    end

    local aligned_color = entry.facing == "left" and left_color or right_color
    local other_color = entry.facing == "left" and right_color or left_color
    local left_bg = blit_of(left_color)
    local right_bg = blit_of(right_color)
    local sep_fg = entry.swap and blit_of(other_color) or blit_of(aligned_color)
    local sep_bg = entry.swap and blit_of(aligned_color) or blit_of(other_color)

    local left_text = "  A  "
    local right_text = "  B  "
    local text = left_text .. string.char(entry.byte) .. right_text
    local fg = string.rep(blit_of(marker_fg), #left_text) .. sep_fg .. string.rep(blit_of(marker_fg), #right_text)
    local bg_line = string.rep(left_bg, #left_text) .. sep_bg .. string.rep(right_bg, #right_text)
    local sample_x = math.max(1, width - #text + 1)

    term.setCursorPos(1, y)
    term.setTextColor(label_fg)
    term.setBackgroundColor(bg)
    term.clearLine()
    term.write(entry.label)

    term.setCursorPos(sample_x, y)
    term.blit(text, fg, bg_line)
end

local function draw_separator(y)
    local width = select(1, term.getSize())
    term.setCursorPos(1, y)
    term.blit(
        string.rep("-", width),
        string.rep(blit_of(colors.gray), width),
        string.rep(blit_of(bg), width)
    )
end

term.setBackgroundColor(bg)
term.setTextColor(label_fg)
term.clear()
term.setCursorPos(1, 1)
term.write("Separator demo: A=orange, B=lightBlue")

for i = 1, #entries do
    local row = 3 + ((i - 1) * 2)
    draw_transition(row, entries[i])
    if i < #entries then
        draw_separator(row + 1)
    end
end

term.setCursorPos(1, 3 + (#entries * 2))
term.setTextColor(colors.lightGray)
term.write("Left-facing samples swap the side colors to keep the aligned side matching.")
