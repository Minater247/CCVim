local Tabpage = {}
Tabpage.__index = Tabpage -- Share the instance methods

local curr_tabno = 1

---@class Window
local Window = loadModule("vim.layout.window")
local FrameTree = loadModule("vim.lib.frame")
local Highlight = loadModule("vim.lib.highlight")
local Statusline = loadModule("vim.lib.statusline")
local Command = loadModule("vim.lib.command")
local CmdRead = loadModule("vim.lib.excmd.cmdread")
local AutoCmd = loadModule("vim.lib.autocmd")
local Event = loadModule("vim.lib.event")
local ExMsg = loadModule("vim.lib.excmd.exmsg")

---@class TabOpts

---@class Tabpage
---@field tabnr number The unique tabpage number.
---@field windows Window[] The list of windows used in this Tabpage.
---@field tree FrameTree The FrameTree used in this Tabpage.
---@field opts TabOpts The options for this Tabpage.
---@field lastwin number The last window used on this tabpage.
---@field curdir string|nil The tabpage-local current directory.

--- Creates a new Tabpage.
---@param window Window The window to attach to the tabpage, if any.
function Tabpage:new(window)
    window = window or Window()

    local winyoff = 0
    local displayheight = screen.height -
        options.get("cmdheight") -- height of the windows
    if options.get("showtabline") == 2 then
        displayheight = displayheight - 1; winyoff = winyoff + 1
    end -- we know the tabpage will only have one window, so we can ignore the `1` case

    local obj = setmetatable({
        tabnr = curr_tabno,
        windows = { window },
        tree = FrameTree.New(window, screen.width, displayheight),
        opts = {},
        winyoff = winyoff,
        -- Double-buffering state for the whole tabpage
        _backwin = nil,
        _parent = nil,
    }, Tabpage)

    window.tabpagenr = curr_tabno

    tabpages[curr_tabno] = obj

    curr_tabno = curr_tabno + 1

    return obj
end

function Tabpage:equalize()
    FrameTree.Equalize(self.tree)
end

-- Keep a full-screen screen buffer for this tabpage
function Tabpage:_ensureBackBuffer()
    local parent = term.current()
    if self._parent ~= parent then
        self._parent = parent
        self._backwin = nil
    end

    local w = screen.width
    local h = screen.height
    local win = self._backwin
    if win then
        if win.reposition then
            win.reposition(1, 1, w, h)
        else
            win = nil
        end
    end

    if not win then
        win = window.create(parent, 1, 1, w, h, false) -- invisible while drawing
        self._backwin = win
    end

    return win
end

function Tabpage:_win_local_index(window)
    for i = 1, #self.windows do
        if self.windows[i] == window then
            return i
        end
    end
    -- Not found, nil
end

local function next_numeric_index(t, i)
    local wrap  -- smallest key > i
    local first -- smallest key overall
    for k, _ in pairs(t) do
        if not first or k < first then first = k end
        if k > i and (not wrap or k < wrap) then wrap = k end
    end
    return wrap or first
end

-- Closes a window, giving its space to other frames.
function Tabpage:close(window, force, frameonly, autowrite_kind)
    local halting
    local newcurtp
    if #self.windows == 1 then
        local myidx
        for k, v in pairs(tabpages) do
            if v == self then
                myidx = k
            end
        end

        if not myidx then
            error("Internal error: tabpage not located!")
        end

        local next = next_numeric_index(tabpages, myidx)
        if next ~= myidx then
            newcurtp = next
        else
            halting = true
        end
    end

    -- TODO: Check whether *any* buffer is unchanged, not just the current, when halting

    local idx = self:_win_local_index(window)
    if idx then
        local bufnr = window.buffer.bufnr
        local name = window.buffer.name
        local closeok
        if frameonly then closeok = true else closeok = window:close(force, halting, autowrite_kind) end
        if closeok == true then
            if not frameonly then
                AutoCmd.Run("WinClosed", { bufnr = bufnr, bufname = name })
            end
            table.remove(self.windows, idx)
            if window.frame then
                local ok, new_root = FrameTree.Close(window.frame)
                if ok and new_root then
                    self.tree = new_root
                end
            end
        else
            return closeok
        end
    end

    if newcurtp and not frameonly then
        curtp = newcurtp
        tabpages[self.tabnr] = nil
    end

    what_redraw["windows"] = true
    need_redraw = true

    -- TODO: proper previous window handling
    if not frameonly then
        if not halting then
            enterWindow(tabpages[curtp].windows[1].winnr)

            if options.get("equalalways") then
                FrameTree.Equalize(self.tree)
            end
        else
            Event.HaltLoop()
        end
    end

    if not frameonly then
        windows[window.winnr] = nil
    end
end

function Tabpage:updateFrameview()
    local winyoff = 0
    local displayheight = screen.height - options.get("cmdheight") -- height of the windows
    local stal = options.get("showtabline")
    if stal == 2 or (stal == 1 and #tabpages > 1) then
        displayheight = displayheight - 1; winyoff = winyoff + 1
    end

    self.winyoff = winyoff

    if self.tree.height ~= displayheight then
        assert(FrameTree.RootResizeHeight(self.tree, displayheight - self.tree.height))
    end
end

function Tabpage:WinSplit(target_winnr, new_win, vertical)
    if target_winnr == 0 then
        target_winnr = curwin
    end

    local frame

    if target_winnr == -1 then
        frame = self.tree
    else
        local window = windows[target_winnr]
        if not window then return end
        frame = window.frame
    end

    local set_root = frame == self.tree

    local success, new_frm
    if vertical then
        success, new_frm = FrameTree.VerticalSplit(frame, new_win)
    else
        success, new_frm = FrameTree.HorizontalSplit(frame, new_win)
    end

    if not success then
        return false
    end

    self.windows[#self.windows + 1] = new_win
    new_win.tabpagenr = self.tabnr

    if set_root then
        self.tree = new_frm
    end

    self:updateFrameview()

    -- Force a cursor update
    new_win:cursorMove(0, 0)
    windows[curwin]:cursorMove(0, 0)

    if options.get("equalalways") then
        FrameTree.Equalize(self.tree)
    end

    return true
end

function Tabpage:FindWin(target_winnr)
    local wins = self.windows
    for i = 1, #wins do
        if wins[i].winnr == target_winnr then
            return wins[i]
        end
    end
end

local lastcmd = ""

function Tabpage:render()
    self:updateFrameview()

    local backwin = self:_ensureBackBuffer()
    backwin.setVisible(false)
    local prevTerm = term.redirect(backwin)

    for i = 1, #self.windows do
        if self.windows[i].need_redraw or what_redraw["all"] or self.windows[i].floatpos or what_redraw["windows"] then
            if self.windows[i].frame then
                local x, y = FrameTree.GetXY(self.windows[i].frame)
                self.windows[i]:render(x, y + self.winyoff)
            else
                self.windows[i]:render()
            end
        end
        self.windows[i].need_redraw = false
    end

    local stal = options.get("showtabline")
    if stal == 2 or (stal == 1 and #tabpages > 1) then
        local tabline = options.get("tabline")

        -- TODO: Use a proper default for the tabline string
        tabline = (tabline == "") and "default tabline string" or tabline

        -- TODO: proper parsing for the tabline
        tabline = tabline:sub(1, screen.width)

        term.setCursorPos(1, 1)
        Highlight.SetFor("Tabline")
        term.write(tabline)
        Highlight.SetFor("TablineFill")
        term.write(string.rep(" ", screen.width - #tabline))
    end

    if options.get("laststatus") == 3 then
        term.setCursorPos(1, self.winyoff + self.tree.height)

        local spans = Statusline.Parse(options.get("statusline"), windows[curwin], self.tree.width)
        for i = 1, #spans do
            Highlight.SetFor(spans[i][2])
            term.write(spans[i][1])
        end
    end

    local pendingprnt = Command.PendingPrintable()
    local overlay_active = ExMsg.IsOverlayActive and ExMsg.IsOverlayActive() or false

    if not overlay_active and (what_redraw["commandline"] or what_redraw["all"] or (pendingprnt ~= lastcmd)) then
        Highlight.SetFor("MsgArea")
        local cmdheight = options.get("cmdheight")
        for i = 1, cmdheight do
            term.setCursorPos(1, screen.height - cmdheight + i)
            term.clearLine()
        end

        if options.get("showcmd") and cmdheight > 0 then
            local scl = options.get("showcmdloc")
            if scl == "last" then
                term.setCursorPos(screen.width - #pendingprnt + 1, screen.height - cmdheight + 1)
                term.write(pendingprnt)
            else
                -- TODO: handle showcmd other than on last line
                error("Unhandled showcmdloc: " .. scl)
            end
        end

        if options.get("showtabline") and cmdheight > 0 then
            Highlight.SetFor("ModeMsg")
            term.setCursorPos(1, screen.height)
            if vimmode == "insert" then
                term.write("-- INSERT --")
            elseif vimmode ~= "normal" then
                error("Unknown mode!")
            end
        end

        lastcmd = pendingprnt

        CmdRead.drawCmdline()
    end

    -- TODO: Commands should show up on top of the ExMsg, but the MoreMsg takes control over both
    --       input and bottom-line rendering. Needs to be looked at
    ExMsg.Redraw()
    if ExMsg.DrawOneShot then
        ExMsg.DrawOneShot()
    end

    term.redirect(prevTerm)
    backwin.setVisible(true)
end

-- Transforms screen (not tree) coordinates into a frame
function Tabpage:WinAt(x, y)
    return FrameTree.GetFrameAt(self.tree, x, y - self.winyoff)
end

setmetatable(Tabpage, { __call = function(self, ...) return self:new(...) end })

return Tabpage
