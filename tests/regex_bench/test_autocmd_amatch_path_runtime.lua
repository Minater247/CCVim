local MockEnv = require("vim.tests.test_mocks")

local function norm(path)
    path = tostring(path or ""):gsub("//+", "/")
    if path == "" then return "/" end
    if #path > 1 and path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end
    return path
end

local dirs = {
    ["/"] = { "vim" },
    ["/vim"] = { "tests" },
    ["/vim/tests"] = { "README.md" },
}

local files = {
    ["/vim/tests/README.md"] = true,
}

local fs_stub = {
    exists = function(path)
        path = norm(path)
        return dirs[path] ~= nil or files[path] == true
    end,
    isDir = function(path)
        path = norm(path)
        return dirs[path] ~= nil
    end,
    list = function(path)
        path = norm(path)
        local entries = dirs[path] or {}
        local out = {}
        for i = 1, #entries do out[i] = entries[i] end
        return out
    end,
    open = function(path, mode)
        path = norm(path)
        if mode == "r" and files[path] then
            return { close = function() end }
        end
        return nil
    end,
    getSize = function(path)
        path = norm(path)
        if files[path] then return 1 end
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
    fs = fs_stub,
    shell = { dir = function() return "/vim" end },
    module_stubs = {
        ["vim.lib.exmsg"] = function() return exmsg_stub end,
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
        ["vim.lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["vim.lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["vim.lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["vim.lib.syntax"] = {
            ParseLinetypes = function() end,
            OwnSyntax = function() end,
            ExecuteCommand = function() return true end,
            SyntimeReport = function() return {} end,
            SyntimeSet = function() end,
            SyntimeClear = function() end,
            MatchCommand = function() return true end,
            OnWindowBufferChanged = function() end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Autocmd = mock.loadModule("lib.autocmd")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Builtins = mock.loadModule("lib.luaapi.fn")

local buf = mock.create_buffer(1, "./tests", { "" })
local win = mock.create_window(1, buf, { tabpagenr = 1, curdir = "/vim" })
win.cursorx = 1
win.cursory = 1
win.scrolly = { 1, 0 }
win.scrollx = 0
_G.curwin = 1
_G.curtp = 1
_G.tabpages = { { tabnr = 1, windows = _G.windows, curdir = "/vim", opts = {} } }

local function run_compiled(script, script_ctx)
    local durable = Runtime.CaptureDurableScriptState({ script_ctx = script_ctx }) or { s = {}, funcs = {} }
    durable.g = durable.g or Scopes._g
    local state = Runtime.MakeRuntimeState(durable)
    state.g = durable.g
    local runtime = Runtime.new(state)

    local code, err = Compiler.compile_script(script, { state = state })
    if not code then
        error("compile failed: " .. tostring(err))
    end

    local env = setmetatable({ runtime = runtime, _G = _G }, { __index = _G })
    local chunk = assert(load(code, "compiled", "t", env))
    local fn = chunk()
    local ok, rv = pcall(fn, state, runtime)
    if not ok then
        error("runtime failed: " .. tostring(rv))
    end
end

run_compiled([[
autocmd BufEnter * let g:probe_amatch = expand('<amatch>')
autocmd FileType * let g:probe_ft_amatch = expand('<amatch>')
]], "/tmp/test_autocmd_amatch_path_runtime.vim")

Autocmd.Run("BufEnter", { bufnr = 1, bufname = "./tests" })
assert_eq("BufEnter <amatch> is absolute path", Scopes._g.probe_amatch, "/vim/tests")

Autocmd.Run("FileType", { bufnr = 1, bufname = "./tests", pattern = "lua" })
assert_eq("FileType <amatch> stays filetype", Scopes._g.probe_ft_amatch, "lua")

run_compiled([[
autocmd FileType * let g:probe_ft_doau = expand('<amatch>')
doautocmd FileType netrw
]], "/tmp/test_autocmd_amatch_path_doau_runtime.vim")
assert_eq("doautocmd FileType keeps <amatch> as filetype", Scopes._g.probe_ft_doau, "netrw")

local function netrw_file(curdir, fname)
    if tostring(fname):sub(1, 1) == "/" then
        return tostring(fname)
    end
    return Builtins.simplify(tostring(curdir) .. "/" .. tostring(fname))
end

local legacy_dir = "./tests"
local legacy_match = Builtins.glob(legacy_dir .. "/*", 0, 1, 1)[1]
assert_eq(
    "legacy relative curdir reproduces netrw path doubling",
    netrw_file(legacy_dir, legacy_match),
    "./tests/tests/README.md"
)

local fixed_dir = Scopes._g.probe_amatch
local fixed_match = Builtins.glob(fixed_dir .. "/*", 0, 1, 1)[1]
assert_eq(
    "absolute curdir avoids netrw path doubling",
    netrw_file(fixed_dir, fixed_match),
    "/vim/tests/README.md"
)

print("autocmd <amatch> path normalization test: OK")
