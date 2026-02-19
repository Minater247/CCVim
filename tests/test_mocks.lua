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
    _G.registers = {}
    _G.keys = config.keys or make_default_keys()
    _G.ccvim_path = config.ccvim_path or "."
    
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
    
    -- ComputerCraft shell API
    _G.shell = config.shell or {
        dir = function() return "/" end,
    }
    
    -- Module loader
    local MODULE_CACHE = {}
    local module_stubs = config.module_stubs or {}
    
    function _G.loadModule(name)
        if MODULE_CACHE[name] then
            return MODULE_CACHE[name]
        end
        
        -- Check if there's a stub for this module
        if module_stubs[name] then
            local stub = module_stubs[name]
            MODULE_CACHE[name] = stub
            return stub
        end

        local path = name:gsub("%.", "/") .. ".lua"
        local env = setmetatable({
            _V = nil,
            loadModule = _G.loadModule,
        }, { __index = _G })

        local chunk, err = loadfile(path, "t", env)
        if not chunk then
            error(("loadModule failed for %s (%s)"):format(name, tostring(err)))
        end
        local mod = chunk()
        MODULE_CACHE[name] = mod
        return mod
    end
    
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
