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
    ["/vim"] = { ".gitignore", "lua", "README.md" },
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

local function assert_list_eq(label, got, want)
    if #got ~= #want then
        error(("FAIL %s: expected length %d, got %d"):format(label, #want, #got))
    end
    for i = 1, #got do
        if got[i] ~= want[i] then
            error(("FAIL %s[%d]: expected %s, got %s"):format(label, i, tostring(want[i]), tostring(got[i])))
        end
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")

local function run(script)
    local durable = { s = {}, funcs = {}, g = Scopes._g, script_ctx = "/tmp/netrw_glob_substitute.vim" }
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
let g:g1 = glob('./*', 0, 1, 1)
let g:g2 = glob('./.*', 0, 1, 1)
let g:g3 = glob('*', 0, 1, 1)
let g:g4 = glob('.*', 0, 1, 1)
let g:simp = simplify('./*')
let g:s1 = substitute('vim/.gitignore*', "\*$", "", "")
let g:s2 = substitute('vim/.gitignore*', '\*$', "", "")
let g:s3 = substitute('/tmp/codex-netrw/a/b/', '^\(.*\)/\([^/]\+\)/$', '\1', '')
let g:s4 = substitute('/tmp/codex-netrw/a/b/', '^\(.*\)/\([^/]\+\)/$', '\2', '')
let g:s5 = substitute('ab', '\(a\)\(b\)', '\2\1', '')
let g:s6 = substitute('AB', '\(ab\)', '\1', 'i')
let g:s7 = substitute('foo', 'foo', '[\0:&:\&]', '')
let g:m1 = match('vim/.gitignore*', "\*$")
let g:m2 = match('vim/.gitignore*', '\*$')
]])

assert_list_eq("glob('./*') stays relative", g.g1, { "./.gitignore", "./README.md", "./lua" })
assert_list_eq("glob('./.*') stays relative", g.g2, { "./.gitignore" })
assert_list_eq("glob('*') stays cwd-relative", g.g3, { ".gitignore", "README.md", "lua" })
assert_list_eq("glob('.*') stays cwd-relative", g.g4, { ".gitignore" })
assert_eq("simplify('./*') keeps dot prefix", g.simp, "./*")
assert_eq("double-quoted pattern keeps backslash", g.s1, "vim/.gitignore")
assert_eq("single-quoted pattern works", g.s2, "vim/.gitignore")
assert_eq("substitute backref \\1 works", g.s3, "/tmp/codex-netrw/a")
assert_eq("substitute backref \\2 works", g.s4, "b")
assert_eq("substitute swaps backrefs", g.s5, "ba")
assert_eq("substitute backref with ignorecase keeps original case", g.s6, "AB")
assert_eq("substitute supports \\0, &, and literal \\&", g.s7, "[foo:foo:&]")
assert_eq("double-quoted match works", g.m1, 14)
assert_eq("single-quoted match works", g.m2, 14)

print("netrw glob/substitute semantics test: OK")
