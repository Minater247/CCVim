local TUI = {}

-- TUI Component Types
local Components = {}

-- prominent text display
function Components.text(str)
    return { type = "text", str = str }
end

-- subtitle/info display
function Components.info(str, color)
    return { type = "info", str = str, color = color or colors.lightGray }
end

-- submenu/callable
function Components.option(str, callback)
    return { type = "option", str = str, callback = callback }
end

-- checkbox
function Components.checkbox(str, checked, callback)
    return { type = "checkbox", str = str, checked = checked, callback = callback }
end

-- text input
function Components.textbox(label, callback, initial)
    return { type = "textbox", str = label, callback = callback, initial = initial or "" }
end

-- horizontal separator
function Components.separator()
    return { type = "separator" }
end

-- log window
function Components.messageBox(opts)
    opts = opts or {}

    local box = {
        type      = "messagebox",
        -- layout
        fill      = opts.fill or false,  -- if true, uses remaining height
        height    = opts.height,         -- otherwise, uses this height
        minHeight = opts.minHeight or 1, -- if fill, be at least this
        -- colors
        textColor = opts.color or colors.white,
        bgColor   = opts.bgColor or colors.black,
        -- content
        lines     = opts.lines or {}, -- string[]
    }

    return box
end

function Components.disabledOption(str)
    return { type = "disabled_option", str = str }
end

TUI.Components = Components

-- check if this can be selected
local function isInteractiveType(t)
    return t == "option" or t == "checkbox" or t == "textbox"
end

local state = {
    stack   = {}, -- stack of menu states
    running = false,
    quitEnabled = true,
}

local function currentMenu()
    return state.stack[#state.stack]
end

-- Ensure currently selected item is visible within a given menu
local function ensureVisible(menu)
    local _, h = term.getSize()
    local usableHeight = h - 1 -- reserve last line for status bar

    if usableHeight < 1 then
        usableHeight = 1
    end

    if menu.selectedIndex < menu.top then
        menu.top = menu.selectedIndex
    elseif menu.selectedIndex > menu.top + usableHeight - 1 then
        menu.top = menu.selectedIndex - usableHeight + 1
    end

    if menu.top < 1 then
        menu.top = 1
    end
end

-- Build a single menu state from an items array
local function buildMenuState(items)
    local menu = {
        items          = items or {},
        itemTypes      = {},
        textboxState   = {},
        checkboxState  = {},
        editingTextbox = nil, -- TODO: remove this, document as function comment
        selectedIndex  = 1,
        top            = 1,
    }

    -- Determine item types and initial states
    for i, item in ipairs(menu.items) do
        local t = item.type
        if t == "option" then
            menu.itemTypes[i] = "option"
        elseif t == "disabled_option" then
            menu.itemTypes[i] = "disabled_option"
        elseif t == "text" or t == "info" then
            menu.itemTypes[i] = t
        elseif t == "separator" then
            menu.itemTypes[i] = "separator"
        elseif t == "checkbox" then
            menu.itemTypes[i] = "checkbox"
            menu.checkboxState[i] = not not item.checked
        elseif t == "textbox" then
            menu.itemTypes[i] = "textbox"
            menu.textboxState[i] = item.initial or ""
        elseif t == "messagebox" then
            menu.itemTypes[i] = "messagebox"
            item.lines = item.lines or {}
        else
            menu.itemTypes[i] = "text"
        end
    end

    -- Find first interactive item
    menu.selectedIndex = 1
    while menu.selectedIndex <= #menu.items do
        if isInteractiveType(menu.itemTypes[menu.selectedIndex]) then
            break
        end
        menu.selectedIndex = menu.selectedIndex + 1
    end
    if menu.selectedIndex > #menu.items then
        menu.selectedIndex = #menu.items
    end

    ensureVisible(menu)
    return menu
end

-- enter a submenu
function TUI.pushMenu(items)
    local menu = buildMenuState(items)
    table.insert(state.stack, menu)
end

function TUI.replaceMenu(depth, items)
    if not state.stack[depth] then
        return
    end

    state.stack[depth] = buildMenuState(items)
end

-- leave current menu
function TUI.popMenu()
    if #state.stack > 1 then
        table.remove(state.stack)
    else
        TUI.HaltLoop()
    end
end

-- add a line to a message box
function TUI.addMessage(box, line)
    if not box or box.type ~= "messagebox" then
        return
    end
    box.lines[#box.lines + 1] = tostring(line)
    TUI.render()
end

-- clear a message box
function TUI.clearMessages(box)
    if not box or box.type ~= "messagebox" then
        return
    end
    box.lines = {}
    TUI.render()
end

function TUI.setQuitEnabled(enabled)
    state.quitEnabled = not not enabled
end

-- turn a disabledOption into a regular option
function TUI.enableOption(item, callback)
    local menu = currentMenu()
    if not menu then
        return
    end

    for i, it in ipairs(menu.items) do
        if it == item then
            it.type = "option"
            it.callback = callback

            menu.itemTypes[i] = "option"
            menu.selectedIndex = i
            ensureVisible(menu)
            break
        end
    end
end

function TUI.render()
    local menu = currentMenu()
    if not menu then
        return
    end

    local w, h = term.getSize()
    local usableHeight = h - 1 -- bottom line is status

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()

    local y = 1

    for idx = menu.top, #menu.items do
        if y > usableHeight then
            break
        end

        local item     = menu.items[idx]
        local itemType = menu.itemTypes[idx]

        if itemType == "messagebox" then
            local remainingHeight = usableHeight - y + 1
            if remainingHeight <= 0 then
                break
            end

            local itemsBelow = #menu.items - idx
            if itemsBelow < 0 then
                itemsBelow = 0
            end

            local innerMin = item.minHeight or 1
            local totalMin = innerMin + 2 -- padding

            local totalHeight

            if item.fill then
                -- Maximum we can give this box while leaving space for items below
                local maxForBox = remainingHeight - itemsBelow
                if maxForBox < 1 then
                    maxForBox = 1
                end

                if maxForBox < totalMin then
                    totalHeight = totalMin
                    if totalHeight > remainingHeight then
                        totalHeight = remainingHeight
                    end
                else
                    totalHeight = maxForBox
                end
            else
                -- Fixed inner height
                local innerTarget = item.height or innerMin
                if innerTarget < innerMin then
                    innerTarget = innerMin
                end

                totalHeight = innerTarget + 2 -- padding

                if totalHeight > remainingHeight then
                    totalHeight = remainingHeight
                end
                if totalHeight < 1 then
                    totalHeight = 1
                end
            end

            if totalHeight < 1 then
                totalHeight = 1
            end

            local innerHeight = totalHeight - 2
            if innerHeight < 0 then
                innerHeight = 0
            end

            local innerWidth = w - 2
            if innerWidth < 1 then
                innerWidth = 1
            end

            local totalLines = #item.lines
            local firstLine = 1
            if innerHeight > 0 and totalLines > innerHeight then
                firstLine = totalLines - innerHeight + 1
            end

            local baseBg = colors.black
            local baseFg = colors.white

            if totalHeight >= 1 and y <= usableHeight then
                term.setCursorPos(1, y)
                term.setBackgroundColor(baseBg)
                term.setTextColor(baseFg)
                term.write(string.rep(" ", w))

                term.setCursorPos(2, y)
                term.setBackgroundColor(item.bgColor or baseBg)
                term.write(string.rep(" ", innerWidth))

                y = y + 1
            end

            for iLine = 0, innerHeight - 1 do
                if y > usableHeight then
                    break
                end

                local text = item.lines[firstLine + iLine] or ""
                if #text > innerWidth then
                    text = text:sub(1, innerWidth)
                end

                term.setCursorPos(1, y)
                term.setBackgroundColor(baseBg)
                term.setTextColor(baseFg)
                term.write(string.rep(" ", w))

                term.setCursorPos(2, y)
                term.setBackgroundColor(item.bgColor or baseBg)
                term.setTextColor(item.textColor or baseFg)

                term.write(text)
                if #text < innerWidth then
                    term.write(string.rep(" ", innerWidth - #text))
                end

                y = y + 1
            end

            if y <= usableHeight and totalHeight >= 2 then
                term.setCursorPos(1, y)
                term.setBackgroundColor(baseBg)
                term.setTextColor(baseFg)
                term.write(string.rep(" ", w))

                term.setCursorPos(2, y)
                term.setBackgroundColor(item.bgColor or baseBg)
                term.write(string.rep(" ", innerWidth))

                y = y + 1
            end
        else
            local selected = (idx == menu.selectedIndex) and isInteractiveType(itemType)

            local bg = colors.black
            local fg = colors.white

            if itemType == "info" then
                fg = item.color or colors.lightGray
            end

            if itemType == "separator" then
                fg = colors.lightGray
            end

            if itemType == "disabled_option" then
                fg = colors.gray or colors.lightGray
            end

            -- Highlight selected row
            if selected then
                bg = colors.lightBlue
                fg = colors.black
            end

            -- Currently editing textbox
            if itemType == "textbox" and idx == menu.editingTextbox then
                bg = colors.blue
                fg = colors.white
            end

            term.setCursorPos(1, y)
            term.setBackgroundColor(bg)

            if itemType == "textbox" then
                local label        = item.str or ""
                local value        = menu.textboxState[idx] or ""
                local labelPart    = label .. ": "
                local valPart      = value
                local remaining

                local labelToWrite = labelPart
                if #labelToWrite > w then
                    labelToWrite = labelToWrite:sub(1, w)
                end

                term.setTextColor(fg)
                term.write(labelToWrite)

                local spaceForVal = w - #labelToWrite - 2
                if spaceForVal < 0 then
                    spaceForVal = 0
                end

                if spaceForVal > 0 then
                    local valToWrite = valPart
                    if #valToWrite > spaceForVal then
                        if spaceForVal > 3 then
                            valToWrite = "..." .. valToWrite:sub(- (spaceForVal - 3))
                        else
                            valToWrite = valToWrite:sub(-spaceForVal)
                        end
                    end

                    local valueColor = (idx == menu.editingTextbox) and fg or colors.cyan
                    local bgColor = (idx == menu.editingTextbox) and bg or colors.black

                    term.setTextColor(valueColor)
                    term.setBackgroundColor(bgColor)

                    term.write("[" .. valToWrite .. "]")

                    local used = #valToWrite + 2
                    remaining = w - #labelToWrite - used
                    if remaining < 0 then
                        remaining = 0
                    end
                else
                    remaining = w - #labelToWrite
                    if remaining < 0 then
                        remaining = 0
                    end
                end

                if remaining > 0 then
                    term.setTextColor(fg)
                    term.write(string.rep(" ", remaining))
                end
            else
                local line = ""

                if itemType == "text" or itemType == "info" then
                    line = item.str or ""
                elseif itemType == "separator" then
                    line = string.rep("-", w)
                elseif itemType == "option" then
                    local prefix = selected and "> " or "  "
                    line = prefix .. (item.str or "")
                elseif itemType == "disabled_option" then
                    local prefix = "  "
                    line = prefix .. (item.str or "")
                elseif itemType == "checkbox" then
                    local checked = menu.checkboxState[idx] or false
                    local mark    = checked and "[x] " or "[ ] "
                    line          = mark .. (item.str or "")
                end

                if #line > w then
                    line = line:sub(1, w)
                end

                term.setTextColor(fg)
                term.write(line)
                if #line < w then
                    term.write(string.rep(" ", w - #line))
                end
            end

            y = y + 1
        end
    end

    while y <= usableHeight do
        term.setCursorPos(1, y)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write(string.rep(" ", w))
        y = y + 1
    end

    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)

    local status = "[Up/Down] Move  [Enter/Space] Select/Toggle/Edit  [Tab] Next  [Q] Quit"
    if #status > w then
        status = status:sub(1, w)
    end
    term.write(status)
end

function TUI.handleKey(key)
    local menu = currentMenu()
    if not menu then
        return false
    end

    if menu.editingTextbox then
        if key == keys.enter then
            menu.editingTextbox = nil
            return true
        elseif key == keys.backspace then
            local idx = menu.editingTextbox
            local value = menu.textboxState[idx] or ""
            if #value > 0 then
                menu.textboxState[idx] = value:sub(1, -2)
                local cb = menu.items[idx].callback
                if cb then
                    cb(menu.textboxState[idx])
                end
            end
            return true
        end
        return false
    end

    if key == keys.up then
        if menu.selectedIndex > 1 then
            local newIndex = menu.selectedIndex - 1
            while newIndex >= 1 do
                if isInteractiveType(menu.itemTypes[newIndex]) then
                    menu.selectedIndex = newIndex
                    ensureVisible(menu)
                    return true
                end
                newIndex = newIndex - 1
            end
        end

    elseif key == keys.down then
        if menu.selectedIndex < #menu.items then
            local newIndex = menu.selectedIndex + 1
            while newIndex <= #menu.items do
                if isInteractiveType(menu.itemTypes[newIndex]) then
                    menu.selectedIndex = newIndex
                    ensureVisible(menu)
                    return true
                end
                newIndex = newIndex + 1
            end
        end

    elseif key == keys.tab then
        if #menu.items > 0 then
            local start = menu.selectedIndex
            local idx   = start
            repeat
                idx = idx + 1
                if idx > #menu.items then
                    idx = 1
                end
                if isInteractiveType(menu.itemTypes[idx]) then
                    menu.selectedIndex = idx
                    ensureVisible(menu)
                    return true
                end
            until idx == start
        end

    elseif key == keys.enter or key == keys.space then
        local idx  = menu.selectedIndex
        local t    = menu.itemTypes[idx]
        local item = menu.items[idx]

        if t == "option" then
            if item.callback then
                item.callback()
            end
            return true

        elseif t == "checkbox" then
            local newVal = not (menu.checkboxState[idx] or false)
            menu.checkboxState[idx] = newVal
            if item.callback then
                item.callback(newVal)
            end
            return true

        elseif t == "textbox" then
            menu.editingTextbox = idx
            return true
        end

    elseif key == keys.q then
        if state.quitEnabled then
            TUI.HaltLoop()
            os.pullEvent("char")
            return true
        end
        return false
    end

    return false
end

function TUI.handleChar(char)
    local menu = currentMenu()
    if not menu then
        return false
    end

    if menu.editingTextbox then
        local idx   = menu.editingTextbox
        local value = menu.textboxState[idx] or ""
        menu.textboxState[idx] = value .. char
        local cb = menu.items[idx].callback
        if cb then
            cb(menu.textboxState[idx])
        end
        return true
    end
    return false
end

function TUI.HaltLoop()
    state.running = false
end

function TUI.run(items)
    state.stack   = {}
    state.running = false
    state.quitEnabled = true

    TUI.pushMenu(items)

    state.running = true

    while state.running and currentMenu() do
        TUI.render()

        local event, param = os.pullEvent()
        if event == "key" then
            TUI.handleKey(param)
        elseif event == "char" then
            TUI.handleChar(param)
        end
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(1, 1)
    term.setCursorBlink(true)
    term.clear()
end

return TUI
