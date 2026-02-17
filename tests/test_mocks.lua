-- vim/tests/test_mocks.lua
-- Simple mock environment setup for running editor outside ComputerCraft

local MockEnv = {}

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
    _G.keys = setmetatable({}, { __index = function() return 0 end })
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
    _G.colors = config.colors or {
        white = 1,
        orange = 2,
        magenta = 4,
        lightBlue = 8,
        yellow = 16,
        lime = 32,
        pink = 64,
        gray = 128,
        lightGray = 256,
        cyan = 512,
        purple = 1024,
        blue = 2048,
        brown = 4096,
        green = 8192,
        red = 16384,
        black = 32768,
        toBlit = function() return "0" end,
        packRGB = function(r, g, b) return { r, g, b } end,
        unpackRGB = function(rgb) return rgb[1], rgb[2], rgb[3] end,
    }
    
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
        local buf = {
            bufnr = bufnr,
            name = name or ("/tmp/buffer" .. bufnr),
            lines = lines or { "" },
            opts = opts or {},
        }
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
