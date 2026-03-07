local MockEnv = require("vim.tests.test_mocks")

local exmsg_stub = {
    messages = {},
    echo = function() end,
    echon = function() end,
    echomsg = function() end,
    echoerr = function() end,
    echohl = function() end,
    PushSilent = function() end,
    PushUnsilent = function() end,
    PushUISuppress = function() end,
    PopUISuppress = function() end,
    StartCapture = function()
        return {}
    end,
    EndCapture = function()
        return "", nil
    end,
    PopSilent = function() end,
    _writeWithHL = function() end,
}

local mock = MockEnv.setup({
    fs = {
        exists = function(path)
            return path == "/" or path == "/tmp/start"
        end,
        isDir = function(path)
            return path == "/"
        end,
        attributes = function(path)
            if path == "/tmp/start" then
                return {
                    size = 6,
                    isDir = false,
                    created = 0,
                    modified = 0,
                }
            end
            error(path .. ": No such file")
        end,
        open = function(path, mode)
            if path == "/tmp/start" and mode == "r" then
                return {
                    readAll = function() return "start\n" end,
                    close = function() end,
                }
            end
            return nil
        end,
        isReadOnly = function() return false end,
        getSize = function() return 0 end,
        list = function() return {} end,
    },
    module_stubs = {
        ["lib.exmsg"] = function() return exmsg_stub end,
        ["lib.excmd.exmsg"] = exmsg_stub,
        ["lib.command"] = {
            clear_mappings = function() end,
            unmap_keys = function() end,
            remap_keys = function() end,
            noremap_keys = function() end,
            emit_raw = function() end,
        },
        ["lib.key"] = {
            strtoseq = function(s)
                local out = {}
                for i = 1, #s do
                    out[#out + 1] = s:sub(i, i)
                end
                return out
            end,
        },
        ["lib.pack"] = {
            add = function() return true end,
            load_start = function() return true end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["lib.syntax"] = {
            ParseLinetypes = function() end,
            OnWindowBufferChanged = function() end,
            OnSyntaxOptionSet = function() end,
            OnSynmaxcolOptionSet = function() end,
        },
        ["lib.tags"] = {
            SearchFile = function() return nil end,
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
        error(("FAIL %s: %s"):format(label, tostring(detail)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options
local Buffer = mock.loadModule("layout.buffer")
local Api = mock.loadModule("lib.luaapi.api")
local Autocmd = mock.loadModule("lib.autocmd")
local Loop = mock.loadModule("lib.luaapi.loop")
local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local Error = mock.loadModule("lib.error")

local buf = Buffer(true, false)
buf.name = "/tmp/start"
buf.lines = { "start" }
buf.refcount = 1

local win = mock.create_window(1, buf, {})
windows[1] = win
tabpages[1].windows = { win }
curtp = 1
curwin = 1

local seen = {
    bufadd = 0,
    readcmd = 0,
    buflocal = 0,
}

Api.nvim_create_autocmd("BufAdd", {
    pattern = "*",
    callback = function(params)
        seen.bufadd = seen.bufadd + 1
        if params.file == "/" then
            Api.nvim_buf_set_name(params.buf, "oil:///")
        end
    end,
})

Api.nvim_create_autocmd("BufReadCmd", {
  pattern = "oil://*,oil-ssh://*",
  callback = function()
    seen.readcmd = seen.readcmd + 1
  end,
})

local readcmd_au = Api.nvim_get_autocmds({ event = "BufReadCmd" })
local saw_oil_pattern = false
for _, au in ipairs(readcmd_au) do
  if au.pattern == "oil://*" or au.pattern == "oil-ssh://*" then
    saw_oil_pattern = true
  end
end
assert_true("nvim_get_autocmds reports split comma patterns", saw_oil_pattern, saw_oil_pattern)

local tmp_au_id = Api.nvim_create_autocmd("User", {
  pattern = "TmpOilProbe",
  callback = function() end,
})
assert_true("temporary autocmd created", type(tmp_au_id) == "number", tmp_au_id)
Api.nvim_del_autocmd(tmp_au_id)
assert_eq("nvim_del_autocmd removed command", #Api.nvim_get_autocmds({ event = "User", pattern = "TmpOilProbe" }), 0)

Api.nvim_create_autocmd("BufEnter", {
    buffer = buf.bufnr,
    callback = function()
        seen.buflocal = seen.buflocal + 1
    end,
})

Autocmd.Run("BufEnter", { bufnr = buf.bufnr, bufname = buf.name })
Autocmd.Run("BufEnter", { bufnr = buf.bufnr + 100, bufname = "/tmp/other" })
assert_eq("buffer-local autocmd only runs on target buffer", seen.buflocal, 1)

Api.nvim_exec("edit /", false)

assert_true("BufAdd fired on :edit new buffer", seen.bufadd >= 1, seen.bufadd)
assert_eq("BufReadCmd comma pattern matches oil scheme", seen.readcmd, 1)
assert_eq("directory buffer renamed by BufAdd callback", windows[curwin].buffer.name, "oil:///")
assert_eq("uv.fs_stat returns nil for uri-like paths", Loop.fs_stat("oil:///"), nil)

Api.nvim_win_set_var(0, "oil_probe", 7)
assert_eq("nvim_win_get_var retrieves window var", Api.nvim_win_get_var(0, "oil_probe"), 7)
Api.nvim_win_del_var(0, "oil_probe")
local ok_win_missing = pcall(Api.nvim_win_get_var, 0, "oil_probe")
assert_true("nvim_win_del_var removes value", ok_win_missing == false, ok_win_missing)

Api.nvim_buf_set_var(0, "oil_buf_probe", 9)
assert_eq("nvim_buf_get_var retrieves buffer var", Api.nvim_buf_get_var(0, "oil_buf_probe"), 9)
Api.nvim_buf_del_var(0, "oil_buf_probe")
local ok_buf_missing = pcall(Api.nvim_buf_get_var, 0, "oil_buf_probe")
assert_true("nvim_buf_del_var removes value", ok_buf_missing == false, ok_buf_missing)

local doomed = Buffer(true, false)
doomed.name = "/tmp/doomed"
doomed.lines = { "x" }
Api.nvim_set_current_buf(doomed.bufnr)
Api.nvim_buf_delete(doomed.bufnr, { force = true })
assert_true("nvim_buf_delete removes buffer", buffers[doomed.bufnr] == nil, buffers[doomed.bufnr])
assert_true(
  "nvim_buf_delete switches window away from deleted buffer",
  windows[curwin].buffer.bufnr ~= doomed.bufnr,
  windows[curwin].buffer.bufnr
)

local unloadbuf = Buffer(true, false)
unloadbuf.name = "/tmp/unload"
unloadbuf.lines = { "x" }
Api.nvim_buf_delete(unloadbuf.bufnr, { force = true, unload = true })
assert_true("nvim_buf_delete unload keeps buffer entry", buffers[unloadbuf.bufnr] ~= nil, buffers[unloadbuf.bufnr])
assert_eq("nvim_buf_delete unload clears lines", #buffers[unloadbuf.bufnr].lines, 0)
assert_true(
    "nvim_buf_delete unload marks buffer unloaded",
    buffers[unloadbuf.bufnr].loaded == false,
    tostring(buffers[unloadbuf.bufnr].loaded)
)

local vimapi = ApiBuild.Build().vim
assert_true("vim.endswith is exposed", vimapi.endswith("oil:///", "/"), vimapi.endswith("oil:///", "/"))

local acwrite_hits = 0
Api.nvim_create_autocmd("BufWriteCmd", {
  pattern = "acwrite://*",
  callback = function()
    acwrite_hits = acwrite_hits + 1
  end,
})

local acwrite_buf = Buffer(true, false)
acwrite_buf.name = "acwrite:///probe"
acwrite_buf.lines = { "x" }
Options.set("buftype", "acwrite", true, nil, acwrite_buf)
assert_eq("acwrite dispatches BufWriteCmd", acwrite_buf:write(false), true)
assert_eq("acwrite BufWriteCmd callback fired", acwrite_hits, 1)

local acwrite_missing = Buffer(true, false)
acwrite_missing.name = "acwrite-miss:///probe"
acwrite_missing.lines = { "x" }
Options.set("buftype", "acwrite", true, nil, acwrite_missing)
local miss_status = acwrite_missing:write(false)
assert_true("acwrite missing callback returns error", Error.IsError(miss_status), miss_status)
assert_eq("acwrite missing callback uses E676", miss_status.code, 676)

print("oil directory hijack runtime tests: OK")
