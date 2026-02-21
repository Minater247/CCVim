local MockEnv = require("vim.tests.test_mocks")

local function norm(path)
    path = tostring(path or ""):gsub("//+", "/")
    if path == "" then
        return "/"
    end
    if #path > 1 and path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    return path
end

local tags_lines = {
    "copy()\tvimfn.txt\t/*copy()*",
}

local vimfn_text = table.concat({
    "header",
    "*copy()*",
    "body",
}, "\n")

local fs_stub = {
    exists = function(path)
        path = norm(path)
        return path == "/vim/runtime/doc/tags" or path == "/vim/runtime/doc/vimfn.txt"
    end,
    isDir = function(_)
        return false
    end,
    list = function(_)
        return {}
    end,
    open = function(path, mode)
        path = norm(path)
        if mode ~= "r" then
            return nil
        end
        if path == "/vim/runtime/doc/tags" then
            local i = 0
            return {
                readLine = function()
                    i = i + 1
                    return tags_lines[i]
                end,
                close = function() end,
            }
        end
        if path == "/vim/runtime/doc/vimfn.txt" then
            return {
                readAll = function()
                    return vimfn_text
                end,
                close = function() end,
            }
        end
        return nil
    end,
    isReadOnly = function(_)
        return false
    end,
    getSize = function(path)
        path = norm(path)
        if path == "/vim/runtime/doc/vimfn.txt" then
            return #vimfn_text
        end
        if path == "/vim/runtime/doc/tags" then
            return #table.concat(tags_lines, "\n")
        end
        return 0
    end,
}

local exmsg_stub = {
    messages = {},
    echo = function() end,
    echon = function() end,
    echomsg = function() end,
    echoerr = function() end,
    echohl = function() end,
    PushSilent = function() end,
    PushUnsilent = function() end,
    PopSilent = function() end,
    _writeWithHL = function() end,
    StartRedir = function() end,
    EndRedir = function() return true end,
    BeginCapture = function() return {} end,
    EndCapture = function() return "", nil end,
    PushUISuppress = function() end,
    PopUISuppress = function() end,
}

local mock = MockEnv.setup({
    ccvim_path = "/vim",
    fs = fs_stub,
    shell = { dir = function() return "/" end },
    module_stubs = {
        ["vim.lib.exmsg"] = function() return exmsg_stub end,
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
        ["vim.lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["vim.lib.key"] = { strtoseq = function() return {} end },
        ["vim.lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["vim.lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
            on_lines_changed = function() end,
        },
    },
})

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s"):format(label))
    end
end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Runtime = mock.loadModule("lib.excmd.runtime")

local help_buf = mock.create_buffer(1, "/tmp/help.txt", { "*old*" }, { buftype = "help", modified = false })
help_buf.loaded = true
help_buf.refcount = 1

local help_win = mock.create_window(1, help_buf, { tabpagenr = 1 })
help_win.tabpagenr = 1
help_win.cursorx = 1
help_win.cursory = 1
help_win.scrollx = 1
help_win.scrolly = { 1, 0 }
function help_win:cursorSet(x, y)
    self.cursorx = x or self.cursorx
    self.cursory = y or self.cursory
end
function help_win:cursorMove(dx, dy)
    self.cursorx = (self.cursorx or 1) + (dx or 0)
    self.cursory = (self.cursory or 1) + (dy or 0)
end

_G.curtp = 1
_G.curwin = 1
_G.windows = { [1] = help_win }
_G.tabpages = { { tabnr = 1, windows = { help_win }, opts = {} } }
_G.enterWindow = function(winnr)
    _G.curwin = winnr
end

local ok, err = Runtime.run("help copy()", { script_ctx = "/tmp/test_help_command_runtime.vim" })
assert_true("help command executes", ok == true)
if ok ~= true then
    error(tostring(err))
end

local buf = _G.windows[_G.curwin].buffer
assert_eq("help file opened", buf.name, "/vim/runtime/doc/vimfn.txt")
assert_eq("help filetype set", Options.get("filetype", nil, buf), "help")
assert_true("cursor moved to tag line", (buf:get_line(help_win.cursory, true) or ""):find("%*copy%(%)%*", 1) ~= nil)

print("help command tag jump/filetype test: OK")
