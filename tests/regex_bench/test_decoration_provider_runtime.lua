local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()
local api = mock.loadModule("lib.luaapi.api")
local Decoration = mock.loadModule("lib.decoration")

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

local buf = mock.create_buffer(1, "/tmp/decoration-provider.txt", { "abc" })
buf.refcount = 2

local win1 = { winnr = 1, buffer = buf, need_redraw = false }
local win2 = { winnr = 2, buffer = buf, need_redraw = false }
windows[1] = win1
windows[2] = win2
tabpages[1].windows = { win1, win2 }
curtp = 1
curwin = 1

local calls = {}
local on_buf_calls = 0
local skipped_on_line_calls = 0

local ns = api.nvim_create_namespace("decor.provider.test")
api.nvim_set_decoration_provider(ns, {
    on_start = function(_, tick)
        calls[#calls + 1] = "start:" .. tostring(tick)
    end,
    on_buf = function(_, bufnr, tick)
        on_buf_calls = on_buf_calls + 1
        calls[#calls + 1] = ("buf:%d:%d"):format(bufnr, tick)
    end,
    on_win = function(_, winid, bufnr, topline, botline)
        calls[#calls + 1] = ("win:%d:%d:%d:%d"):format(winid, bufnr, topline, botline)
    end,
    on_line = function(_, _, bufnr, row)
        calls[#calls + 1] = "line:" .. tostring(row)
        api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
            end_col = 1,
            hl_group = "Search",
            ephemeral = true,
        })
    end,
    on_end = function(_, tick)
        calls[#calls + 1] = "end:" .. tostring(tick)
    end,
})

local ns_skip = api.nvim_create_namespace("decor.provider.skip")
api.nvim_set_decoration_provider(ns_skip, {
    on_win = function()
        return false
    end,
    on_line = function()
        skipped_on_line_calls = skipped_on_line_calls + 1
    end,
})

Decoration.begin_redraw()
Decoration.on_window(win1, 0, 0)
Decoration.on_line(win1, 0)
Decoration.on_window(win2, 0, 0)
Decoration.on_line(win2, 0)

local ext_during = api.nvim_buf_get_extmarks(buf.bufnr, ns, { 0, 0 }, { 0, -1 }, {})
assert_eq("ephemeral marks visible during redraw", #ext_during, 2)

Decoration.end_redraw()

local ext_after = api.nvim_buf_get_extmarks(buf.bufnr, ns, { 0, 0 }, { 0, -1 }, {})
assert_eq("ephemeral marks cleared after redraw", #ext_after, 0)
assert_eq("on_buf called once per buffer per cycle", on_buf_calls, 1)
assert_eq("on_line skipped when on_win returns false", skipped_on_line_calls, 0)
assert_true("on_start fired first", calls[1] and calls[1]:match("^start:"), tostring(calls[1]))
assert_true("on_end fired last", calls[#calls] and calls[#calls]:match("^end:"), tostring(calls[#calls]))

api.nvim_set_decoration_provider(ns, nil)
calls = {}
Decoration.begin_redraw()
Decoration.on_window(win1, 0, 0)
Decoration.on_line(win1, 0)
Decoration.end_redraw()
assert_eq("provider removed", #calls, 0)

print("decoration provider runtime tests: OK")
