local MockEnv = require("vim.tests.test_mocks")

local epochs = { 1000, 1200, 1300, 1900, 2200 }
local epoch_idx = 0

local autocmd_calls = {}
local scroll_calls = {}
local cursor_calls = {}

local key_stub = {}
function key_stub.new(k, ctrld, shifted, alted)
    return setmetatable({
        numeric = (k or 0)
            + (ctrld and 4096 or 0)
            + (shifted and 8192 or 0)
            + (alted and 16384 or 0),
    }, {
        __index = {
            emittable = function() return nil end,
            printable = function() return "" end,
        },
    })
end
function key_stub.mouse_key(name, ctrld, shifted, alted)
    return setmetatable({
        numeric = 3000
            + (ctrld and 4096 or 0)
            + (shifted and 8192 or 0)
            + (alted and 16384 or 0),
        _name = tostring(name or ""),
    }, {
        __index = {
            emittable = function() return nil end,
            printable = function(self) return self._name end,
        },
    })
end
function key_stub.to_map_notation(_)
    return "<LeftMouse>"
end

local mock = MockEnv.setup({
    os = {
        startTimer = function() return 1 end,
        cancelTimer = function() end,
        pullEvent = function() return "terminate" end,
        epoch = function()
            epoch_idx = epoch_idx + 1
            return epochs[epoch_idx] or epochs[#epochs]
        end,
    },
    module_stubs = {
        ["lib.command"] = {
            HandleKey = function() end,
            has_mapping = function() return false end,
        },
        ["lib.key"] = key_stub,
        ["lib.luaapi.on_key"] = {
            dispatch = function() return false end,
        },
        ["lib.excmd.exmsg"] = {
            Finalize = function() end,
            echoerr = function() end,
        },
        ["lib.frame"] = {
            FrameAtWithLocal = function(tree, x, y)
                if not tree or not tree.frame then
                    return nil
                end
                return tree.frame, x, y
            end,
        },
        ["lib.autocmd"] = {
            Run = function(event, ctx)
                autocmd_calls[#autocmd_calls + 1] = {
                    event = event,
                    ctx = ctx,
                }
                return 1
            end,
        },
        ["lib.luaapi.scopes"] = {
            _v = {},
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

local Options = mock.loadModule("lib.options")
_G.options = Options

local buf = mock.create_buffer(1, "/tmp/mouse.txt", { "one", "two", "three", "four", "five" })
buf.opts.filetype = ""

local win = mock.create_window(1, buf, { wrap = false })
win.cursorx = 1
win.cursory = 1
win.scrollx = 3
win.scrolly = { 1, 0 }
win.textheight = function()
    return 5
end
win.textwidth = function()
    return 20, 5
end
win.cursorSetScreenRow = function(_, row_offset, opts)
    cursor_calls[#cursor_calls + 1] = {
        row_offset = row_offset,
        screen_col = opts and opts.screen_col or nil,
    }
    win.cursory = row_offset + 1
    win.cursorx = opts and opts.screen_col or win.cursorx
end
win.scroll = function(_, dx, dy)
    scroll_calls[#scroll_calls + 1] = { dx = dx, dy = dy }
end

tabpages[1].tree = {
    frame = {
        window = win,
    },
}
tabpages[1].winyoff = 0
tabpages[1].windows = { win }

curtp = 1
curwin = 1
vimmode = "normal"

Options.set("mouse", "nvi", false, win, buf, true)
Options.set("mousemodel", "popup_setpos", false, win, buf, true)
Options.set("mousetime", 500, false, win, buf, true)
Options.set("mousescroll", "ver:3,hor:6", false, win, buf, true)

local Event = mock.loadModule("lib.event")
Event.LoadCommandModule()

Event.ProcessEvent({ "mouse_click", 1, 10, 3 })
assert_eq("left click row offset", cursor_calls[#cursor_calls].row_offset, 2)
assert_eq("left click screen col", cursor_calls[#cursor_calls].screen_col, 8)

Event.ProcessEvent({ "mouse_click", 2, 9, 2 })
assert_eq("right click popup event count", #autocmd_calls, 1)
assert_eq("right click popup event name", autocmd_calls[1].event, "MenuPopup")
assert_eq("right click popup clicks", autocmd_calls[1].ctx.data.clicks, 1)

Event.ProcessEvent({ "mouse_click", 2, 9, 2 })
assert_eq("double right click popup event count", #autocmd_calls, 2)
assert_eq("double right click click-count", autocmd_calls[2].ctx.data.clicks, 2)

Event.ProcessEvent({ "mouse_click", 2, 9, 2 })
assert_eq("mousetime timeout resets count", autocmd_calls[3].ctx.data.clicks, 1)

Options.set("mousemodel", "popup", false, win, buf, true)
local cursor_before_popup_only = #cursor_calls
Event.ProcessEvent({ "mouse_click", 2, 12, 2 })
assert_eq("popup model does not move cursor", #cursor_calls, cursor_before_popup_only)
assert_eq("popup model still runs MenuPopup", autocmd_calls[#autocmd_calls].event, "MenuPopup")

local scroll_before = #scroll_calls
Event.ProcessEvent({ "mouse_scroll", 1, 12, 2 })
assert_eq("scroll down uses mousescroll amount", scroll_calls[scroll_before + 1].dy, 3)

Event.ProcessEvent({ "key", keys.leftShift })
Event.ProcessEvent({ "mouse_scroll", -1, 12, 2 })
assert_eq("shift+scroll uses page amount", scroll_calls[#scroll_calls].dy, -5)
Event.ProcessEvent({ "key_up", keys.leftShift })

Options.set("mouse", "", false, win, buf, true)
local cursor_before_disabled = #cursor_calls
Event.ProcessEvent({ "mouse_click", 1, 10, 3 })
assert_eq("mouse disabled ignores click", #cursor_calls, cursor_before_disabled)

local scopes = mock.loadModule("lib.luaapi.scopes")
assert_eq("v:mouse_win populated", scopes._v.mouse_win, 1)
assert_true("v:mouse_col populated", type(scopes._v.mouse_col) == "number", scopes._v.mouse_col)

print("mouse events runtime tests: OK")
