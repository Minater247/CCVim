local Intro = {}

local Options = loadModule("lib.options")
local ScreenDraw = loadModule("lib.screendraw")

Intro.command = false
local LINES = {
    "CCVim v" .. ccvimversion_str,
    "",
    "CCVim is open source and freely distributable",
    "https://github.com/Minater247/CCVim",
    "",
    "type  :help nvim<Enter>       if you are new! ",
    "type  :checkhealth<Enter>     to optimize CCVim",
    "type  :q<Enter>               to exit         ",
    "type  :help<Enter>            for help        ",
    "",
    "type  :help news<Enter> to see changes in v0.8",
    "",
    "Help poor children in Uganda!",
    "type  :help Kuwasha<Enter>    for information ",
}

local function draw_line(row, text)
    local spans = {}
    local from = 1
    while true do
        local first = text:find("<", from, true)
        if not first then
            if from <= #text then
                spans[#spans + 1] = { text:sub(from), "Normal" }
            end
            break
        end
        local last = text:find(">", first + 1, true) or #text
        if first > from then
            spans[#spans + 1] = { text:sub(from, first - 1), "Normal" }
        end
        spans[#spans + 1] = { text:sub(first, last), "SpecialKey" }
        from = last + 1
    end
    local col = math.max(0, math.floor((screen.width - #text) / 2))
    ScreenDraw.put_spans(row, col, spans)
end

function Intro.draw(tabpage)
    if not Intro.command then
        local win = windows[curwin]
        local buf = win.buffer
        local lines = buf:lines_ref(true)
        if win.winnr ~= 1
            or win.frame ~= tabpage.tree
            or buf.bufnr ~= 1
            or (buf.name and buf.name ~= "")
            or #lines ~= 1
            or lines[1] ~= ""
            or Options.get("shortmess"):find("I", 1, true)
        then
            return false
        end
    else
        for row = 0, screen.height - 1 do
            ScreenDraw.clear_line(row, "Normal")
        end
    end

    local blanklines = screen.height - (#LINES - 1)
    if Options.get("laststatus") > 1 then
        blanklines = blanklines - (screen.height - tabpage.tree.height)
    end
    local row = math.floor(math.max(0, blanklines) / 2)
    if not Intro.command and (row < 2 or screen.width < 50) then
        return true
    end

    for i = 1, #LINES do
        local text = LINES[i]
        if text ~= "" then
            draw_line(row + i - 1, text)
        end
    end
    if Intro.command then
        ScreenDraw.put_text(screen.height - 1, 0, "Press ENTER or type command to continue", "Question")
    end
    return true
end

function Intro.show(command)
    Intro.command = true
    command.override_emitter[#command.override_emitter + 1] = function(key)
        local char = key:emittable()
        if char == "\r" or char == ":" then
            Intro.command = false
            table.remove(command.override_emitter)
            table.remove(command.emitter_names)
            what_redraw.all = true
            need_redraw = true
            if char == ":" then
                command.HandleKey(key)
            end
        end
    end
    command.emitter_names[#command.emitter_names + 1] = "Intro"
    what_redraw.all = true
    need_redraw = true
end

return Intro
