local ccvim_path

do
    local source
    if debug and debug.getinfo then
        local info = debug.getinfo(1, "S")
        source = info and info.source
    end

    local function dirname(path)
        if not path then return "." end
        local dir = path:match("(.*/)")
        if dir then
            dir = dir:gsub("/+$", "")
            if dir == "" then return "/" end
            return dir
        end
        return "."
    end

    if source and source:sub(1,1) == "@" then
        ccvim_path = dirname(source:sub(2))
    else
        local prog = arg and arg[0]
        if prog and prog ~= "" then
            ccvim_path = dirname(prog)
        else
            ccvim_path = "."
        end
    end
end

if not ccvim_path then
    print("Error: Failed to determine program path!")
    return
end

if not os.epoch then
    os.epoch = function(_)
        return math.floor(os.time() * 1000)
    end
end

if not loadstring then
    loadstring = function(str, chunkname)
        return load(str, chunkname)
    end
end

if not bit32 then
    local ok_bit32, compat = pcall(require, "bit32")
    if not ok_bit32 then
        local ok_bit, bit = pcall(require, "bit")
        if ok_bit and bit then
            compat = {
                band = bit.band,
                bor = bit.bor,
                bxor = bit.bxor,
                bnot = bit.bnot,
                lshift = bit.lshift,
                rshift = bit.rshift,
                arshift = bit.arshift or bit.rshift,
            }
        else
            local MOD = 4294967296
            local floor = math.floor

            local function to_u32(n)
                n = tonumber(n) or 0
                n = n % MOD
                if n < 0 then
                    n = n + MOD
                end
                return n
            end

            local function band2(a, b)
                a = to_u32(a)
                b = to_u32(b)
                local res = 0
                local bitv = 1
                for _ = 1, 32 do
                    local abit = a % 2
                    local bbit = b % 2
                    if abit == 1 and bbit == 1 then
                        res = res + bitv
                    end
                    a = floor(a / 2)
                    b = floor(b / 2)
                    bitv = bitv * 2
                end
                return res
            end

            local function bor2(a, b)
                a = to_u32(a)
                b = to_u32(b)
                local res = 0
                local bitv = 1
                for _ = 1, 32 do
                    local abit = a % 2
                    local bbit = b % 2
                    if abit == 1 or bbit == 1 then
                        res = res + bitv
                    end
                    a = floor(a / 2)
                    b = floor(b / 2)
                    bitv = bitv * 2
                end
                return res
            end

            local function bxor2(a, b)
                a = to_u32(a)
                b = to_u32(b)
                local res = 0
                local bitv = 1
                for _ = 1, 32 do
                    local abit = a % 2
                    local bbit = b % 2
                    if abit ~= bbit then
                        res = res + bitv
                    end
                    a = floor(a / 2)
                    b = floor(b / 2)
                    bitv = bitv * 2
                end
                return res
            end

            local function fold_binary(op, a, b, ...)
                local res = op(a, b)
                for i = 1, select("#", ...) do
                    res = op(res, select(i, ...))
                end
                return res
            end

            compat = {
                band = function(a, b, ...)
                    if b == nil then
                        return to_u32(a)
                    end
                    return fold_binary(band2, a, b, ...)
                end,
                bor = function(a, b, ...)
                    if b == nil then
                        return to_u32(a)
                    end
                    return fold_binary(bor2, a, b, ...)
                end,
                bxor = function(a, b, ...)
                    if b == nil then
                        return to_u32(a)
                    end
                    return fold_binary(bxor2, a, b, ...)
                end,
                bnot = function(a)
                    return MOD - 1 - to_u32(a)
                end,
                lshift = function(a, n)
                    a = to_u32(a)
                    n = tonumber(n) or 0
                    if n <= 0 then
                        return a
                    end
                    if n >= 32 then
                        return 0
                    end
                    return (a * (2 ^ n)) % MOD
                end,
                rshift = function(a, n)
                    a = to_u32(a)
                    n = tonumber(n) or 0
                    if n <= 0 then
                        return a
                    end
                    if n >= 32 then
                        return 0
                    end
                    return floor(a / (2 ^ n))
                end,
                arshift = function(a, n)
                    a = to_u32(a)
                    n = tonumber(n) or 0
                    if n <= 0 then
                        return a
                    end
                    if n >= 32 then
                        return a >= 2147483648 and (MOD - 1) or 0
                    end
                    local shifted = floor(a / (2 ^ n))
                    if a < 2147483648 then
                        return shifted
                    end
                    local fill = 0
                    local bitv = 2147483648
                    for _ = 1, n do
                        fill = fill + bitv
                        bitv = bitv / 2
                    end
                    return shifted + fill
                end,
            }
        end
    end
    bit32 = compat
end

if not textutils then
    textutils = { serialize = tostring }
end

local function load_local_chunk(path)
    local chunk, err = loadfile(path, "t", _ENV)
    if not chunk and setfenv then
        chunk, err = loadfile(path)
        if chunk then
            setfenv(chunk, _ENV)
        end
    end
    if not chunk then
        error(err)
    end
    return chunk
end

local _is_cc = (type(term) == "table" and term.getSize ~= nil)
local _backend = load_local_chunk(ccvim_path .. "/lib/backend/" .. (_is_cc and "cc" or "native") .. ".lua")()
if not fs then
    fs = _backend.fs
end

local function log(level, format, ...)
    local handle = fs.open(ccvim_path .. "/logfile.txt", "a")
    handle.write("[" .. os.date() .. "] " .. (level and ("(" .. level .. ") ") or "") .. (
        type(format) == "string" and format:format(...) or textutils.serialize(format)
    ) .. "\n")
    handle.close()
end

math.clamp = function(value, min_value, max_value) -- luacheck: ignore 122
    if value < min_value then
        return min_value
    end
    if value > max_value then
        return max_value
    end
    return value
end

local _V = {
    vimversion_maj = 0,
    vimversion_min = 11,
    vimversion_pat = 3,

    vimcompat_maj = 8,
    vimcompat_min = 1,

    loaded_modules = {},
    state = {},
    __ccvim_input_state = {
        feedkeys_typeahead_depth = 0,
    },

    curtp = 1,
    tabpages = { {
        -- Enough of a tabpage for options to function during initialization
        opts = {},
        updateFrameview = function() end
    } },
    curwin = 1,
    windows = {}, -- keep track of all the windows by index for more efficient access
    buffers = {},

    vimmode = "normal",

    need_redraw = true,
    what_redraw = {},
    lazyredraw_block = 0,
    lazyredraw_force = false,

    registers = {},

    global_marks = {},

    startuptime = false,
    no_cache = false,

    ccvim_path = ccvim_path,
    ccvimversion_str = "0.9",

    -- error = function(...)
    --     log("DEBUG", "Error thrown:\n%s", debug.traceback())
    --     log("DEBUG", ...)
    --     error(...)
    -- end
}
_V.vimversion_str = _V.vimversion_maj .. "." .. _V.vimversion_min .. "." .. _V.vimversion_pat
_V.LOG_DEBUG = function(format, ...) log("DEBUG", format, ...) end
_V.LOG_ERROR = function(format, ...) log("ERROR", format, ...) end

local function loadModule(module, opts)
    opts = opts or {}

    local cached = _V.loaded_modules[module]
    if cached ~= nil then
        if type(cached) == "table" and rawget(cached, "__ccvim_lazy_proxy") then
            if opts.immediate then
                return cached.__ccvim_materialize()
            end
        end
        return cached
    end

    local module_path = ccvim_path .. "/" .. module:gsub("%.", "/") .. ".lua"

    setmetatable(_V, {
        __index = function(_tbl, key)
            if _G[key] then
                return _G[key]
            else
                return _ENV[key]
            end
        end
    })

    local loaded, error = loadfile(module_path, "t", _V)
    if loaded then
        local resolved = false
        local mod

        local function materialize()
            if not resolved then
                mod = loaded()
                if mod == nil then
                    mod = true
                end
                resolved = true
                _V.loaded_modules[module] = mod
            end
            return mod
        end

        if opts.immediate then
            return materialize()
        end

        local proxy = {
            __ccvim_lazy_proxy = true,
            __ccvim_materialize = materialize,
        }
        setmetatable(proxy, {
            __index = function(_, key)
                return materialize()[key]
            end,
            __newindex = function(_, key, value)
                materialize()[key] = value
            end,
            __call = function(_, ...)
                return materialize()(...)
            end,
            __len = function()
                return #materialize()
            end,
            __pairs = function()
                return pairs(materialize())
            end,
            __tostring = function()
                return tostring(materialize())
            end,
        })
        _V.loaded_modules[module] = proxy
        return proxy
    else
        _V.LOG_DEBUG("loadModule(%s) failed, error: %s", module, error)
    end
    return false
end
_V.loadModule = loadModule
if _backend.on_load_module_ready then
    _backend.on_load_module_ready(_V)
end

local Screen = loadModule("lib.screen", { immediate = true })
Screen.init(_backend)
_V.screen = Screen
_V.keys = _backend.keys
_V.fs = _backend.fs
_V.backend = _backend

local w, h = Screen.get_size()
_V.screen_size = {
    width = w,
    height = h,
}

-- Populate v:version for Vimscript compatibility (major*100 + minor).
-- Use a Vim-compatible value, not the NVIM version tuple, so runtime scripts
-- that gate on Vim version (eg netrw) behave predictably.
local Scopes = loadModule("lib.luaapi.scopes")
local original_palette = _backend.capture_palette()
Scopes._v.version = (_V.vimcompat_maj * 100) + _V.vimcompat_min
Scopes._v.vim_did_init = 0
local Error = loadModule("lib.error")
local ScriptSource

local VimFs = loadModule("lib.luaapi.fs")

_V.LOG_INTERNAL_ENABLE = {
    autocmd = false,
    syntax = false,
    excmd_call = false,
    excmd_internal_parse = false,
    unimplemented = false,
    ignored = false,
    pcall = false,
    frametree = false,
    has = false,
    missing = false,
}
_V.LOG_INTERNAL = function(sector, format, ...)
    if _V.LOG_INTERNAL_ENABLE[sector:lower()] then
        if type(format) == "function" then
            format = format()
        end

        log("internal." .. sector, format, ...)
    end
end

local startupstart = os.epoch("utc")
local startuptime_buf = {}
function _V.writestartup(message, exttime)
    local mytime = os.epoch("utc")
    local formatted_elapsedtime = string.format("%06.3f", mytime - startupstart)
    startuptime_buf[#startuptime_buf+1] = ("%s%s: %s"):format(
        formatted_elapsedtime,
        (exttime and ("  " .. string.format("%06.3f", os.epoch("utc") - exttime)) or ""),
        message
    )
end

_V.writestartup("--- NVIM STARTING ---")

Tabpage = loadModule("layout.tabpage")
local FrameTree = loadModule("lib.frame")
_V.options = loadModule("lib.options")
_V.options.set("lines", h)
_V.options.set("columns", w)

local Event = loadModule("lib.event")
Event.LoadCommandModule()
loadModule("lib.mappings", { immediate = true })

local AutoCmd = loadModule("lib.autocmd")
local PopupMenu = loadModule("lib.popupmenu")
local Visual = loadModule("lib.visual")
_V.apply_terminal_resize = FrameTree.ApplyTerminalResize

local function leave_insert_cursor(win)
    local start = win.insert_curs_start
    if not start then
        return
    end
    if win.cursory < start[2] or (win.cursory == start[2] and win.cursorx <= start[1]) then
        return
    end
    if win.cursorx > 1 then
        win:cursorMove(-1, 0)
    else
        local previous_line = win.cursory - 1
        win:cursorSet(win.buffer:line_len(previous_line, true), previous_line)
    end
end

function _V.setMode(newmode, newx, newy)
    local oldmode = _V.vimmode
    local win = _V.windows[_V.curwin]
    local mode_changed = (newmode ~= oldmode)
    local buf_ctx = {
        bufnr = win.buffer.bufnr,
        bufname = win.buffer.name,
    }

    if mode_changed and oldmode == "insert" and newmode ~= "insert" then
        Visual.complete_block_change(win)
        win.buffer:undo_end(win)
        AutoCmd.Run("InsertLeavePre", buf_ctx)
    end

    local old_select = oldmode == "visual" or oldmode == "select"
    local new_select = newmode == "visual" or newmode == "select"
    if mode_changed and old_select and not new_select and win.visual_anchor then
        Visual.finish(win)
    end

    _V.vimmode = newmode
    if mode_changed and oldmode == "insert" and newmode ~= "insert" then
        leave_insert_cursor(win)
    end
    if newy then
        win:cursorSetY(newy)
    end
    if newx then
        win:cursorSetX(newx)
    end
    if newmode == "insert" then
        local buf = win.buffer
        local lines = buf:lines_ref(true)
        if #lines == 0 then
            lines[1] = ""
        end
    end
    if mode_changed then
        if oldmode == "insert" and newmode ~= "insert" then
            if PopupMenu.visible() then
                PopupMenu.close("cancel")
            end
            AutoCmd.Run("InsertLeave", buf_ctx)
        elseif oldmode ~= "insert" and newmode == "insert" then
            AutoCmd.Run("InsertEnter", buf_ctx)
        end

        if oldmode == "cmdline" and newmode ~= "cmdline" then
            AutoCmd.Run("CmdlineLeave", buf_ctx)
        elseif oldmode ~= "cmdline" and newmode == "cmdline" then
            AutoCmd.Run("CmdlineEnter", buf_ctx)
        end

        AutoCmd.Run("ModeChanged", { old_mode = oldmode, new_mode = newmode })
    end
    _V.what_redraw["commandline"] = true
    win:cursorMove(0, 0, false)
    if newmode == "insert" then
        win.insert_curs_start = {win.cursorx, win.cursory}
        if mode_changed and oldmode ~= "insert" then
            win.buffer:undo_begin(win)
        end
    end
    _V.need_redraw = true
end

local function _find_external_caller()
    if not (debug and debug.getinfo) then return nil end
    local lvl = 2                          -- 1 = this function, 2 = direct caller
    while true do
        local info = debug.getinfo(lvl, "nSl") -- name/namewhat, source, currentline
        if not info then return nil end
        lvl = lvl + 1
    end
end

local function _fmt_caller(info)
    if not info then return "unknown caller" end
    local src = info.source or info.short_src or "?"
    if src:sub(1, 1) == "@" then src = src:sub(2) end -- strip leading '@'
    local who = info.name or (info.what == "main" and "<main chunk>" or "<anonymous>")
    local kind = (info.namewhat and info.namewhat ~= "" and info.namewhat) or info.what or "function"
    return string.format("%s %s at %s:%d", kind, who, src, info.currentline or -1)
end

function _V._log_caller(where)
    local info = _find_external_caller()
    _V.LOG_DEBUG(string.format("[%s] called by %s", where, _fmt_caller(info)))
    _V.LOG_DEBUG(debug.traceback("stack:", 2))
end

local function _source_runtime_startup(path)
    local ok, err = ScriptSource.source_runtime(path)
    if ok then
        return true
    end

    local msg = Error.IsError(err) and err:toString() or tostring(err)
    _V.LOG_DEBUG("startup source_runtime failed path=%s err=%s", tostring(path), tostring(msg))

    return false
end

function _V.enterWindow(winnr)
    if winnr == _V.curwin then
        return
    end

    local new_curwin, new_curtp

    new_curwin = winnr

    if _V.windows[winnr].tabpagenr ~= _V.curtp then
        new_curtp = _V.windows[winnr].tabpagenr
    end

    local oldbuf = _V.windows[_V.curwin].buffer
    local newbuf = _V.windows[new_curwin].buffer
    local buf_changed = oldbuf ~= newbuf

    if buf_changed then
        AutoCmd.Run("BufLeave", { bufnr = oldbuf.bufnr, bufname = oldbuf.name })
    end

    AutoCmd.Run("WinLeave")

    if new_curtp then
        AutoCmd.Run("TabLeave")
    end

    _V.curwin = new_curwin
    if new_curtp then
        _V.curtp = new_curtp
    end

    AutoCmd.Run("WinEnter")

    if new_curtp then
        AutoCmd.Run("TabEnter")
    end

    if buf_changed then
        AutoCmd.Run("BufEnter", { bufnr = newbuf.bufnr, bufname = newbuf.name })
    end

    FrameTree.RebalanceCurrentTab()
end

_V.writestartup("parsing arguments")
local Args = loadModule("lib.args")
if not Args.parse(arg) then
    return
end

-- Enable ftplugin and indent
ScriptSource = loadModule("lib.scriptsource")
_source_runtime_startup("ftplugin.vim")
_source_runtime_startup("indent.vim")
_source_runtime_startup("lua/vim/_defaults.lua")

_V.writestartup("sourcing vimrc file(s)")
local srcok, srcerr = ScriptSource.source(ccvim_path .. "/config/init.lua")
if not srcok then
    local cause
    if Error.IsError(srcerr) then
        cause = srcerr:toString()
    else
        cause = tostring(srcerr)
    end
    _V.LOG_DEBUG("Failed to source init file! Reason: %s", cause)
end

-- Run filetype.lua and syntax.vim
-- TODO: these are skipped if `:filetype off` or `:syntax off` were called during init
_source_runtime_startup("filetype.lua")
_source_runtime_startup("syntax/syntax.vim")

Scopes._v.vim_did_init = 1

-- Load plugin scripts (runtimepath + packages) if enabled
if _V.options.get("loadplugins") then
    local Filesystem = loadModule("lib.filesystem")
    local RuntimePath = loadModule("lib.runtimepath")
    local Pack = loadModule("lib.pack")

    local rtp = RuntimePath.get_list()

    local non_after, after = {}, {}
    local patterns = { "plugin/**/*.vim", "plugin/**/*.lua" }
    for _, base in ipairs(rtp) do
        local target = RuntimePath.is_after(base) and after or non_after
        for _, pattern in ipairs(patterns) do
            local matches = Filesystem.ExpandWildcards(base .. "/" .. pattern)
            for _, m in ipairs(matches) do
                if not fs.isDir(m) then
                    target[#target + 1] = m
                end
            end
        end
    end

    local ok, err
    for _, path in ipairs(non_after) do
        ok, err = ScriptSource.source(path)
        if not ok then
            break
        end
    end
    if not ok and err and err.toString then
        _V.LOG_DEBUG("runtime! plugin/**/*.vim failed: %s", err:toString())
    end

    ok, err = Pack.load_start()
    if not ok and err and err.toString then
        _V.LOG_DEBUG("loading start packages failed: %s", err:toString())
    end

    for _, path in ipairs(after) do
        ok, err = ScriptSource.source(path)
        if not ok then
            break
        end
    end
    if not ok and err and err.toString then
        _V.LOG_DEBUG("runtime! after/plugin failed: %s", err:toString())
    end
end

_V.writestartup("loading argument files")
Args.load_pending_files()

Scopes._v.vim_did_enter = 1
AutoCmd.Run("VimEnter")
AutoCmd.Run("UIEnter", { data = { chan = 1 } })

if _V.startuptime then
    local file = fs.open(VimFs.abspath(_V.startuptime), "a")
    for i = 1, #startuptime_buf do
        file.write(startuptime_buf[i] .. "\n")
    end
    file.close()
end

-- Run the main loop

local ok, err = xpcall(Event.RunLoop, function(e)
    return debug.traceback("A critical internal error occurred:\n" .. tostring(e), 2)
end)

_backend.reset(original_palette)

if not ok then
    _V.LOG_DEBUG(err)
    print("An internal error occurred! Check the log for more information.")
end
