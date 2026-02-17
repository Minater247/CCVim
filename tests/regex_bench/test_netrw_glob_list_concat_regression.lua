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
    ["/vim"] = { ".gitignore", "README.md", "lua" },
    ["/vim/lua"] = { "init.lua" },
}

local files = {
    ["/vim/.gitignore"] = true,
    ["/vim/README.md"] = true,
    ["/vim/lua/init.lua"] = true,
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
        local entries = dirs[path]
        if not entries then return {} end
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
        ["vim.lib.autocmd"] = {
            Run = function() return 0 end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
local Compiler = mock.loadModule("vim.lib.excmd.compiler")
local Runtime = mock.loadModule("vim.lib.excmd.runtime")
local Scopes = mock.loadModule("vim.lib.luaapi.scopes")

local function run(script)
    local durable = { s = {}, funcs = {}, g = Scopes._g, script_ctx = "/tmp/netrw_glob_concat_regression.vim" }
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

    return durable.g
end

local g = run([[
let g:filelist = glob('*', 0, 1, 1)
let g:nomatch  = glob('ZZZ_NO_MATCH_*', 0, 1, 1)
let g:combo1   = g:filelist + g:nomatch
let g:combo2   = g:nomatch + g:filelist
let g:combo3   = g:nomatch + g:nomatch
]])

assert_eq("glob no-match is empty list", #g.nomatch, 0)
assert_eq("list + empty preserves len", #g.combo1, #g.filelist)
assert_eq("empty + list preserves len", #g.combo2, #g.filelist)
assert_eq("empty + empty is empty", #g.combo3, 0)

for i = 1, #g.filelist do
    assert_eq(("combo1[%d]"):format(i), g.combo1[i], g.filelist[i])
    assert_eq(("combo2[%d]"):format(i), g.combo2[i], g.filelist[i])
end

print("netrw glob list concat regression test: OK")
