local MockEnv = require("vim.tests.test_mocks")

local echoerr_calls = {}
local exmsg_stub = {
    messages = {},
    echo = function() end,
    echon = function() end,
    echomsg = function() end,
    echoerr = function(message)
        echoerr_calls[#echoerr_calls + 1] = tostring(message or "")
    end,
    echohl = function() end,
    PushSilent = function() end,
    PushUnsilent = function() end,
    PopSilent = function() end,
    _writeWithHL = function() end,
}

local files = {}
local dirs = {
    ["/"] = true,
    ["/tmp"] = true,
}

local function norm(path)
    local p = tostring(path or ""):gsub("//+", "/")
    if p == "" then
        p = "/"
    end
    if p ~= "/" then
        p = p:gsub("/+$", "")
    end
    return p
end

local function set_file(path, data)
    files[norm(path)] = tostring(data or "")
end

_G.textutils = {
    json_null = {},
    empty_json_array = {},
    unserializeJSON = function(s, _opts)
        local src = tostring(s or "")
        if src:find("^%s*{%s*") and src:find("}%s*$") then
            local title = src:match('"title"%s*:%s*"([^"]*)"')
            if title ~= nil then
                return { title = title }
            end
            return {}
        end
        return nil, "invalid json"
    end,
}

local mock = MockEnv.setup({
    fs = {
        exists = function(path)
            local p = norm(path)
            return dirs[p] == true or files[p] ~= nil
        end,
        isDir = function(path)
            return dirs[norm(path)] == true
        end,
        list = function()
            return {}
        end,
        open = function(path, mode)
            local p = norm(path)
            local m = tostring(mode or "")
            if m == "r" or m == "rb" then
                local data = files[p]
                if data == nil then
                    return nil
                end
                return {
                    readAll = function()
                        return data
                    end,
                    close = function() end,
                }
            end
            return nil
        end,
        isReadOnly = function()
            return false
        end,
        getSize = function(path)
            local data = files[norm(path)]
            return data and #data or 0
        end,
    },
    module_stubs = {
        ["vim.lib.exmsg"] = exmsg_stub,
        ["vim.lib.excmd.exmsg"] = exmsg_stub,
        ["vim.lib.highlight"] = {
            GroupExists = function() return false end,
            For = function() return { colors.white, colors.black } end,
        },
        ["vim.lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
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

local function assert_true(label, cond, detail)
    if not cond then
        error(("FAIL %s: %s"):format(label, tostring(detail or "assertion failed")))
    end
end

local function assert_list_eq(label, got, want)
    if type(got) ~= "table" then
        error(("FAIL %s: expected list table, got %s"):format(label, type(got)))
    end
    if #got ~= #want then
        error(("FAIL %s: expected len %d, got %d"):format(label, #want, #got))
    end
    for i = 1, #want do
        if got[i] ~= want[i] then
            error(("FAIL %s[%d]: expected %s, got %s"):format(label, i, tostring(want[i]), tostring(got[i])))
        end
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Fn = mock.loadModule("lib.luaapi.fn")
local Compiler = mock.loadModule("lib.excmd.compiler")
local Runtime = mock.loadModule("lib.excmd.runtime")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Buffer = mock.loadModule("layout.buffer")

local buf = Buffer(true, false)
buf.name = "/tmp/readfile-current.txt"
buf.lines = { "" }
local win = {
    winnr = 1,
    buffer = buf,
    opts = {},
    cursorx = 1,
    cursory = 1,
    scrolly = { 1, 0 },
    scrollx = 0,
    cursorSet = function(self, x, y)
        self.cursorx = x
        self.cursory = y
    end,
}
windows[1] = win
tabpages[1].windows = { win }
curwin = 1

local durable_by_ctx = {}
local function run_compiled(script, opts)
    opts = opts or {}
    local key = opts.script_ctx or "__default"
    local durable = durable_by_ctx[key]
    if not durable then
        durable = Runtime.CaptureDurableScriptState({ script_ctx = opts.script_ctx }) or { s = {}, funcs = {} }
        durable.g = durable.g or Scopes._g
        durable_by_ctx[key] = durable
    end

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

do
    local p = "/tmp/readfile-basic.txt"
    local bom = "\239\187\191"
    set_file(p, bom .. "alpha\r\nbeta\nmu\0nu\n")

    local plain = Fn.readfile(p)
    assert_list_eq("readfile text mode", plain, { "alpha", "beta", "mu", "nu" })

    local binary = Fn.readfile(p, "b")
    assert_list_eq("readfile binary mode", binary, { bom .. "alpha\r", "beta", "mu", "nu", "" })

    assert_list_eq("readfile max positive", Fn.readfile(p, "", 2), { "alpha", "beta" })
    assert_list_eq("readfile max negative", Fn.readfile(p, "", -2), { "mu", "nu" })
    assert_list_eq("readfile max zero", Fn.readfile(p, "", 0), {})
end

do
    local missing = "/tmp/readfile-missing-" .. tostring(math.random(100000, 999999)) .. ".txt"
    echoerr_calls = {}
    local rv = Fn.readfile(missing)
    assert_list_eq("readfile missing returns empty list", rv, {})
    assert_true(
        "readfile missing emits E484",
        #echoerr_calls >= 1 and echoerr_calls[#echoerr_calls]:find("E484", 1, true) ~= nil,
        tostring(echoerr_calls[#echoerr_calls] or "")
    )
end

do
    local tutor_path = "/tmp/readfile-tutor-case.tutor"
    local metadata_path = tutor_path .. ".json"
    set_file(tutor_path, "")
    local metadata_text = "{\n  \"title\": \"Tutor\"\n}\n"
    set_file(metadata_path, metadata_text)

    windows[curwin].buffer.name = tutor_path

    local ok, err = run_compiled([[
let b:tutor_metadata = json_decode(join(readfile(expand('%').'.json'), "\n"))
]], { script_ctx = "/vim/runtime/ftplugin/tutor.vim" })
    if ok ~= true then
        error(("FAIL tutor metadata expression runs: %s"):format(tostring(err)))
    end

    local bscope = Scopes._b_by_buf[windows[curwin].buffer.bufnr] or {}
    assert_true("tutor metadata dict present", type(bscope.tutor_metadata) == "table", type(bscope.tutor_metadata))
    assert_eq("tutor metadata title", bscope.tutor_metadata.title, "Tutor")
end

do
    local decoded = Fn.json_decode("{\"title\":\"Direct\"}")
    assert_true("json_decode string returns dict", type(decoded) == "table", type(decoded))
    assert_eq("json_decode string title", decoded.title, "Direct")

    local decoded_list = Fn.json_decode({ "{\"title\":", "\"List\"}" })
    assert_true("json_decode list returns dict", type(decoded_list) == "table", type(decoded_list))
    assert_eq("json_decode list title", decoded_list.title, "List")

    local ok_err, err = pcall(function()
        return Fn.json_decode("{invalid")
    end)
    assert_eq("json_decode invalid throws", ok_err, false)
    assert_true("json_decode invalid uses E474", tostring(err):find("E474", 1, true) ~= nil, tostring(err))
end

print("readfile builtin tests: OK")
