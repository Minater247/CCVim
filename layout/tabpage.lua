local Tabpage = {}
Tabpage.__index = Tabpage -- Share the instance methods

local curr_tabno = 1

---@class Window
local Window = loadModule("layout.window")
local FrameTree = loadModule("lib.frame")
local Highlight = loadModule("lib.highlight")
local Statusline = loadModule("lib.statusline")
local Command = loadModule("lib.command")
local CmdRead = loadModule("lib.excmd.cmdread")
local AutoCmd = loadModule("lib.autocmd")
local Event = loadModule("lib.event")
local ExMsg = loadModule("lib.excmd.exmsg")
local Decoration = loadModule("lib.decoration")
local PopupMenu = loadModule("lib.popupmenu")

local function statusline_rows_for_frame(laststatus, window_count, frame_bottom, root_height)
    if frame_bottom < root_height then
        return 1
    end

    if laststatus == 2 then
        return 1
    end

    if laststatus == 1 and window_count > 1 then
        return 1
    end

    return 0
end

local function compute_layout_metrics()
    local winyoff = 0
    local displayheight = screen.height - options.get("cmdheight")
    local stal = options.get("showtabline")
    if stal == 2 or (stal == 1 and #tabpages > 1) then
        displayheight = displayheight - 1
        winyoff = winyoff + 1
    end

    local global_statusline = options.get("laststatus") == 3
    if global_statusline then
        displayheight = displayheight - 1
    end

    if displayheight < 1 then
        displayheight = 1
    end

    return displayheight, winyoff, global_statusline
end

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

    local displayheight, winyoff = compute_layout_metrics()

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

local function clone_frame_tree(node, map)
    local copy = {
        parent = nil,
        window = node.window,
        width = node.width,
        height = node.height,
        split_type = node.split_type,
    }
    map[node] = copy

    if node.children then
        local left = clone_frame_tree(node.children[1], map)
        local right = clone_frame_tree(node.children[2], map)
        left.parent = copy
        right.parent = copy
        copy.children = { left, right }
    end

    return copy
end

local function resolve_split_target(self, target_winnr)
    if target_winnr == 0 then
        target_winnr = curwin
    end

    if target_winnr == -1 then
        return self.tree
    end

    local window = windows[target_winnr]
    if not window then
        return nil
    end
    return window.frame
end

function Tabpage:MakeSplitProbe(refwin)
    local opts = {}
    if refwin and refwin.opts then
        for k, v in pairs(refwin.opts) do
            opts[k] = v
        end
    end

    local probe = {
        opts = opts,
        style = refwin and refwin.style,
    }

    function probe:minwidth()
        local base = options.get("winminwidth")
        if (self.style ~= "minimal") and (options.get("number", self) or options.get("relativenumber", self)) then
            base = math.max(base, options.get("numberwidth", self) + 1)
        end
        return base
    end

    function probe:minheight()
        return options.get("winminheight")
    end

    return probe
end

function Tabpage:CanWinSplit(target_winnr, new_win, vertical)
    local frame = resolve_split_target(self, target_winnr)
    if not frame then
        return false
    end

    local frame_map = {}
    local root_clone = clone_frame_tree(self.tree, frame_map)
    local probe_frame = frame_map[frame]
    if not probe_frame then
        return false
    end

    if options.get("equalalways") and probe_frame.window then
        if vertical then
            local needed_width = probe_frame.window:minwidth() + new_win:minwidth()
            if probe_frame.width < needed_width then
                local ok = FrameTree.ResizeWidth(probe_frame, needed_width - probe_frame.width)
                if not ok or probe_frame.width < needed_width then
                    return false
                end
            end
        else
            local needed_height = probe_frame.window:minheight() + new_win:minheight()
            if probe_frame.height < needed_height then
                local ok = FrameTree.ResizeHeight(probe_frame, needed_height - probe_frame.height)
                if not ok or probe_frame.height < needed_height then
                    return false
                end
            end
        end
    end

    local ok, split_anchor
    if vertical then
        ok, split_anchor = FrameTree.VerticalSplit(probe_frame, new_win)
    else
        ok, split_anchor = FrameTree.HorizontalSplit(probe_frame, new_win)
    end
    if not ok then
        return false
    end

    local root_after = split_anchor or probe_frame or root_clone
    while root_after and root_after.parent do
        root_after = root_after.parent
    end
    if not root_after then
        return false
    end

    local laststatus = options.get("laststatus")
    local post_split_window_count = #self.windows + 1

    local function has_text_capacity(node, yoff)
        if node.split_type then
            if node.split_type == "h" then
                if not has_text_capacity(node.children[1], yoff) then
                    return false
                end
                return has_text_capacity(node.children[2], yoff + node.children[1].height)
            end
            if not has_text_capacity(node.children[1], yoff) then
                return false
            end
            return has_text_capacity(node.children[2], yoff)
        end

        local frame_bottom = yoff + node.height - 1
        local status_rows = statusline_rows_for_frame(
            laststatus,
            post_split_window_count,
            frame_bottom,
            root_after.height
        )
        local text_rows = node.height - status_rows
        if text_rows < 1 then
            return false
        end

        local min_text_rows = tonumber(node.window:minheight()) or 1
        if text_rows < min_text_rows then
            return false
        end

        return true
    end

    return has_text_capacity(root_after, 1)
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
        -- If closing the current window may wipe/delete its buffer, switch to another
        -- window first so BufLeave callbacks run with a valid current buffer context.
        local switched_before_close = false
        if not frameonly and window.winnr == curwin and #self.windows > 1 then
            local bufhidden = options.get("bufhidden", nil, window.buffer)
            local may_drop_from_registry = (bufhidden == "wipe" or bufhidden == "delete")
                and ((window.buffer.refcount or 0) <= 1)
            if may_drop_from_registry then
                local target = (self.windows[1] ~= window) and self.windows[1] or self.windows[2]
                if target then
                    enterWindow(target.winnr)
                    switched_before_close = true
                end
            end
        end

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
            if switched_before_close and windows[window.winnr] then
                enterWindow(window.winnr)
            end
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

    return true
end

function Tabpage:updateFrameview()
    local displayheight, winyoff = compute_layout_metrics()

    self.winyoff = winyoff

    local ok = true

    if self.tree.width ~= screen.width then
        ok = FrameTree.RootResizeWidth(self.tree, screen.width - self.tree.width) and ok
    end

    if self.tree.height ~= displayheight then
        ok = FrameTree.RootResizeHeight(self.tree, displayheight - self.tree.height) and ok
    end

    return ok
end

function Tabpage:WinSplit(target_winnr, new_win, vertical, opts)
    opts = opts or {}

    if opts.dry_run then
        return self:CanWinSplit(target_winnr, new_win, vertical)
    end

    local frame = resolve_split_target(self, target_winnr)
    if not frame then
        return false
    end

    local set_root = frame == self.tree

    local grew_for_split = false
    if options.get("equalalways") and frame.window then
        if vertical then
            local needed_width = frame.window:minwidth() + new_win:minwidth()
            if frame.width < needed_width then
                if not FrameTree.ResizeWidth(frame, needed_width - frame.width) or frame.width < needed_width then
                    return false
                end
                grew_for_split = true
            end
        else
            local needed_height = frame.window:minheight() + new_win:minheight()
            if frame.height < needed_height then
                if not FrameTree.ResizeHeight(frame, needed_height - frame.height) or frame.height < needed_height then
                    return false
                end
                grew_for_split = true
            end
        end
    end

    local success, new_frm
    if vertical then
        success, new_frm = FrameTree.VerticalSplit(frame, new_win, opts.place_after == true)
    else
        success, new_frm = FrameTree.HorizontalSplit(frame, new_win, opts.place_after == true)
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

    if options.get("equalalways") and (not opts.skip_equalize or grew_for_split) then
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
    Decoration.begin_redraw()
    local redraw_windows = what_redraw["all"] or what_redraw["windows"]

    for i = 1, #self.windows do
        if self.windows[i].need_redraw or redraw_windows or self.windows[i].floatpos then
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
    local redraw_tabline = what_redraw["all"] or what_redraw["tabline"] or redraw_windows
    if redraw_tabline and (stal == 2 or (stal == 1 and #tabpages > 1)) then
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

    local redraw_global_statusline = what_redraw["all"] or redraw_windows
        or what_redraw["statusline"] or what_redraw["winbar"]
    if redraw_global_statusline and options.get("laststatus") == 3 then
        term.setCursorPos(1, self.winyoff + self.tree.height + 1)

        local spans = Statusline.Parse(options.get("statusline", windows[curwin]), windows[curwin], self.tree.width)
        for i = 1, #spans do
            Highlight.SetFor(spans[i][2])
            term.write(spans[i][1])
        end
    end

    if PopupMenu.visible() then
        PopupMenu.render()
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

    Decoration.end_redraw()
    term.redirect(prevTerm)
    backwin.setVisible(true)
end

-- Transforms screen (not tree) coordinates into a frame
function Tabpage:WinAt(x, y)
    return FrameTree.GetFrameAt(self.tree, x, y - self.winyoff)
end

setmetatable(Tabpage, { __call = function(self, ...) return self:new(...) end })

return Tabpage
