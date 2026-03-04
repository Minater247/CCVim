-- vim/lib/autocmd.lua  (fixed)

local Autocmd               = {}

local scopes                = loadModule("lib.luaapi.scopes")
local Error                 = loadModule("lib.error")
local ExMsg                 = loadModule("lib.excmd.exmsg")
local Runtime

---@class Autocommand
---@field pattern table<string, boolean>  -- set of patterns
---@field command string|nil
---@field callback function|string|nil
---@field once boolean
---@field nested boolean
---@field group number
---@field event table<string, boolean>    -- set of events
---@field desc string|nil
---@field id number
---@field script_ctx string|nil
---@field script_state table|nil

-- === Internal state ===
local currautocommandid     = 1
local currauc_seq           = 1 -- Def

-- Separate namespaces to avoid key collision
local autocommands_by_group = {} -- [group:number] -> { Autocommand, ... }
local autocommands_by_id    = {} -- [id:number]    -> Autocommand

-- Default group is "all" (group id = 1, implicit)
local currautocmdgroup      = 2
-- name -> id
local autocmdgroups         = {}

-- Whether autocommands are disabled
local autocmd_disabled      = false

-- Known event names (case-insensitive). Keep in sync with runtime docs.
local EVENT_LIST = {
    "BufAdd",
    "BufDelete",
    "BufEnter",
    "BufFilePost",
    "BufFilePre",
    "BufHidden",
    "BufLeave",
    "BufModifiedSet",
    "BufNew",
    "BufNewFile",
    "BufRead",
    "BufReadPost",
    "BufReadCmd",
    "BufReadPre",
    "BufUnload",
    "BufWinEnter",
    "BufWinLeave",
    "BufWipeout",
    "BufWrite",
    "BufWritePre",
    "BufWriteCmd",
    "BufWritePost",
    "ChanInfo",
    "ChanOpen",
    "CmdUndefined",
    "CmdlineChanged",
    "CmdlineEnter",
    "CmdlineLeave",
    "CmdwinEnter",
    "CmdwinLeave",
    "ColorScheme",
    "ColorSchemePre",
    "CompleteChanged",
    "CompleteDonePre",
    "CompleteDone",
    "CursorHold",
    "CursorHoldI",
    "CursorMoved",
    "CursorMovedI",
    "DiffUpdated",
    "DirChanged",
    "DirChangedPre",
    "ExitPre",
    "FileAppendCmd",
    "FileAppendPost",
    "FileAppendPre",
    "FileChangedRO",
    "FileChangedShell",
    "FileChangedShellPost",
    "FileReadCmd",
    "FileReadPost",
    "FileReadPre",
    "FileType",
    "FileWriteCmd",
    "FileWritePost",
    "FileWritePre",
    "FilterReadPost",
    "FilterReadPre",
    "FilterWritePost",
    "FilterWritePre",
    "FocusGained",
    "FocusLost",
    "FuncUndefined",
    "UIEnter",
    "UILeave",
    "InsertChange",
    "InsertCharPre",
    "InsertEnter",
    "InsertLeavePre",
    "InsertLeave",
    "MenuPopup",
    "ModeChanged",
    "OptionSet",
    "QuickFixCmdPre",
    "QuickFixCmdPost",
    "QuitPre",
    "RemoteReply",
    "SearchWrapped",
    "RecordingEnter",
    "RecordingLeave",
    "SessionLoadPost",
    "ShellCmdPost",
    "Signal",
    "ShellFilterPost",
    "SourcePre",
    "SourcePost",
    "SourceCmd",
    "SpellFileMissing",
    "StdinReadPost",
    "StdinReadPre",
    "SwapExists",
    "Syntax",
    "TabEnter",
    "TabLeave",
    "TabNew",
    "TabNewEntered",
    "TabClosed",
    "TermOpen",
    "TermEnter",
    "TermLeave",
    "TermClose",
    "TermResponse",
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
    "TextChangedT",
    "TextYankPost",
    "User",
    "UserGettingBored",
    "VimEnter",
    "VimLeave",
    "VimLeavePre",
    "VimResized",
    "VimResume",
    "VimSuspend",
    "WinClosed",
    "WinEnter",
    "WinLeave",
    "WinNew",
    "WinScrolled",
    "WinResized",
    -- Newer/autodoc events not present in the bundled autocmd.txt
    "DiagnosticChanged",
    "LspAttach",
    "LspDetach",
    "LspTokenUpdate",
}

local EVENT_SET = {}
local EVENT_CANON = {}
for _, name in ipairs(EVENT_LIST) do
    local key = name:lower()
    EVENT_SET[key] = true
    EVENT_CANON[key] = name
end

function Autocmd.IsValidEvent(name)
    if type(name) ~= "string" then return false end
    return EVENT_SET[name:lower()] == true
end

function Autocmd.NormalizeEvent(name)
    if type(name) ~= "string" then return name end
    return EVENT_CANON[name:lower()] or name
end

local function augroup_as_integer(group)
    if type(group) == "string" then
        return autocmdgroups[group]
    end
    return group
end

local function normalize_pattern(p)
    if p == "<buffer>" then
        return ("<buffer=%d>"):format(windows[curwin].buffer.bufnr)
    end
    return p
end

-- ===== Groups =====

function Autocmd.CreateAugroup(name, clear)
    local group = autocmdgroups[name]

    if clear and group then
        -- Clear per-group list
        autocommands_by_group[group] = {}

        -- Drop all ids that belong to this group
        for id, obj in pairs(autocommands_by_id) do
            if obj.group == group then
                autocommands_by_id[id] = nil
            end
        end
    end

    if not group then
        group = currautocmdgroup
        currautocmdgroup = currautocmdgroup + 1
        autocmdgroups[name] = group
    end

    return group
end

function Autocmd.GetAugroupId(name)
    return autocmdgroups[name]
end

function Autocmd.GroupHasAutocommands(group)
    local gid = augroup_as_integer(group)
    if not gid then
        return false
    end
    local list = autocommands_by_group[gid]
    return (list ~= nil and #list > 0) or false
end

-- === Current augroup selection ===
local current_group_id = 1 -- default (unnamed) group

function Autocmd.SetCurrentGroup(group)
    current_group_id = augroup_as_integer(group) or 1
    return current_group_id
end

function Autocmd.GetCurrentGroup()
    return current_group_id
end

-- Delete an augroup by name (augroup!)
-- Returns: ok:boolean, err:string|nil, warn:string|nil
function Autocmd.DeleteAugroup(name)
    if not name or name == "" then
        return false, Error(471)
    end
    if name:lower() == "end" then
        return false, Error(475, "end")
    end
    local gid = autocmdgroups[name]
    if not gid then
        return false, Error(367, name)
    end
    if gid == current_group_id then
        return false, Error(936)
    end

    local count = 0
    local list = autocommands_by_group[gid]
    if list then count = #list end

    -- remove all autocommands in that group
    autocommands_by_group[gid] = nil
    for id, ac in pairs(autocommands_by_id) do
        if ac.group == gid then autocommands_by_id[id] = nil end
    end
    -- remove the group name mapping
    autocmdgroups[name] = nil

    local warn
    if count > 0 then
        -- TODO: Add a warning file similar to Error for warnings
        warn = ("W19: Deleting augroup that still has autocommands: %s"):format(name)
    end
    return true, nil, warn
end

-- ===== Create / Remove =====

function Autocmd.CreateAutocommand(events, patterns, callback, command, group, once, nested, desc, script_ctx)
    group = augroup_as_integer(group) or 1

    local id = currautocommandid
    currautocommandid = currautocommandid + 1

    local bucket = autocommands_by_group[group]
    if not bucket then
        bucket = {}
        autocommands_by_group[group] = bucket
    end

    local eventmap = {}
    for _, v in ipairs(events or {}) do
        local ev = Autocmd.NormalizeEvent(v)
        eventmap[ev] = true
    end

    local patternmap = {}
    for _, v in ipairs(patterns or {}) do
        local nv = normalize_pattern(v)
        patternmap[nv] = true
    end

    local seq = currauc_seq
    currauc_seq = currauc_seq + 1

    local durable_script_state
    if type(callback) == "string" or type(command) == "string" then
        Runtime = Runtime or loadModule("lib.excmd.runtime")
        durable_script_state = Runtime.CaptureDurableScriptState({ script_ctx = script_ctx })
    end

    local autocmdobj = {
        event    = eventmap,
        pattern  = patternmap,
        command  = command,
        callback = callback,
        once     = once or false,
        nested   = nested or false,
        id       = id,
        seq      = seq,
        group    = group,
        desc     = desc,
        script_ctx = (type(script_ctx) == "string" and script_ctx ~= "") and script_ctx,
        script_state = durable_script_state,
    }

    table.insert(bucket, autocmdobj)
    autocommands_by_id[id] = autocmdobj
    if eventmap["BufEnter"] or eventmap["VimEnter"] then
        local cdetail
        if command then
            cdetail = command
        elseif type(callback) == "function" then
            cdetail = "<lua-callback>"
        elseif type(callback) == "string" then
            cdetail = callback
        else
            cdetail = "<no-callback>"
        end
        LOG_DEBUG("CreateAutocommand events=%s group=%s patterns=%s cmd=%s",
            tostring(events and table.concat(events, ",") or "<nil>"),
            tostring(group),
            tostring(patterns and table.concat(patterns, ",") or "<nil>"),
            tostring(cdetail))
    end
    LOG_INTERNAL("autocmd",
        "CreateAutocommand id=%d group=%s events=%s patterns=%s callback=%s once=%s nested=%s desc=%s",
        id,
        tostring(group),
        (events and table.concat(events, ",") or "<nil>"),
        (patterns and table.concat(patterns, ",") or "<nil>"),
        (callback and (type(callback) == "string" and callback or "<fn>") or tostring(command)),
        tostring(once), tostring(nested), tostring(desc)
    )
    return id
end

-- Remove by filters; returns count removed.
--   group    : string|number|nil (nil => default group 1)
--   events   : {string,...}|nil
--   patterns : {string,...}|nil ("*" or nil => any pattern)
function Autocmd.RemoveAutocommands(group, events, patterns)
    if type(group) == "string" then
        local gid = augroup_as_integer(group)
        if not gid then return 0 end
        group = gid
    elseif group == nil then
        group = 1
    end
    local list = autocommands_by_group[group]
    if not list or #list == 0 then return 0 end

    local evset, anyevent = nil, false
    if events and #events > 0 then
        evset = {}
        for _, e in ipairs(events) do
            if e == "*" then
                anyevent = true
            else
                evset[Autocmd.NormalizeEvent(e)] = true
            end
        end
    end

    local pset, anypat = nil, false
    if patterns and #patterns > 0 then
        pset = {}
        for _, p in ipairs(patterns) do
            if p == "*" then anypat = true end
            local np = normalize_pattern(p)
            pset[np] = true
        end
    end

    local removed = 0
    for i = #list, 1, -1 do
        local ac = list[i]
        local ev_ok = true
        if evset then
            ev_ok = anyevent
            if not ev_ok then
                ev_ok = false
                for ev, _ in pairs(ac.event) do
                    if evset[ev] then
                        ev_ok = true; break
                    end
                end
            end
        end

        local pat_ok = true
        if pset then
            pat_ok = anypat
            if not pat_ok then
                for pat, _ in pairs(ac.pattern) do
                    if pset[pat] then
                        pat_ok = true; break
                    end
                end
            end
        end

        if ev_ok and pat_ok then
            -- remove from per-group list
            table.remove(list, i)
            -- drop id entry
            autocommands_by_id[ac.id] = nil
            removed = removed + 1
        end
    end

    return removed
end

-- === internal helpers for running ===
local function _remove_by_id(id)
    local ac = autocommands_by_id[id]
    if not ac then return false end
    local list = autocommands_by_group[ac.group]
    if list then
        for i = #list, 1, -1 do
            if list[i].id == id then
                table.remove(list, i)
                break
            end
        end
    end
    autocommands_by_id[id] = nil
    LOG_INTERNAL("autocmd", "_remove_by_id id=%d group=%s", id, tostring(ac.group))
    return true
end

function Autocmd.RemoveById(id)
    return _remove_by_id(id)
end

local function _glob_match(glob, text)
    -- Escape Lua pattern magic except * and ?
    local pat = glob:gsub("([%^%$%(%)%.%[%]%+%-])", "%%%1")
    pat = "^" .. pat:gsub("%*", ".*"):gsub("%?", ".") .. "$"
    return text:match(pat) ~= nil
end

local function _patternmap_matches(pset, ctx)
    if not pset or next(pset) == nil or (ctx.pattern_target == "*") then
        return true -- no pattern means "match any"
    end
    -- Allow event-specific match target via ctx.pattern_target; default to bufname
    local name  = (ctx.pattern_target) or ((ctx.bufname) or "")
    local bufnr = ctx.bufnr

    for pat, _ in pairs(pset) do
        if pat == "*" then
            return true
        end
        local n = pat:match("^<buffer=(%d+)>$")
        if n then
            if bufnr and bufnr == tonumber(n) then return true end
        elseif pat == "<buffer>" then
            -- Best-effort fallback if host didn't normalize at creation:
            -- treat as "current buffer at trigger"; matches if we have a bufnr.
            if bufnr ~= nil then return true end
        else
            if _glob_match(pat, name) then return true end
        end
    end
    return false
end

-- Map verbose mode names to short codes used by Vim's ModeChanged pattern.
local function _mode_short(name)
    if not name then return "?" end
    local map = {
        normal   = "n",
        insert   = "i",
        visual   = "v",
        select   = "s",
        cmdline  = "c",
        replace  = "R",
        operator = "o",
        terminal = "t",
    }
    return map[name] or tostring(name):sub(1, 1)
end

-- Event-specific pattern matching and context adapters
-- Each handler: function(ctx) -> { pattern_target = string|nil, cb = table|nil }
--  - pattern_target: overrides the default name used by _patternmap_matches
--  - cb            : key/values merged into callback context
local event_match_behavior = {}

function Autocmd.SetEventPatternMatcher(event, fn)
    if type(event) ~= "string" or type(fn) ~= "function" then return false end
    event_match_behavior[event] = fn
    return true
end

-- Built-in: ModeChanged - match against "old:new" using short mode codes.
Autocmd.SetEventPatternMatcher("ModeChanged", function(ctx)
    local oldm = ctx and (ctx.old_mode or ctx.mode_old)
    local newm = ctx and (ctx.new_mode or ctx.mode_new)
    return {
        pattern_target = (_mode_short(oldm) .. ":" .. _mode_short(newm)),
        cb = { old_mode = oldm, new_mode = newm },
    }
end)

-- v:event lifecycle management
-- We intentionally keep the same table reference (scopes._v.event) and mutate
-- its contents so that any code holding a reference to vim.v.event sees the
-- updates (Neovim semantics discourage storing it, but plugins sometimes do).
-- Nested autocmds: push current snapshot, apply new, run, then restore.
local _event_stack = {}
local function _with_event_dict(temp, run)
    local evtbl = scopes._v.event
    if not evtbl then
        scopes._v.event = {}
        evtbl = scopes._v.event
    end

    -- snapshot current (cheap shallow copy; keys are simple scalars)
    local snap = {}
    for k, v in pairs(evtbl) do snap[k] = v end
    _event_stack[#_event_stack + 1] = snap

    -- replace contents with new temp dict
    for k in pairs(evtbl) do evtbl[k] = nil end
    if temp then for k, v in pairs(temp) do evtbl[k] = v end end

    local ok, err = pcall(run)

    -- restore previous snapshot (or empty if none)
    local prev = _event_stack[#_event_stack]
    _event_stack[#_event_stack] = nil
    for k in pairs(evtbl) do evtbl[k] = nil end
    if prev then for k, v in pairs(prev) do evtbl[k] = v end end

    if not ok then error(err) end
end

local function _find_window_for_bufnr(bufnr)
    if not bufnr then
        return nil
    end

    local cur = windows[curwin]
    if cur.buffer.bufnr == bufnr then
        return curwin
    end

    local fallback = nil
    for winid, win in pairs(windows) do
        if win.buffer.bufnr == bufnr then
            if win.tabpagenr == curtp then
                return winid
            end
            fallback = fallback or winid
        end
    end
    return fallback
end

local function _restore_current_window(old_curwin)
    if old_curwin and windows[old_curwin] then
        curwin = old_curwin
        return
    end
    for winid, _ in pairs(windows) do
        curwin = winid
        return
    end
end

-- Execute callback/command in the target autocmd buffer context.
-- If the buffer is visible, switch to its window; otherwise temporarily swap
-- the current window's buffer.
local function _with_autocmd_buffer(bufnr, run)
    if type(run) ~= "function" then
        return
    end
    if not bufnr then
        return run()
    end

    local old_curwin = curwin
    local old_win = windows[old_curwin]
    if not old_win then
        return run()
    end

    local switched_win = false
    local swapped_buf = false
    local old_buf = old_win.buffer

    local target_win = _find_window_for_bufnr(bufnr)
    if target_win and target_win ~= curwin then
        curwin = target_win
        switched_win = true
    elseif not target_win then
        local target_buf = buffers[bufnr]
        if target_buf and old_win.buffer ~= target_buf then
            old_win.buffer = target_buf
            swapped_buf = true
        end
    end

    local ok, result_or_err, result2 = pcall(run)

    if swapped_buf and old_win then
        old_win.buffer = old_buf
    end
    if switched_win then
        _restore_current_window(old_curwin)
    end

    if not ok then
        error(result_or_err)
    end
    return result_or_err, result2
end

local function _call_callback(cb, ac, event, ctx)
    -- Build v.event dict (best-effort subset depending on event)
    local ve = { event = event }
    if ctx then
        if ctx.match ~= nil then ve.match = ctx.match end
        if ctx.file ~= nil then ve.file = ctx.file end
        if ctx.buf ~= nil then ve.buf = ctx.buf end
    end
    if event == "ModeChanged" then
        ve.scope = "global"
        ve.old_mode = ctx and ctx.old_mode
        ve.new_mode = ctx and ctx.new_mode
    elseif event == "DirChanged" then
        -- Expected keys (subset): scope, cwd, changed_window
        ve.scope = (ctx and ctx.data and ctx.data.scope) or "global"
        -- Support both old (cwd) and new (new_cwd) naming; choose new_cwd when present
        if ctx and ctx.data then
            ve.cwd = ctx.data.new_cwd or ctx.data.cwd
            ve.changed_window = ctx.data.changed_window or false
        end
    elseif event == "WinResized" then
        ve.windows = (ctx and ctx.data and ctx.data.windows) or {}
    elseif event == "CompleteChanged" then
        if ctx and ctx.data then
            ve.completed_item = ctx.data.completed_item or {}
            ve.height = ctx.data.height
            ve.width = ctx.data.width
            ve.row = ctx.data.row
            ve.col = ctx.data.col
            ve.size = ctx.data.size
            ve.scrollbar = ctx.data.scrollbar
            ve.complete_type = ctx.data.complete_type
        end
    elseif event == "CompleteDonePre" or event == "CompleteDone" then
        if ctx and ctx.data then
            ve.completed_item = ctx.data.completed_item or {}
            ve.reason = ctx.data.reason
            ve.complete_type = ctx.data.complete_type
            ve.complete_word = ctx.data.complete_word
        end
    end

    if type(cb) == "function" then
        local info = {
            event   = event,
            bufnr   = ctx.bufnr,
            bufname = ctx.bufname,
            buf     = ctx.buf,
            file    = ctx.file,
            match   = ctx.match,
            group   = ac.group,
            id      = ac.id,
            desc    = ac.desc,
        }
        if ctx then
            if ctx.old_mode ~= nil then info.old_mode = ctx.old_mode end
            if ctx.new_mode ~= nil then info.new_mode = ctx.new_mode end
            if ctx.data ~= nil then info.data = ctx.data end
        end
        _with_event_dict(ve, function()
            local ok, err = pcall(function()
                _with_autocmd_buffer(ctx and ctx.bufnr, function()
                    cb(info)
                end)
            end)
            if not ok then
                LOG_DEBUG("autocmd %d callback error: %s", ac.id, err)
            end
        end)
        return
    elseif type(cb) == "string" then
        Runtime = Runtime or loadModule("lib.excmd.runtime")
        LOG_INTERNAL("autocmd", "autocmd %d executing Ex command string: %s", ac.id, tostring(cb))
        if event == "BufEnter" or event == "VimEnter" or event == "BufRead" or event == "BufReadCmd" then
            LOG_DEBUG("autocmd %d event=%s executing: %s", ac.id, tostring(event), tostring(cb))
        end
        _with_event_dict(ve, function()
            local run_opts = nil
            local ac_source = ac.script_ctx
            if ac.script_state then
                local runtime_state = Runtime.MakeRuntimeState(ac.script_state)
                run_opts = { state = runtime_state }
                local state_ctx = ac.script_state.script_ctx
                if state_ctx ~= nil and state_ctx ~= "" then
                    run_opts.script_ctx = state_ctx
                    ac_source = state_ctx
                end
            elseif ac.script_ctx then
                run_opts = { script_ctx = ac.script_ctx }
            end
            if run_opts then
                run_opts.origin = {
                    kind = "autocmd",
                    event = event,
                    id = ac.id,
                    group = ac.group,
                    source = ac_source,
                }
            else
                run_opts = {
                    origin = {
                        kind = "autocmd",
                        event = event,
                        id = ac.id,
                        group = ac.group,
                        source = ac_source,
                    },
                }
            end

            local ok_call, ok, rv = pcall(function()
                return _with_autocmd_buffer(ctx and ctx.bufnr, function()
                    return Runtime.run(cb, run_opts)
                end)
            end)
            local ac_desc = ac.desc or ""
            local ac_match = ctx and ctx.match or ""
            if not ok_call then
                LOG_DEBUG(
                    "autocmd %d event=%s execution error: %s (group=%s source=%s match=%s desc=%s cmd=%s)",
                    ac.id,
                    event,
                    tostring(ok),
                    tostring(ac.group),
                    tostring(ac_source),
                    tostring(ac_match),
                    tostring(ac_desc),
                    tostring(cb)
                )
                return
            end

            local rvstr = tostring(rv)
            if not ok and Error.IsError(rv) then
                rvstr = rv:toString()
            end
            LOG_INTERNAL("autocmd", "autocmd %d Ex command returned ok=%s rv=%s", ac.id, tostring(ok), rvstr)
            if not ok then
                LOG_DEBUG(
                    "autocmd %d event=%s failed: %s (group=%s source=%s match=%s desc=%s cmd=%s)",
                    ac.id,
                    event,
                    rvstr,
                    tostring(ac.group),
                    tostring(ac_source),
                    tostring(ac_match),
                    tostring(ac_desc),
                    tostring(cb)
                )
            end
        end)
    end
end

-- ===== Run =====
-- Fire autocommands for a given event.
--   event : string (e.g., "BufEnter")
--   ctx   : { bufnr=number?, bufname=string?, group=number|string? }
-- Returns the number of autocommands that *matched* (regardless of callback presence).
function Autocmd.Run(event, ctx)
    ctx = ctx or {}
    event = Autocmd.NormalizeEvent(event)
    local force = (ctx.force == true)

    if autocmd_disabled and not force then
        LOG_DEBUG("autocommands disabled: not firing %s", event); return
    elseif autocmd_disabled and force then
        LOG_DEBUG("autocommands disabled: force-running %s", event)
    end

    LOG_INTERNAL("autocmd", "Run event=%s ctx.bufname=%s buf=%s group=%s", event, tostring(ctx.bufname),
        tostring(ctx.bufnr), tostring(ctx.group))

    local eventignore = options.get("eventignore")
    local eistate = {
        ignored = {},
        unignored = {},
        all = false,
    }
    for option in eventignore:gmatch("[^,]+") do
        if option:sub(1, 1) == "-" then
            if option:sub(2) == "all" then
                eistate.all = false
            else
                eistate.unignored[#eistate.unignored + 1] = option:sub(2)
            end
        else
            eistate.ignored[#eistate.ignored + 1] = option
        end
    end
    if eistate.all or ((eistate.ignored[event]) and (not eistate.unignored[event])) then
        LOG_DEBUG("EVENT IGNORED: %s", event)
        return 0
    end

    local bufnr     = ctx.bufnr or windows[curwin].buffer.bufnr
    local bufname   = (ctx.bufname or windows[curwin].buffer.name) or ""
    local match_ctx = { bufnr = bufnr, bufname = bufname }
    local cb_ctx    = { bufnr = bufnr, bufname = bufname }

    if ctx.pattern ~= nil then
        match_ctx.pattern_target = ctx.pattern
    end
    if ctx.data ~= nil then
        cb_ctx.data = ctx.data
    end

    -- Event-specific matching/context via registry (defaults to buffer name when absent)
    do
        local handler = event_match_behavior[event]
        if handler then
            local res = handler(ctx or {})
            if res then
                if res.pattern_target ~= nil then
                    match_ctx.pattern_target = res.pattern_target
                end
                if res.cb then
                    for k, v in pairs(res.cb) do cb_ctx[k] = v end
                end
            end
        end
    end
    -- Provide common v:event fields for <amatch>/<afile>/<abuf> expansion.
    cb_ctx.event = event
    cb_ctx.match = match_ctx.pattern_target or match_ctx.bufname
    cb_ctx.file = cb_ctx.bufname
    cb_ctx.buf = cb_ctx.bufnr

    local groups = {}

    if ctx.group ~= nil then
        local g = augroup_as_integer(ctx.group) or 1
        groups[#groups + 1] = g
    else
        for g, _ in pairs(autocommands_by_group) do
            groups[#groups + 1] = g
        end
    end

    local matched = 0

    -- Collect all matching autocommands across the selected groups
    local candidates = {}
    for _, g in ipairs(groups) do
        local list = autocommands_by_group[g]
        if list and #list > 0 then
            for i = 1, #list do
                local ac = list[i]
                if ac and ac.event[event] and _patternmap_matches(ac.pattern, match_ctx) then
                    candidates[#candidates + 1] = ac
                end
            end
        end
    end

    -- Targeted debug logging for startup/path events
    if event == "BufEnter" or event == "VimEnter" or event == "BufRead" or event == "BufReadCmd" then
        LOG_DEBUG("AutoCmd.Run event=%s bufname=%s bufnr=%s candidates=%d", event, tostring(bufname),
            tostring(bufnr), #candidates)
        for _, ac in ipairs(candidates) do
            local cdetail
            if ac.command then
                cdetail = ac.command
            elseif type(ac.callback) == "function" then
                cdetail = "<lua-callback>"
            elseif type(ac.callback) == "string" then
                cdetail = ac.callback
            else
                cdetail = "<no-callback>"
            end
            LOG_DEBUG("AutoCmd event=%s id=%d group=%d cmd=%s", event, ac.id, ac.group, tostring(cdetail))
        end
    end

    -- Global FIFO: sort by definition order (seq ascending)
    table.sort(candidates, function(a, b) return a.seq < b.seq end)

    -- Stable snapshot of IDs in that order
    local ids = {}
    for i = 1, #candidates do
        ids[i] = candidates[i].id
    end

    -- Execute in FIFO order
    for _, id in ipairs(ids) do
        local ac = autocommands_by_id[id]
        if ac and ac.event[event] and _patternmap_matches(ac.pattern, match_ctx) then
            matched = matched + 1

            local prev_autocmddisabled = autocmd_disabled
            if not ac.nested then autocmd_disabled = true end

            LOG_INTERNAL("autocmd", "autocmd %d matched event=%s group=%d id=%d desc=%s",
                ac.id, event, ac.group, ac.id, ac.desc or "")

            if ac.callback ~= nil then
                LOG_INTERNAL("autocmd", "autocmd %d executing callback type=%s", ac.id, type(ac.callback))
                _call_callback(ac.callback, ac, event, cb_ctx)
            elseif ac.command ~= nil then
                LOG_INTERNAL("autocmd", "autocmd %d executing command: %s", ac.id, tostring(ac.command))
                _call_callback(ac.command, ac, event, cb_ctx)
            else
                LOG_INTERNAL("autocmd", "autocmd %d matched but has no callback/command", ac.id)
                LOG_DEBUG("autocmd %d matched (%s) but has no callback/command; nothing to run", ac.id, event)
            end

            if ac.once then
                LOG_INTERNAL("autocmd", "autocmd %d is once; removing", ac.id)
                _remove_by_id(ac.id)
            end

            if not ac.nested then
                autocmd_disabled = prev_autocmddisabled
            end
        end
    end

    return matched
end

local function _group_name(gid)
    for name, id in pairs(autocmdgroups) do
        if id == gid then return name end
    end
    return "" -- unnamed/default group prints blank like Vim
end

function Autocmd.List(opts)
    opts                  = opts or {}
    local gfilter         = augroup_as_integer(opts.group)
    local gfilter_missing = (type(opts.group) == "string" and gfilter == nil)
    local events          = opts.events
    local pats            = opts.pattern

    local evset, anyevent = nil, false
    if events and #events > 0 then
        evset = {}
        for _, e in ipairs(events) do
            if e == "*" then
                anyevent = true
            else
                evset[Autocmd.NormalizeEvent(e)] = true
            end
        end
    end

    local pset, anypat = nil, false
    if pats and #pats > 0 then
        pset = {}
        for _, p in ipairs(pats) do
            if p == "*" then anypat = true end
            pset[normalize_pattern(p)] = true
        end
    end

    -- which groups to show?
    local groups = {}
    if gfilter_missing then
        groups = {}
    elseif gfilter then
        groups[1] = gfilter
    else
        for gid, list in pairs(autocommands_by_group) do
            if list and #list > 0 then
                groups[#groups + 1] = gid
            end
        end
        table.sort(groups)
    end

    ExMsg.echo("--- Autocommands ---")

    for _, gid in ipairs(groups) do
        local list = autocommands_by_group[gid]
        if list and #list > 0 then
            -- group by event so we can print a single "Group  Event" header, then rows
            local by_event = {}

            for _, ac in ipairs(list) do
                -- events on this autocommand
                for ev, _ in pairs(ac.event) do
                    if (not evset) or anyevent or evset[ev] then
                        -- decide which patterns to display (filter if requested)
                        local pats_here = {}
                        for pat, _ in pairs(ac.pattern) do pats_here[#pats_here + 1] = pat end
                        table.sort(pats_here)

                        local function pattern_selected(pat)
                            if not pset then return true end
                            if anypat then return true end
                            return pset[pat] == true
                        end

                        local selected = {}
                        for _, pat in ipairs(pats_here) do
                            if pattern_selected(pat) then
                                -- choose a display text
                                local text
                                if ac.callback ~= nil then
                                    if type(ac.callback) == "function" then
                                        local info = debug.getinfo(ac.callback, "S")
                                        local src  = info and (info.source or info.short_src) or "?"
                                        local ln   = info and (info.linedefined or 0) or 0
                                        -- mimic Neovim style: <Lua N: path:line>
                                        text       = ("<Lua %d: %s:%d>"):format(ln, src, ln)
                                    else -- string Ex command payload
                                        text = tostring(ac.callback)
                                    end
                                elseif ac.command ~= nil then
                                    -- fallback if someone used 'command' field
                                    text = tostring(ac.command)
                                else
                                    text = "(no command)"
                                end
                                selected[#selected + 1] = { pattern = pat, text = text }
                            end
                        end

                        if #selected > 0 then
                            local bucket = by_event[ev] or {}
                            -- Preserve insertion order (append)
                            for _, row in ipairs(selected) do
                                bucket[#bucket + 1] = row
                            end
                            by_event[ev] = bucket
                        end
                    end
                end
            end

            -- Emit for this group
            local gname = _group_name(gid)
            local evnames = {}
            for ev, rows in pairs(by_event) do
                if rows and #rows > 0 then evnames[#evnames + 1] = ev end
            end
            table.sort(evnames)

            for _, ev in ipairs(evnames) do
                ExMsg.echo((gname ~= "" and gname or " ") .. "  " .. ev)

                local rows = by_event[ev]
                -- compute pattern column width for this header
                local w = 8
                for _, row in ipairs(rows) do
                    if #row.pattern > w then w = #row.pattern end
                end
                for _, row in ipairs(rows) do
                    local pad = string.rep(" ", w - #row.pattern + 1)
                    ExMsg.echo(("    %s%s%s"):format(row.pattern, pad, row.text))
                end
            end
        end
    end

    return true
end

-- Public helper: return augroup name ("" for default) given its numeric id; nil if not found.
function Autocmd.GetAugroupName(id)
    if type(id) ~= "number" then return nil end
    for name, gid in pairs(autocmdgroups) do
        if gid == id then return name end
    end
    if id == 1 then return "" end -- default unnamed group
    return nil
end

function Autocmd.GetAutocommands(opts)
    opts = opts or {}

    local group_filter = nil
    if opts.group ~= nil then
        group_filter = augroup_as_integer(opts.group)
        if not group_filter then
            return {}
        end
    end

    local events = opts.event or opts.events
    if type(events) == "string" then
        events = { events }
    end
    local evset = nil
    if type(events) == "table" and #events > 0 then
        evset = {}
        for _, ev in ipairs(events) do
            evset[Autocmd.NormalizeEvent(ev)] = true
        end
    end

    local patterns = opts.pattern
    if type(patterns) == "string" then
        patterns = { patterns }
    end
    local pset, anypat = nil, false
    if type(patterns) == "table" and #patterns > 0 then
        pset = {}
        for _, p in ipairs(patterns) do
            local np = normalize_pattern(p)
            if np == "*" then
                anypat = true
            end
            pset[np] = true
        end
    end

    local buffer_pattern = nil
    if opts.buffer ~= nil then
        local bufnr = opts.buffer
        if bufnr == 0 then
            bufnr = windows[curwin].buffer.bufnr
        end
        buffer_pattern = ("<buffer=%d>"):format(bufnr)
    end

    local out = {}
    for gid, list in pairs(autocommands_by_group) do
        if (not group_filter) or gid == group_filter then
            for _, ac in ipairs(list or {}) do
                local matched_events = {}
                for ev, _ in pairs(ac.event) do
                    if not evset or evset[ev] then
                        matched_events[#matched_events + 1] = ev
                    end
                end

                if #matched_events > 0 then
                    local matched_patterns = {}
                    for pat, _ in pairs(ac.pattern) do
                        local match = true
                        if buffer_pattern ~= nil then
                            match = (pat == buffer_pattern)
                        end
                        if match and pset then
                            match = anypat or pset[pat] == true
                        end
                        if match then
                            matched_patterns[#matched_patterns + 1] = pat
                        end
                    end

                    for _, ev in ipairs(matched_events) do
                        for _, pat in ipairs(matched_patterns) do
                            out[#out + 1] = {
                                id = ac.id,
                                group = ac.group,
                                event = ev,
                                pattern = pat,
                                command = ac.command,
                                desc = ac.desc,
                                once = ac.once,
                            }
                        end
                    end
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.id == b.id then
            if a.event == b.event then
                return tostring(a.pattern) < tostring(b.pattern)
            end
            return tostring(a.event) < tostring(b.event)
        end
        return a.id < b.id
    end)
    return out
end

-- Delete by id wrapper (mirrors DeleteAugroup by name)
-- Returns: ok:boolean, err:Error|nil, warn:string|nil
function Autocmd.DeleteAugroupById(id)
    local name = Autocmd.GetAugroupName(id)
    if not name then
        return false, Error(367, tostring(id))
    end
    if name == "" then
        -- unnamed group cannot be explicitly deleted (matches Vim behavior of not having a name)
        return false, Error(936)
    end
    return Autocmd.DeleteAugroup(name)
end

return Autocmd
