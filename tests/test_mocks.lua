-- vim/tests/test_mocks.lua
-- Simple mock environment setup for running editor outside ComputerCraft

local MockEnv = {}

local function make_default_colors()
    local order = {
        "white", "orange", "magenta", "lightBlue",
        "yellow", "lime", "pink", "gray",
        "lightGray", "cyan", "purple", "blue",
        "brown", "green", "red", "black",
    }
    local t = {}
    local map = {}
    for i = 1, #order do
        local bit = 2 ^ (i - 1)
        t[order[i]] = bit
        map[bit] = string.format("%x", i - 1)
    end

    function t.toBlit(bit)
        return map[bit] or "0"
    end

    function t.packRGB(r, g, b)
        return { r, g, b }
    end

    function t.unpackRGB(rgb)
        if type(rgb) == "table" then
            return rgb[1] or 0, rgb[2] or 0, rgb[3] or 0
        end
        return 0, 0, 0
    end

    return t
end

local function make_default_keys()
    local next_code = 1
    return setmetatable({}, {
        __index = function(t, k)
            local value = rawget(t, k)
            if value == nil then
                value = next_code
                next_code = next_code + 1
                rawset(t, k, value)
            end
            return value
        end,
    })
end

---Setup basic mock environment
---@param config? table Optional configuration for custom globals
---@return table mock Helper object with metatable interfaces
function MockEnv.setup(config)
    config = config or {}
    
    -- Logging
    _G.LOG_DEBUG = function(...) end
    _G.LOG_ERROR = function(...) end
    _G.LOG_INTERNAL = function(...) end
    
    -- Editor state
    _G.need_redraw = false
    _G.what_redraw = {}
    _G.lazyredraw_block = 0
    _G.lazyredraw_force = false
    _G.registers = {}
    _G.keys = config.keys or make_default_keys()


    local function infer_ccvim_path()
        -- level 3 = caller of Setup (level1=infer,2=setup,3=invoker)
        local info = debug.getinfo(3, "S")
        if info and type(info.source) == "string" then
            local src = info.source
            if src:sub(1,1) == "@" then
                src = src:sub(2)
            end
            local dir = src:match("(.*/)")
            if dir then
                local up1 = dir:gsub("/$", ""):match("(.*/)")
                if up1 then
                    local up2 = up1:gsub("/$", ""):match("(.*/)")
                    if up2 then
                        return up2:gsub("/$", "")
                    end
                    return up1:gsub("/$", "")
                end
                return dir:gsub("/$", "")
            end
        end
        error("Failed to infer ccvim directory!")
    end

    local inferred_ccvim_path = infer_ccvim_path()
    _G.ccvim_path = config.ccvim_path or inferred_ccvim_path
    
    -- bit32 compatibility
    _G.bit32 = _G.bit32 or {
        band = function(a, b) return (a & b) end,
        bor = function(a, b) return (a | b) end,
        bxor = function(a, b) return (a ~ b) end,
        bnot = function(a) return ~a end,
        lshift = function(a, b) return (a << b) end,
        rshift = function(a, b) return (a >> b) end,
    }
    
    -- Editor objects
    _G.buffers = config.buffers or {}
    _G.windows = config.windows or {}
    _G.tabpages = config.tabpages or { { opts = {}, tabnr = 1, windows = {} } }
    _G.curtp = config.curtp or 1
    _G.curwin = config.curwin or 1
    _G.vimmode = config.vimmode or "normal"
    
    -- ComputerCraft fs API
    _G.fs = config.fs or {
        exists = function() return false end,
        isDir = function() return false end,
        list = function() return {} end,
        open = function() return nil end,
        isReadOnly = function() return false end,
        getSize = function() return 0 end,
    }
    
    -- ComputerCraft colors API
    _G.colors = config.colors or make_default_colors()
    
    -- ComputerCraft term API
    _G.term = config.term or {
        getPaletteColor = function() return 0, 0, 0 end,
        setTextColor = function() end,
        setBackgroundColor = function() end,
    }
    _G.term.getSize = _G.term.getSize or function() return 80, 24 end
    
    -- ComputerCraft shell API
    _G.shell = config.shell or {
        dir = function() return "/" end,
    }

    local screen_w, screen_h = _G.term.getSize()
    _G.screen = config.screen or { width = screen_w or 80, height = screen_h or 24 }
    if config._V ~= nil then
        _G._V = config._V
    end

    local next_timer_id = 0
    _G.os = config.os or _G.os or os or {}
    _G.os.epoch = _G.os.epoch or function()
        local sec = (_G.os.time and _G.os.time()) or 0
        return math.floor(sec * 1000)
    end
    _G.os.startTimer = _G.os.startTimer or function()
        next_timer_id = next_timer_id + 1
        return next_timer_id
    end
    _G.os.cancelTimer = _G.os.cancelTimer or function() end
    _G.os.pullEvent = _G.os.pullEvent or function()
        return "terminate"
    end
    _G.os.queueEvent = _G.os.queueEvent or function() end
    
    -- Module loader
    local MODULE_CACHE = {}
    local module_stubs = config.module_stubs or {}

    local sign_stub = module_stubs["lib.sign"]
    if type(sign_stub) == "table" then
        sign_stub.on_lines_changed = sign_stub.on_lines_changed or function() end
        sign_stub.getplaced = sign_stub.getplaced or function() return {} end
        sign_stub.jump = sign_stub.jump or function() return -1 end
    end

    local module_roots = {}
    local function add_module_root(root)
        if type(root) ~= "string" or root == "" then
            return
        end
        for i = 1, #module_roots do
            if module_roots[i] == root then
                return
            end
        end
        module_roots[#module_roots + 1] = root
    end

    add_module_root(config.module_root)
    add_module_root(_G.ccvim_path)
    add_module_root(inferred_ccvim_path)
    if type(_G.ccvim_path) == "string" and _G.ccvim_path:sub(1, 1) == "/" then
        add_module_root(_G.ccvim_path:sub(2))
    end
    if type(inferred_ccvim_path) == "string" and inferred_ccvim_path:sub(1, 1) == "/" then
        add_module_root(inferred_ccvim_path:sub(2))
    end
    
    function _G.loadModule(name)
        if MODULE_CACHE[name] then
            return MODULE_CACHE[name]
        end
        
        -- Check if there's a stub for this module
        local stub = module_stubs[name]
        if stub then
            MODULE_CACHE[name] = stub
            return stub
        end

        local path = name:gsub("%.", "/") .. ".lua"
        local env = setmetatable({
            loadModule = _G.loadModule,
        }, { __index = _G })

        local last_err
        for i = 1, #module_roots do
            local chunk, err = loadfile(module_roots[i] .. "/" .. path, "t", env)
            if chunk then
                local mod = chunk()
                MODULE_CACHE[name] = mod
                return mod
            end
            last_err = err
        end
        error(("loadModule failed for %s (%s)"):format(name, tostring(last_err)))
    end

    _G.options = config.options or _G.options or _G.loadModule("lib.options")
    
    -- Return helper object with metatable interfaces
    local mock = {
        MODULE_CACHE = MODULE_CACHE,
    }
    
    -- Metatable interface for buffers
    mock.buffers = setmetatable({}, {
        __newindex = function(_, bufnr, buf)
            _G.buffers[bufnr] = buf
        end,
        __index = function(_, bufnr)
            return _G.buffers[bufnr]
        end,
    })
    
    -- Metatable interface for windows
    mock.windows = setmetatable({}, {
        __newindex = function(_, winnr, win)
            _G.windows[winnr] = win
        end,
        __index = function(_, winnr)
            return _G.windows[winnr]
        end,
    })
    
    -- Metatable interface for tabpages
    mock.tabpages = setmetatable({}, {
        __newindex = function(_, tabnr, tab)
            _G.tabpages[tabnr] = tab
        end,
        __index = function(_, tabnr)
            return _G.tabpages[tabnr]
        end,
    })
    
    -- Helper to create a buffer
    function mock.create_buffer(bufnr, name, lines, opts)
        local Utf8 = loadModule("lib.utf8")
        local loaded = true
        if opts and opts.loaded ~= nil then
            loaded = not not opts.loaded
        end
        local buf = {
            bufnr = bufnr,
            name = name or ("/tmp/buffer" .. bufnr),
            lines = lines or { "" },
            opts = opts or {},
            loaded = loaded,
        }
        buf.is_loaded = function(self)
            return self.loaded == true
        end
        buf.ensure_loaded = function(self, read_contents)
            if self.loaded == true then
                return true
            end
            if type(self.Load) == "function" then
                self:Load(read_contents ~= false)
            end
            self.loaded = true
            if type(self.lines) ~= "table" then
                self.lines = { "" }
            elseif #self.lines == 0 then
                self.lines = { "" }
            end
            return true
        end
        buf.line_count = function(self, load_if_unloaded)
            if load_if_unloaded then
                self:ensure_loaded(true)
            end
            if self.loaded ~= true then
                return 0
            end
            return #(self.lines or {})
        end
        buf.lines_ref = function(self, load_if_unloaded)
            if load_if_unloaded then
                self:ensure_loaded(true)
            end
            self.lines = self.lines or {}
            return self.lines
        end
        buf.get_line = function(self, line_nr, load_if_unloaded)
            local lns = self:lines_ref(load_if_unloaded)
            return lns[line_nr]
        end
        buf.str_len = function(self, s)
            return Utf8.len(s or "")
        end
        buf.str_sub = function(self, s, start_col1, end_col1)
            return Utf8.sub(s or "", start_col1, end_col1)
        end
        buf.str_char_at = function(self, s, col1)
            return Utf8.char_at(s or "", col1)
        end
        buf.str_codepoint_at = function(self, s, col1)
            return Utf8.codepoint_at(s or "", col1)
        end
        buf.str_byte_index = function(self, s, col1, allow_eol)
            return Utf8.byte_index(s or "", col1, allow_eol)
        end
        buf.str_col_from_byte = function(self, s, byte_idx, allow_eol)
            return Utf8.col_from_byte(s or "", byte_idx, allow_eol)
        end
        buf.str_each_codepoint = function(self, s, visitor)
            return Utf8.each_codepoint(s or "", visitor)
        end
        buf.line_len = function(self, line_nr, load_if_unloaded)
            local line = self:get_line(line_nr, load_if_unloaded) or ""
            return Utf8.len(line)
        end
        buf.line_sub = function(self, line_nr, start_col1, end_col1, load_if_unloaded)
            local line = self:get_line(line_nr, load_if_unloaded) or ""
            return Utf8.sub(line, start_col1, end_col1)
        end
        buf.line_char_at = function(self, line_nr, col1, load_if_unloaded)
            local line = self:get_line(line_nr, load_if_unloaded) or ""
            return Utf8.char_at(line, col1)
        end
        buf.line_codepoint_at = function(self, line_nr, col1, load_if_unloaded)
            local line = self:get_line(line_nr, load_if_unloaded) or ""
            return Utf8.codepoint_at(line, col1)
        end
        buf.line_byte_index = function(self, line_nr, col1, load_if_unloaded, allow_eol)
            local line = self:get_line(line_nr, load_if_unloaded) or ""
            return Utf8.byte_index(line, col1, allow_eol)
        end
        _G.buffers[bufnr] = buf
        return buf
    end
    
    -- Helper to create a window
    function mock.create_window(winnr, buffer, opts)
        local win = {
            winnr = winnr,
            buffer = buffer,
            opts = opts or {},
        }
        _G.windows[winnr] = win
        return win
    end
    
    -- Helper to create a tabpage
    function mock.create_tabpage(tabnr, windows, opts)
        local tab = {
            tabnr = tabnr,
            windows = windows or {},
            opts = opts or {},
        }
        _G.tabpages[tabnr] = tab
        return tab
    end
    
    -- Direct access to globals
    mock.loadModule = _G.loadModule
    
    return mock
end

return MockEnv
