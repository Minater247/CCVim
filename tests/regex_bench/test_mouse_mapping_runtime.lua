local MockEnv = require("vim.tests.test_mocks")

local epochs = { 1000, 1100, 1200, 1300, 1400, 1500 }
local epoch_idx = 0

local cursor_calls = 0
local scroll_calls = 0
local popup_calls = 0

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
        ["lib.luaapi.on_key"] = {
            dispatch = function() return false end,
        },
        ["lib.excmd.exmsg"] = {
            Finalize = function() end,
            echoerr = function() end,
            echo = function() end,
            echon = function() end,
            echomsg = function() end,
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
            Run = function(event_name)
                if event_name == "MenuPopup" then
                    popup_calls = popup_calls + 1
                end
                return 1
            end,
        },
        ["lib.popupmenu"] = {
            visible = function() return false end,
            handle_key = function() return false end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local Options = mock.loadModule("lib.options")
_G.options = Options

local buf = mock.create_buffer(1, "/tmp/mouse-mapping.txt", { "one", "two", "three", "four", "five" })
local win = mock.create_window(1, buf, { wrap = false })
win.cursorx = 1
win.cursory = 1
win.scrollx = 1
win.textheight = function()
    return 5
end
win.textwidth = function()
    return 20, 1
end
win.cursorSetScreenRow = function(_, row_offset, opts)
    cursor_calls = cursor_calls + 1
    win.cursory = row_offset + 1
    win.cursorx = opts and opts.screen_col or win.cursorx
end
win.scroll = function(_, _, _)
    scroll_calls = scroll_calls + 1
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

local Command = mock.loadModule("lib.command")
local Key = mock.loadModule("lib.key")

local left_hits = 0
local right_hits = 0
local dbl_right_hits = 0
local drag_hits = 0
local release_hits = 0
local wheel_up_hits = 0
local shifted_wheel_down_hits = 0

Command.clear_mappings({
    "normal",
    "visual",
    "select",
    "operator",
    "insert",
    "lang",
    "cmdline",
    "terminal",
})

Command.map_callback("normal", Key.strtoseq("<LeftMouse>"), function()
    left_hits = left_hits + 1
end)
Command.map_callback("normal", Key.strtoseq("<RightMouse>"), function()
    right_hits = right_hits + 1
end)
Command.map_callback("normal", Key.strtoseq("<2-RightMouse>"), function()
    dbl_right_hits = dbl_right_hits + 1
end)
Command.map_callback("normal", Key.strtoseq("<LeftDrag>"), function()
    drag_hits = drag_hits + 1
end)
Command.map_callback("normal", Key.strtoseq("<LeftRelease>"), function()
    release_hits = release_hits + 1
end)
Command.map_callback("normal", Key.strtoseq("<ScrollWheelUp>"), function()
    wheel_up_hits = wheel_up_hits + 1
end)
Command.map_callback("normal", Key.strtoseq("<S-ScrollWheelDown>"), function()
    shifted_wheel_down_hits = shifted_wheel_down_hits + 1
end)

Event.ProcessEvent({ "mouse_click", 1, 8, 3 })
assert_eq("left click mapping executed", left_hits, 1)
assert_eq("mapped left click suppresses default cursor move", cursor_calls, 0)

Event.ProcessEvent({ "mouse_click", 2, 8, 3 })
Event.ProcessEvent({ "mouse_click", 2, 8, 3 })
assert_eq("right click mapping executed", right_hits, 1)
assert_eq("double right click mapping executed", dbl_right_hits, 1)
assert_eq("mapped double right click suppresses popup", popup_calls, 0)

Event.ProcessEvent({ "mouse_drag", 1, 9, 3 })
assert_eq("left drag mapping executed", drag_hits, 1)
assert_eq("mapped left drag suppresses default cursor move", cursor_calls, 0)

Event.ProcessEvent({ "mouse_up", 1, 9, 3 })
assert_eq("left release mapping executed", release_hits, 1)

Event.ProcessEvent({ "mouse_scroll", -1, 8, 3 })
assert_eq("scroll-up mapping executed", wheel_up_hits, 1)
assert_eq("mapped scroll-up suppresses default scroll", scroll_calls, 0)

Event.ProcessEvent({ "key", keys.leftShift })
Event.ProcessEvent({ "mouse_scroll", 1, 8, 3 })
Event.ProcessEvent({ "key_up", keys.leftShift })
assert_eq("shifted scroll-down mapping executed", shifted_wheel_down_hits, 1)
assert_eq("mapped shifted scroll suppresses default scroll", scroll_calls, 0)

local emitted = Key.replace_termcodes("<LeftMouse>", true, true)
Command.execute_normal_keys(Key.strtoseq(emitted), { remap = true })
assert_eq("script-emitted <LeftMouse> triggers mapping", left_hits, 2)

print("mouse mapping runtime tests: OK")
