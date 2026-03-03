local MockEnv = require("vim.tests.test_mocks")
local mock = MockEnv.setup()

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

local function find_capture(items, wanted)
    for i = 1, #items do
        if items[i].capture == wanted then
            return items[i]
        end
    end
    return nil
end

local Options = mock.loadModule("lib.options")
_G.options = Options

local Highlight = mock.loadModule("lib.highlight")
local Scopes = mock.loadModule("lib.luaapi.scopes")
local Treesitter = mock.loadModule("lib.luaapi.treesitter")
local Syntax = mock.loadModule("lib.syntax")

local line = "local function foo(x) return x + 1 end -- doc"
local buf = mock.create_buffer(1, "/tmp/test_ts.lua", { line }, { filetype = "lua", syntax = "" })
local win = mock.create_window(1, buf, {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1

local local_col = assert(string.find(line, "local", 1, true)) - 1
local foo_col = assert(string.find(line, "foo", 1, true)) - 1
local return_col = assert(string.find(line, "return", 1, true)) - 1

local function fg_at_col(blits, lnum, col0)
    local normal = colors.toBlit(Highlight.For("Normal")[1])
    if not blits or not blits[lnum] or not blits[lnum].fg then
        return normal
    end
    return blits[lnum].fg:sub(col0 + 1, col0 + 1)
end

-- Baseline before treesitter: with empty syntax this should be Normal.
local before = Syntax.LinesToBlit(buf, 1, 1, win)
local before_local = fg_at_col(before, 1, local_col)

Treesitter.start(buf.bufnr, "lua")
assert_eq("b:ts_highlight enabled", Scopes._b_by_buf[buf.bufnr].ts_highlight, 1)
assert_true("highlighter active", Treesitter.highlighter.active[buf.bufnr] ~= nil)

-- Capture API must report treesitter captures/ids/lang.
local caps_local = Treesitter.get_captures_at_pos(buf.bufnr, 0, local_col)
local caps_foo = Treesitter.get_captures_at_pos(buf.bufnr, 0, foo_col)
local caps_return = Treesitter.get_captures_at_pos(buf.bufnr, 0, return_col)

local c_local = find_capture(caps_local, "keyword")
local c_foo = find_capture(caps_foo, "function")
local c_return = find_capture(caps_return, "keyword.return")

assert_true("local capture exists", c_local ~= nil)
assert_true("foo capture exists", c_foo ~= nil)
assert_true("return capture exists", c_return ~= nil)
assert_eq("capture lang", c_local.lang, "lua")
assert_true("capture id > 0", type(c_local.id) == "number" and c_local.id > 0)

-- Rendered highlight must change only when treesitter is active.
local after_start = Syntax.LinesToBlit(buf, 1, 1, win)
local keyword_blit = colors.toBlit(Highlight.For("Keyword")[1])
local function_blit = colors.toBlit(Highlight.For("Function")[1])

assert_eq("local becomes keyword after start", fg_at_col(after_start, 1, local_col), keyword_blit)
assert_eq("foo becomes function after start", fg_at_col(after_start, 1, foo_col), function_blit)
assert_true("start changed color from baseline", fg_at_col(after_start, 1, local_col) ~= before_local)

Treesitter.stop(buf.bufnr)
assert_true("highlighter inactive", Treesitter.highlighter.active[buf.bufnr] == nil)

local after_stop = Syntax.LinesToBlit(buf, 1, 1, win)
assert_eq("local returns to baseline after stop", fg_at_col(after_stop, 1, local_col), before_local)

print("treesitter highlight source tests: OK")
