local MockEnv = require("vim.tests.test_mocks")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function norm(path)
    path = tostring(path or ""):gsub("//+", "/")
    if #path > 1 and path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    return path
end

local file_path = "/tmp/cli.lua"

local window_ctor = setmetatable({ _next = 1 }, {
    __call = function(self, buffer)
        local id = self._next
        self._next = id + 1
        local win = {
            winnr = id,
            buffer = buffer,
            opts = {},
            scrolly = { 1, 0 },
            scrollx = 1,
            cursorx = 1,
            cursory = 1,
        }
        windows[id] = win
        return win
    end,
})

local tab_ctor = setmetatable({ _next = 1 }, {
    __call = function(self, window)
        local id = self._next
        self._next = id + 1
        local tab = {
            tabnr = id,
            windows = {},
            tree = {},
            opts = {},
        }
        if window then
            window.tabpagenr = id
            tab.windows[1] = window
        end
        function tab:WinSplit(_, new_win)
            new_win.tabpagenr = self.tabnr
            self.windows[#self.windows + 1] = new_win
            return true
        end
        tabpages[id] = tab
        return tab
    end,
})

local mock = MockEnv.setup({
    fs = {
        exists = function(path)
            return norm(path) == file_path
        end,
        isDir = function(_)
            return false
        end,
        list = function(_)
            return {}
        end,
        open = function(path, mode)
            if mode ~= "r" or norm(path) ~= file_path then
                return nil
            end
            return {
                readAll = function()
                    return "print('ok')\n"
                end,
                close = function() end,
            }
        end,
        isReadOnly = function(_)
            return false
        end,
        getSize = function(path)
            if norm(path) == file_path then
                return 12
            end
            return 0
        end,
    },
    module_stubs = {
        ["vim.layout.window"] = window_ctor,
        ["vim.layout.tabpage"] = tab_ctor,
        ["vim.lib.frame"] = {
            Equalize = function()
                return true
            end,
        },
        ["vim.lib.sign"] = {
            on_lines_changed = function() end,
        },
    },
})

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
local Autocmd = mock.loadModule("vim.lib.autocmd")
local Args = mock.loadModule("vim.lib.args")

Autocmd.CreateAutocommand({ "BufRead" }, { "*.lua" }, function(ctx)
    local buf = buffers[ctx.bufnr]
    Options.set("filetype", "lua", nil, nil, buf)
end, nil, 1, false, false)

local ok = Args.parse({ [0] = "nvim", file_path })
assert_eq("parse ok", ok, true)

local buf = buffers[1]
assert_eq("buffer initially unloaded", buf.loaded, false)
assert_eq("filetype initially empty", Options.get("filetype", nil, buf), "")

Args.load_pending_files()

assert_eq("buffer loaded after startup load", buf.loaded, true)
assert_eq("filetype set from BufRead autocmd", Options.get("filetype", nil, buf), "lua")

print("args deferred load filetype test: OK")
