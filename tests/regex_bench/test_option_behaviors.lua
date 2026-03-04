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
        ["layout.buffer"] = {},
        ["lib.highlight"] = {
            For = function() return { colors.white, colors.black } end,
        },
        ["lib.sign"] = {
            define = function() end,
            getdefined = function() return {} end,
        },
        ["lib.scriptsource"] = {
            CurrentContext = function()
                return rawget(_G, "__test_script_ctx")
            end,
            PushContext = function() end,
            PopContext = function() end,
        },
    },
})

local Options = mock.loadModule("lib.options")
_G.options = Options
local Runtime = mock.loadModule("lib.excmd.runtime")
local ExMsg = mock.loadModule("lib.excmd.exmsg")
Runtime.CurrentScriptSid = function()
    return rawget(_G, "__test_sid")
end
Runtime.CanonicalFunctionName = function(fname, opts)
    local ctx = type(opts) == "table" and opts.script_ctx
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

local function assert_match(label, got, pattern)
    if type(got) ~= "string" or not got:match(pattern) then
        error(("FAIL %s: expected pattern %s, got %s"):format(label, tostring(pattern), tostring(got)))
    end
end

Options.set("path", ".,/project/lua,/project/inc", false, win, buf)
Options.set("suffixesadd", ".lua", true, win, buf)
Options.set("includeexpr", "substitute(v:fname,'\\.','/','g')", true, win, buf)

local Fn = mock.loadModule("lib.luaapi.fn")
local ApiBuild = mock.loadModule("lib.luaapi.apibuild")
local Error = mock.loadModule("lib.error")
local vimapi = ApiBuild.Build().vim

assert_eq("findfile includeexpr+suffixesadd", Fn.fn.findfile("pkg.mod"), "/project/lua/pkg/mod.lua")
assert_eq("finddir", Fn.fn.finddir("pkg", "/project/lua"), "/project/lua/pkg")
assert_eq("expand <cfile>", Fn.fn.expand("<cfile>"), "/project/lua/pkg/mod.lua")
assert_eq("resolve simplifies path", Fn.fn.resolve("/project/src/../lua/pkg"), "/project/lua/pkg")
assert_eq("resolve preserves trailing slash", Fn.fn.resolve("/project/src/../lua/pkg/"), "/project/lua/pkg/")
assert_eq("expand <SID> without script id", Fn.fn.expand("<SID>"), "")
_G.__test_script_ctx = "/project/plugin/test.vim"
assert_eq("expand <SID> with script context", Fn.fn.expand("<SID>"), "<SNR>88_")
_G.__test_script_ctx = nil
_G.__test_sid = 42
assert_eq("expand <SID> with script id", Fn.fn.expand("<SID>"), "<SNR>42_")
_G.__test_sid = nil

buf.lines = { "one", "two", "three" }
assert_eq("getline single", Fn.fn.getline(2), "two")
local range = Fn.fn.getline(1, 3)
assert_eq("getline range count", #range, 3)
assert_eq("getline range first", range[1], "one")
assert_eq("getline range last", range[3], "three")
assert_eq("join(getline range)", Fn.fn.join(range, "\n"), "one\ntwo\nthree")

assert_eq("keywordprg abbreviation resolves", Options.resolve_abbrev("kp"), "keywordprg")
assert_eq("mousemodel abbreviation resolves", Options.resolve_abbrev("mousem"), "mousemodel")
assert_eq("mousetime abbreviation resolves", Options.resolve_abbrev("mouset"), "mousetime")
assert_eq("mousemoveevent abbreviation resolves", Options.resolve_abbrev("mousemev"), "mousemoveevent")
assert_eq("undolevels abbreviation resolves", Options.resolve_abbrev("ul"), "undolevels")
assert_eq("undofile abbreviation resolves", Options.resolve_abbrev("udf"), "undofile")
assert_eq("concealcursor abbreviation resolves", Options.resolve_abbrev("cocu"), "concealcursor")
assert_eq("conceallevel abbreviation resolves", Options.resolve_abbrev("cole"), "conceallevel")
assert_eq("concealcursor default", Options.get("concealcursor", win, buf), "")
assert_eq("conceallevel default", Options.get("conceallevel", win, buf), 0)
assert_eq("mouse default", Options.get("mouse", win, buf), "nvi")
assert_eq("mousemodel default", Options.get("mousemodel", win, buf), "popup_setpos")
assert_eq("mousetime default", Options.get("mousetime", win, buf), 500)
Options.set("concealcursor", "nvic", true, win, buf)
Options.set("conceallevel", 3, true, win, buf)
assert_eq("concealcursor set/get", Options.get("concealcursor", win, buf, true), "nvic")
assert_eq("conceallevel set/get", Options.get("conceallevel", win, buf, true), 3)
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

assert_eq("undolevels default", Options.get("undolevels", win, buf), 1000)
Options.set("undolevels", 777, false, win, buf, true)
Options.set("undolevels", -1, true, win, buf)
assert_eq("undolevels local override", Options.get("undolevels", win, buf, true), -1)
assert_eq("undolevels global value", Options.get("undolevels", win, buf, false, true), 777)
Options.exset_token("undolevels<", "local", win, buf)
assert_eq("undolevels < copies global to local", Options.get("undolevels", win, buf, true), 777)

assert_eq("undofile default", Options.get("undofile", win, buf), false)
Options.set("undofile", true, true, win, buf)
assert_eq("undofile local set/get", Options.get("undofile", win, buf, true), true)

Options.set("mousem", "popup", false, win, buf, true)
assert_eq("mousemodel set via alias", Options.get("mousemodel", win, buf), "popup")
Options.set("mouset", 250, false, win, buf, true)
assert_eq("mousetime set via alias", Options.get("mousetime", win, buf), 250)

local ok_bad_mouse = pcall(function()
    Options.set("mouse", "z", false, win, buf, true)
end)
assert_eq("mouse invalid value rejects", ok_bad_mouse, false)

Options.exset_token("mouse=nvn", "both", win, buf)
assert_eq("mouse = deduplicates repeated flags", Options.get("mouse", win, buf), "vn")
Options.exset_token("mouse+=ni", "both", win, buf)
assert_eq("mouse += moves flags to end", Options.get("mouse", win, buf), "vni")
Options.exset_token("mouse=nvi", "both", win, buf)
Options.exset_token("mouse^=ca", "both", win, buf)
assert_eq("mouse ^= prepends missing flags", Options.get("mouse", win, buf), "canvi")
Options.exset_token("mouse-=ni", "both", win, buf)
assert_eq("mouse -= keeps non-contiguous flags", Options.get("mouse", win, buf), "canvi")
Options.exset_token("mouse=vni", "both", win, buf)
Options.exset_token("mouse-=ni", "both", win, buf)
assert_eq("mouse -= removes contiguous substring", Options.get("mouse", win, buf), "v")
Options.exset_token("mouse=nvi", "both", win, buf)
Options.exset_token("mouse-=ni", "both", win, buf)
assert_eq("mouse -= keeps non-contiguous flags from base value", Options.get("mouse", win, buf), "nvi")
local ok_mouse_remove_unknown = pcall(function()
    Options.exset_token("mouse-=N", "both", win, buf)
end)
assert_eq("mouse -= with unknown flag is a no-op", ok_mouse_remove_unknown, true)

local ok_mouse_upper, err_mouse_upper = pcall(function()
    Options.exset_token("mouse=N", "both", win, buf)
end)
assert_eq("mouse uppercase flag rejects", ok_mouse_upper, false)
assert_match(
    "mouse uppercase error uses E539",
    Error.IsError(err_mouse_upper) and err_mouse_upper:toString(),
    "E539: Illegal character <N>: mouse=N"
)

local ok_mouse_plus_upper, err_mouse_plus_upper = pcall(function()
    Options.exset_token("mouse+=N", "both", win, buf)
end)
assert_eq("mouse += uppercase flag rejects", ok_mouse_plus_upper, false)
assert_match(
    "mouse += error keeps operator in rhs",
    Error.IsError(err_mouse_plus_upper) and err_mouse_plus_upper:toString(),
    "E539: Illegal character <N>: mouse%+=N"
)

local ok_mouse_caret_upper, err_mouse_caret_upper = pcall(function()
    Options.exset_token("mouse^=N", "both", win, buf)
end)
assert_eq("mouse ^= uppercase flag rejects", ok_mouse_caret_upper, false)
assert_match(
    "mouse ^= error keeps operator in rhs",
    Error.IsError(err_mouse_caret_upper) and err_mouse_caret_upper:toString(),
    "E539: Illegal character <N>: mouse%^=N"
)

vimapi.wo[0][0].number = false
assert_eq("wo double index set/get", vimapi.wo[0][0].number, false)
assert_eq("wo single index still works", vimapi.wo[0].number, false)

local ok_invalid_buf = pcall(function()
    return vimapi.wo[0][999].number
end)
assert_eq("wo double index invalid buffer", ok_invalid_buf, false)

Options.set("cpoptions", "test", false, win, buf)
local msg_count_before_cpo_reset = #ExMsg.messages
Options.exset_token("cpoptions&vim", "both", win, buf)
assert_eq("cpoptions&vim resets value", Options.get("cpoptions", win, buf), "aABceFs_")
assert_eq("cpoptions&vim does not echo value", #ExMsg.messages, msg_count_before_cpo_reset)

local rt = Runtime.new()
local ok_mouse_multi, err_mouse_multi = pcall(function()
    rt:set_options("number mouse=nv!", "global")
end)
assert_eq("set with invalid mouse in multi-token command fails", ok_mouse_multi, false)
assert_match(
    "set with invalid mouse reports single option token",
    Error.IsError(err_mouse_multi) and err_mouse_multi:toString(),
    "E539: Illegal character <!>: mouse=nv!"
)

local msg_count_before_setlocal_comment = #ExMsg.messages
rt:set_options('path-=. " remove cwd from path', "local")
assert_eq(
    "setlocal path-=. with comment applies change",
    Options.get("path", win, buf, true),
    ",/project/lua,/project/inc"
)
assert_eq("setlocal path-=. with comment does not echo path", #ExMsg.messages, msg_count_before_setlocal_comment)

Options.set("commentstring", "-- %s", true, win, buf)
assert_eq("commentstring format", Options.FormatCommentString("hello", win, buf), "-- hello")

print("Option behavior tests: OK")
