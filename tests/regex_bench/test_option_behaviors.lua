-- Test option behaviors with custom fs and module stubs
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
    ["/"] = { "project" },
    ["/project"] = { "src", "lua", "inc" },
    ["/project/src"] = { "main.lua" },
    ["/project/lua"] = { "pkg" },
    ["/project/lua/pkg"] = { "mod.lua" },
    ["/project/inc"] = { "defs.h" },
}

local files = {
    ["/project/src/main.lua"] = "require 'pkg.mod'",
    ["/project/lua/pkg/mod.lua"] = "return {}",
    ["/project/inc/defs.h"] = "#define X 1",
}

local mock = MockEnv.setup({
    fs = {
        exists = function(path)
            path = norm(path)
            return dirs[path] ~= nil or files[path] ~= nil
        end,
        isDir = function(path)
            return dirs[norm(path)] ~= nil
        end,
        list = function(path)
            local entries = dirs[norm(path)] or {}
            local out = {}
            for i = 1, #entries do out[i] = entries[i] end
            return out
        end,
        open = function(path, mode)
            path = norm(path)
            if mode == "r" then
                local text = files[path]
                if text == nil then return nil end
                return {
                    readAll = function() return text end,
                    close = function() end,
                }
            end
            return nil
        end,
        isReadOnly = function(_)
            return false
        end,
        getSize = function(path)
            local text = files[norm(path)]
            return text and #text or 0
        end,
    },
    shell = {
        dir = function()
            return "/project"
        end,
    },
    module_stubs = {
        ["vim.layout.buffer"] = {},
        ["vim.lib.highlight"] = {
            For = function() return { colors.white, colors.black } end,
        },
        ["vim.lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["vim.lib.scriptsource"] = {
            CurrentContext = function()
                return rawget(_G, "__test_script_ctx")
            end,
        },
    },
})

local Options = mock.loadModule("vim.lib.options")
_G.options = Options
local Runtime = mock.loadModule("vim.lib.excmd.runtime")
local ExMsg = mock.loadModule("vim.lib.excmd.exmsg")
Runtime.CurrentScriptSid = function()
    return rawget(_G, "__test_sid")
end
Runtime.CanonicalFunctionName = function(fname, opts)
    local ctx = type(opts) == "table" and opts.script_ctx or nil
    if type(ctx) == "string" and ctx ~= "" then
        local tail = tostring(fname or ""):gsub("^s:", "")
        return "<SNR>88_" .. tail
    end
    return fname
end

local buf = mock.create_buffer(1, "/project/src/main.lua", { "require 'pkg.mod'" })
local win = mock.create_window(1, buf)
win.cursorx = 12
win.cursory = 1
win.scrolly = { 1, 0 }
win.scrollx = 1
tabpages[1].windows = { win }

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

Options.set("path", ".,/project/lua,/project/inc", false, win, buf)
Options.set("suffixesadd", ".lua", true, win, buf)
Options.set("includeexpr", "substitute(v:fname,'\\.','/','g')", true, win, buf)

local Fn = mock.loadModule("vim.lib.luaapi.fn")
local Opts = mock.loadModule("vim.lib.luaapi.opts")

assert_eq("findfile includeexpr+suffixesadd", Fn.findfile("pkg.mod"), "/project/lua/pkg/mod.lua")
assert_eq("finddir", Fn.finddir("pkg", "/project/lua"), "/project/lua/pkg")
assert_eq("expand <cfile>", Fn.expand("<cfile>"), "/project/lua/pkg/mod.lua")
assert_eq("resolve simplifies path", Fn.resolve("/project/src/../lua/pkg"), "/project/lua/pkg")
assert_eq("resolve preserves trailing slash", Fn.resolve("/project/src/../lua/pkg/"), "/project/lua/pkg/")
assert_eq("expand <SID> without script id", Fn.expand("<SID>"), "")
_G.__test_script_ctx = "/project/plugin/test.vim"
assert_eq("expand <SID> with script context", Fn.expand("<SID>"), "<SNR>88_")
_G.__test_script_ctx = nil
_G.__test_sid = 42
assert_eq("expand <SID> with script id", Fn.expand("<SID>"), "<SNR>42_")
_G.__test_sid = nil

buf.lines = { "one", "two", "three" }
assert_eq("getline single", Fn.getline(2), "two")
local range = Fn.getline(1, 3)
assert_eq("getline range count", #range, 3)
assert_eq("getline range first", range[1], "one")
assert_eq("getline range last", range[3], "three")
assert_eq("join(getline range)", Fn.join(range, "\n"), "one\ntwo\nthree")

assert_eq("keywordprg abbreviation resolves", Options.resolve_abbrev("kp"), "keywordprg")
assert_eq("keywordprg default", Options.get("keywordprg", win, buf), ":Man")
Options.set("kp", ":VimKeywordPrg", true, win, buf)
assert_eq("keywordprg local set via alias", Options.get("keywordprg", win, buf, true), ":VimKeywordPrg")
Options.set("keywordprg", ":GlobalKeywordPrg", false, win, buf, true)
Options.set("keywordprg", ":LocalKeywordPrg", true, win, buf)
assert_eq("keywordprg local override", Options.get("keywordprg", win, buf, true), ":LocalKeywordPrg")
Options.exset_token("keywordprg<", "local", win, buf)
assert_eq("keywordprg < copies global value", Options.get("keywordprg", win, buf, true), ":GlobalKeywordPrg")

Options.set("commentstring", "-- %s", true, win, buf)
assert_eq("commentstring local override", Options.get("commentstring", win, buf, true), "-- %s")
Options.exset_token("commentstring<", "local", win, buf)
assert_eq("commentstring < resets local-only option to default", Options.get("commentstring", win, buf, true), "")
Options.set("commentstring", "GLOBAL_%s", false, win, buf, true)
Options.set("commentstring", "LOCAL_%s", true, win, buf)
Options.exset_token("commentstring<", "local", win, buf)
assert_eq("commentstring < copies local-option global value", Options.get("commentstring", win, buf, true), "GLOBAL_%s")

Opts.wo[0][0].number = false
assert_eq("wo double index set/get", Opts.wo[0][0].number, false)
assert_eq("wo single index still works", Opts.wo[0].number, false)

local ok_invalid_buf = pcall(function()
    return Opts.wo[0][999].number
end)
assert_eq("wo double index invalid buffer", ok_invalid_buf, false)

Options.set("cpoptions", "test", false, win, buf)
local msg_count_before_cpo_reset = #ExMsg.messages
Options.exset_token("cpoptions&vim", "both", win, buf)
assert_eq("cpoptions&vim resets value", Options.get("cpoptions", win, buf), "aABceFs_")
assert_eq("cpoptions&vim does not echo value", #ExMsg.messages, msg_count_before_cpo_reset)

local rt = Runtime.new()
local msg_count_before_setlocal_comment = #ExMsg.messages
rt:set_options('path-=. " remove cwd from path', "local")
assert_eq("setlocal path-=. with comment applies change", Options.get("path", win, buf, true), ",/project/lua,/project/inc")
assert_eq("setlocal path-=. with comment does not echo path", #ExMsg.messages, msg_count_before_setlocal_comment)

Options.set("commentstring", "-- %s", true, win, buf)
assert_eq("commentstring format", Options.FormatCommentString("hello", win, buf), "-- hello")

print("Option behavior tests: OK")
