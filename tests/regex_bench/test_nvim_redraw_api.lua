local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup()
local api = mock.loadModule("lib.luaapi.api")
local Decoration = mock.loadModule("lib.decoration")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local buf1 = mock.create_buffer(1, "/tmp/redraw-api-1.txt", { "one" })
local buf2 = mock.create_buffer(2, "/tmp/redraw-api-2.txt", { "two" })
buf1.refcount = 1
buf2.refcount = 1

local win1 = { winnr = 1, buffer = buf1, need_redraw = false }
local win2 = { winnr = 2, buffer = buf2, need_redraw = false }
windows[1] = win1
windows[2] = win2
curtp = 1
curwin = 1

local render_count = 0
tabpages[1].windows = { win1, win2 }
tabpages[1].render = function()
    render_count = render_count + 1
end

local function reset_flags()
    win1.need_redraw = false
    win2.need_redraw = false
    need_redraw = false
    what_redraw = {}
end

reset_flags()
api.nvim__redraw({ win = win1.winnr, valid = false, flush = false })
assert_eq("target window marked", win1.need_redraw, true)
assert_eq("other window untouched", win2.need_redraw, false)
assert_eq("no flush render", render_count, 0)

reset_flags()
api.nvim__redraw({ buf = buf1.bufnr, valid = true, flush = false })
assert_eq("buffer redraw marks attached window", win1.need_redraw, true)
assert_eq("unattached window untouched", win2.need_redraw, false)

reset_flags()
api.nvim__redraw({})
assert_eq("flush renders immediately by default", render_count, 1)

reset_flags()
Decoration.begin_redraw()
api.nvim__redraw({ win = win1.winnr, flush = true })
Decoration.end_redraw()
assert_eq("flush suppressed while redraw callbacks run", render_count, 1)
assert_eq("target window still marked while flush suppressed", win1.need_redraw, true)

print("nvim__redraw api tests: OK")
