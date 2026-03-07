local MockEnv = require("vim.tests.test_mocks")

local file_store = {}
local function fs_open(path, mode)
    if mode == "r" then
        local data = file_store[path]
        if data == nil then
            return nil
        end
        return {
            readAll = function() return data end,
            close = function() end,
        }
    end

    if mode == "w" then
        local out = ""
        return {
            write = function(s) out = out .. tostring(s or "") end,
            close = function() file_store[path] = out end,
        }
    end

    if mode == "a" then
        local out = file_store[path] or ""
        return {
            write = function(s) out = out .. tostring(s or "") end,
            close = function() file_store[path] = out end,
        }
    end

    return nil
end

local mock = MockEnv.setup({
    fs = {
        exists = function(path) return file_store[path] ~= nil end,
        isDir = function() return false end,
        list = function() return {} end,
        open = fs_open,
        isReadOnly = function() return false end,
        getSize = function(path)
            local data = file_store[path]
            if data == nil then return 0 end
            return #data
        end,
    },
    module_stubs = {
        ["lib.exmsg"] = function() return mock.loadModule("lib.excmd.exmsg") end,
        ["lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
        },
        ["lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
    },
})

_G.screen = { width = 80, height = 24 }
term.setCursorPos = term.setCursorPos or function() end
term.clearLine = term.clearLine or function() end
term.blit = term.blit or function() end
term.write = term.write or function() end
term.getSize = term.getSize or function() return 80, 24 end

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s: expected true, got false"):format(label))
    end
end

local function err_string(err)
    if type(err) == "table" then
        if type(err.toString) == "function" then
            return err:toString()
        end
        if err.code then
            return ("code=%s message=%s"):format(tostring(err.code), tostring(err.message))
        end
    end
    return tostring(err)
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Buffer = mock.loadModule("layout.buffer")

local win = mock.create_window(1, Buffer(true, false), {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

local function make_current_buffer(name, modified, fileformat)
    local buf = Buffer(true, false)
    buf.name = name
    buf.refcount = 1
    buf.opts.modified = not not modified
    if fileformat ~= nil then
        buf.opts.fileformat = fileformat
    end
    win.buffer = buf
    return buf
end

local function run_compiled(script, script_ctx)
    local durable = { s = {}, funcs = {}, g = Scopes._g, script_ctx = script_ctx }
    local state = Runtime.MakeRuntimeState(durable)
    state.g = durable.g
    local runtime = Runtime.new(state)

    local code, err = Compiler.compile_script(script, { state = state })
    if not code then return false, err end

    local env = setmetatable({ runtime = runtime, _G = _G }, { __index = _G })
    local chunk, lerr = load(code, "excmd_compiled", "t", env)
    if not chunk then return false, lerr end

    local fn = chunk()
    local ok, rv = pcall(fn, state, runtime)
    if not ok then return false, rv end
    return true, rv
end

Options.set("hidden", false)
Options.set("autowriteall", false)
Options.set("fileformats", "dos,unix")
make_current_buffer("/tmp/needs_write.txt", true, "mac")

do
    local ok, rv = run_compiled("enew", "/tmp/enew_fail.vim")
    assert_true("enew without bang fails when modified", ok == false and err_string(rv):find("E37", 1, true) ~= nil)
end

do
    local before = win.buffer
    local ok, rv = run_compiled("ene!", "/tmp/enew_bang.vim")
    assert_true("ene! executes", ok == true)
    if ok ~= true then
        error(err_string(rv))
    end
    assert_true("ene! switched buffer", win.buffer ~= before)
    assert_eq("ene! uses unnamed buffer", win.buffer.name, "")
    assert_eq("ene! picks first fileformats entry", win.buffer.opts.fileformat, "dos")
end

do
    Options.set("fileformats", "")
    make_current_buffer("/tmp/current_mac.txt", true, "mac")
    local ok, rv = run_compiled("enew!", "/tmp/enew_fileformat_fallback.vim")
    assert_true("enew! executes when fileformats empty", ok == true)
    if ok ~= true then
        error(err_string(rv))
    end
    assert_eq("enew! falls back to current fileformat", win.buffer.opts.fileformat, "mac")
end

do
    Scopes._g.redir_var = nil
    local ok, rv = run_compiled([[
redir => g:redir_var
echo "alpha"
echon "beta"
redir END
]], "/tmp/redir_var.vim")
    assert_true("redir to variable executes", ok == true)
    if ok ~= true then
        error(err_string(rv))
    end
    assert_eq("redir captures echo/echon into variable", Scopes._g.redir_var, "alpha\nbeta\n")
end

do
    Scopes._g.redir_one = nil
    Scopes._g.redir_two = nil
    local ok, rv = run_compiled([[
redir => g:redir_one
echo "one"
redir => g:redir_two
echo "two"
redir END
]], "/tmp/redir_switch_targets.vim")
    assert_true("redir target switch executes", ok == true)
    if ok ~= true then
        error(err_string(rv))
    end
    assert_eq("first redir target closed on new redir", Scopes._g.redir_one, "one\n")
    assert_eq("second redir target receives later output", Scopes._g.redir_two, "two\n")
end

do
    file_store["/tmp/redir_file.txt"] = "old\n"
    local ok, rv = run_compiled("redir > /tmp/redir_file.txt", "/tmp/redir_file_exists.vim")
    assert_true("redir > existing file without ! fails", ok == false and err_string(rv):find("E474", 1, true) ~= nil)
end

do
    local ok, rv = run_compiled([[
redir! > /tmp/redir_file.txt
echo "fresh"
redir END
]], "/tmp/redir_file_force.vim")
    assert_true("redir! > file executes", ok == true)
    if ok ~= true then
        error(err_string(rv))
    end
    assert_eq("redir! overwrites file", file_store["/tmp/redir_file.txt"], "fresh\n")
end

do
    registers["a"] = nil
    local ok, rv = run_compiled([[
redir @a
echo "x"
redir END
redir @A
echo "y"
redir END
]], "/tmp/redir_register_append.vim")
    assert_true("redir register + append executes", ok == true)
    if ok ~= true then
        error(err_string(rv))
    end
    assert_eq("register append via uppercase keeps previous text", table.concat(registers["a"][2], "\n"), "x\ny\n")
end

print("enew/redir runtime tests: OK")
