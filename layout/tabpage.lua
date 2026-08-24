local Tabpage = {}
Tabpage.__index = Tabpage -- Share the instance methods

local curr_tabno = 1

---@class Window
local Window = loadModule("layout.window")
local Buffer = loadModule("layout.buffer")
local FrameTree = loadModule("lib.frame")
local Statusline = loadModule("lib.statusline")
local Command = loadModule("lib.command")
local CmdRead = loadModule("lib.excmd.cmdread")
local Error = loadModule("lib.error")
local AutoCmd = loadModule("lib.autocmd")
local Event = loadModule("lib.event")
local ExMsg = loadModule("lib.excmd.exmsg")
local Decoration = loadModule("lib.decoration")
local PopupMenu = loadModule("lib.popupmenu")
local ScreenDraw = loadModule("lib.screendraw")
local Options = loadModule("lib.options")
local Visual = loadModule("lib.visual")

local function all_tabpage_ids()
    local ids = {}
    for tabnr, _ in pairs(tabpages) do
        ids[#ids + 1] = tabnr
    end
    table.sort(ids)
    return ids
end

local function all_tabpage_count()
    local count = 0
    for _, _ in pairs(tabpages) do
        count = count + 1
    end
    return count
end

local function all_tabpage_ordinal(ordinal)
    local ids = all_tabpage_ids()
    if ordinal < 1 then
        ordinal = 1
    elseif ordinal > #ids then
        ordinal = #ids
    end
    return ids[ordinal]
end

local function all_tabpage_wrap_offset(current, offset)
    local ids = all_tabpage_ids()
    local current_idx = 1
    for i = 1, #ids do
        if ids[i] == current then
            current_idx = i
            break
        end
    end
    return ids[((current_idx - 1 + offset) % #ids) + 1]
end

function Tabpage:all_ids()
    return all_tabpage_ids()
end

function Tabpage:count_all()
    return all_tabpage_count()
end

function Tabpage:ordinal_all(ordinal)
    return all_tabpage_ordinal(ordinal)
end

function Tabpage:wrap_offset_all(current, offset)
    return all_tabpage_wrap_offset(current, offset)
end

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
    if stal == 2 or (stal == 1 and all_tabpage_count() > 1) then
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

local function tab_current_window(tp)
    if tp.tabnr == curtp and windows[curwin].tabpagenr == tp.tabnr then
        return windows[curwin]
    end
    if tp.lastwin and windows[tp.lastwin] and windows[tp.lastwin].tabpagenr == tp.tabnr then
        return windows[tp.lastwin]
    end
    return tp.windows[1]
end

local function default_tab_label(tp)
    local win = tab_current_window(tp)
    local name = win.buffer.name or ""
    local tail = name:match("[^/\\]+$") or name
    if tail == "" then
        tail = "[No Name]"
    end

    local prefix = ""
    if #tp.windows > 1 then
        prefix = tostring(#tp.windows)
    end
    for i = 1, #tp.windows do
        if tp.windows[i].buffer.opts.modified then
            prefix = prefix .. "+"
            break
        end
    end
    if prefix ~= "" then
        prefix = prefix .. " "
    end

    return " " .. prefix .. tail .. " "
end

local function default_tabline_format()
    local parts = {}
    local tab_ids = all_tabpage_ids()
    for i = 1, #tab_ids do
        local tabnr = tab_ids[i]
        local hl = (tabnr == curtp) and "TabLineSel" or "TabLine"
        parts[#parts + 1] = ("%%#%s#%%%dT%s"):format(hl, tabnr, default_tab_label(tabpages[tabnr]))
    end

    parts[#parts + 1] = "%#TabLineFill#%T"
    if #tab_ids > 1 then
        parts[#parts + 1] = "%=%#TabLine#%999Xclose%X"
    end

    return table.concat(parts)
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
        opts = Options.new_object_local_opts("tab"),
        winyoff = winyoff,
        _manual_root_height = nil,
        tabline_click_zones = {},
        global_statusline_click_zones = {},
    }, Tabpage)

    window.tabpagenr = curr_tabno

    tabpages[curr_tabno] = obj

    curr_tabno = curr_tabno + 1

    return obj
end

function Tabpage:equalize(axis)
    FrameTree.Equalize(self.tree, axis)
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

function Tabpage:CanWinSplit(target_winnr, new_win, vertical, opts)
    local frame = resolve_split_target(self, target_winnr)
    if not frame then
        return false
    end

    opts = opts or {}
    local laststatus = options.get("laststatus")
    local post_split_window_count = #self.windows + 1

    local function has_text_capacity(root_after, node, yoff)
        if node.split_type then
            if node.split_type == "h" then
                if not has_text_capacity(root_after, node.children[1], yoff) then
                    return false
                end
                return has_text_capacity(root_after, node.children[2], yoff + node.children[1].height)
            end
            if not has_text_capacity(root_after, node.children[1], yoff) then
                return false
            end
            return has_text_capacity(root_after, node.children[2], yoff)
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

    return FrameTree.CanSplit(self.tree, frame, new_win, vertical, {
        place_after = opts.place_after,
        validate = function(root_after)
            return has_text_capacity(root_after, root_after, 1)
        end,
    })
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

local function _first_other_modified_buf(current_buf)
    local first_bufnr
    for bufnr, buf in pairs(buffers) do
        if buf ~= current_buf and buf.opts.modified and (not first_bufnr or bufnr < first_bufnr) then
            first_bufnr = bufnr
        end
    end
    return first_bufnr and buffers[first_bufnr]
end

local function _surface_halting_buffer(buf)
    local win = windows[curwin]
    Window.SwitchBuffer(win, buf, { update_refcount = true })
    win:cursorSet(1, 1)
    win:mark_redraw()
end

local function _prepare_halting_buffers(current_buf, force, autowrite_kind)
    if force then
        return true
    end

    local autowrite_enabled = false
    if autowrite_kind == "autowrite" then
        autowrite_enabled = options.get("autowrite") or options.get("autowriteall")
    elseif autowrite_kind == "autowriteall" then
        autowrite_enabled = options.get("autowriteall")
    end

    local buf = _first_other_modified_buf(current_buf)
    while buf do
        if autowrite_enabled and not Buffer.AutowriteBlockedBuftype(buf) then
            local status = buf:write(false)
            if status == true then
                buf = _first_other_modified_buf(current_buf)
            else
                _surface_halting_buffer(buf)
                return Error(37)
            end
        else
            _surface_halting_buffer(buf)
            return Error(37)
        end
    end

    return true
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

    if halting and not frameonly then
        local halt_status = _prepare_halting_buffers(window.buffer, force, autowrite_kind)
        if halt_status ~= true then
            return halt_status
        end
    end

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
    local target_height = displayheight

    if #self.windows == 1 and self._manual_root_height ~= nil then
        target_height = math.max(1, math.min(displayheight, self._manual_root_height))
    else
        self._manual_root_height = nil
    end

    self.winyoff = winyoff

    local ok = true

    if self.tree.width ~= screen.width then
        ok = FrameTree.RootResizeWidth(self.tree, screen.width - self.tree.width) and ok
    end

    if self.tree.height ~= target_height then
        ok = FrameTree.RootResizeHeight(self.tree, target_height - self.tree.height) and ok
    end

    return ok
end

function Tabpage:WinSplit(target_winnr, new_win, vertical, opts)
    opts = opts or {}

    if opts.dry_run then
        return self:CanWinSplit(target_winnr, new_win, vertical, opts)
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

    screen.begin_frame()
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
    if redraw_tabline and (stal == 2 or (stal == 1 and all_tabpage_count() > 1)) then
        local tabline = options.get("tabline")
        if tabline == "" then
            tabline = default_tabline_format()
        end

        local info = Statusline.RenderInfo(tabline, windows[curwin], screen.width, {
            default_group = "TabLine",
            fillchar = " ",
        })
        self.tabline_click_zones = info.click_zones

        ScreenDraw.put_spans(0, 0, info.spans)
    else
        self.tabline_click_zones = {}
    end

    local redraw_global_statusline = what_redraw["all"] or redraw_windows
        or what_redraw["statusline"] or what_redraw["winbar"]
    if redraw_global_statusline and options.get("laststatus") == 3 then
        local info = Statusline.RenderInfo(options.get("statusline", windows[curwin]), windows[curwin], self.tree.width)
        self.global_statusline_click_zones = info.click_zones
        ScreenDraw.put_spans(self.winyoff + self.tree.height, 0, info.spans)
    else
        self.global_statusline_click_zones = {}
    end

    if PopupMenu.visible() then
        PopupMenu.render()
    end

    local pendingprnt = Command.PendingPrintable()
    local overlay_active = ExMsg.IsOverlayActive and ExMsg.IsOverlayActive() or false

    if not overlay_active and (what_redraw["commandline"] or what_redraw["all"] or (pendingprnt ~= lastcmd)) then
        local cmdheight = options.get("cmdheight")
        for i = 1, cmdheight do
            ScreenDraw.clear_line(screen.height - cmdheight + i - 1, "MsgArea")
        end

        if options.get("showcmd") and cmdheight > 0 then
            local scl = options.get("showcmdloc")
            if scl == "last" then
                ScreenDraw.put_text(screen.height - cmdheight, screen.width - #pendingprnt, pendingprnt, "MsgArea")
            else
                -- TODO: handle showcmd other than on last line
                error("Unhandled showcmdloc: " .. scl)
            end
        end

        if options.get("showmode") and cmdheight > 0 then
            if vimmode == "insert" then
                ScreenDraw.put_text(screen.height - 1, 0, "-- INSERT --", "ModeMsg")
            elseif vimmode == "visual" or vimmode == "select" then
                local mode = Visual.mode_char(windows[curwin].visual_kind)
                local name = vimmode == "select" and "SELECT" or "VISUAL"
                local label = (mode == "V" and "-- " .. name .. " LINE --")
                    or (mode == string.char(22) and "-- " .. name .. " BLOCK --")
                    or "-- " .. name .. " --"
                ScreenDraw.put_text(screen.height - 1, 0, label, "ModeMsg")
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
    screen.end_frame()
end

-- Transforms screen (not tree) coordinates into a frame
function Tabpage:WinAt(x, y)
    return FrameTree.GetFrameAt(self.tree, x, y - self.winyoff)
end

setmetatable(Tabpage, { __call = function(self, ...) return self:new(...) end })

return Tabpage
