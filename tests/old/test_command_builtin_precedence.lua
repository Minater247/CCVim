local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    module_stubs = {
        ["lib.event"] = {
            StartTimer = function() return 1 end,
            CancelTimer = function() end,
        },
        ["lib.excmd.exmsg"] = {
            echo = function() end,
            echon = function() end,
            echomsg = function() end,
            echoerr = function() end,
        },
    },
})

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local buf = mock.create_buffer(1, "/tmp/test_command_builtin_precedence.vim", { "" }, {})
local win = mock.create_window(1, buf, {})
mock.create_tabpage(1, { win }, {})
curtp = 1
curwin = 1
vimmode = "normal"
options = options or {}
options.get = options.get or function(name)
    if name == "timeout" then return false end
    if name == "timeoutlen" then return 1000 end
    return nil
end

local Command = mock.loadModule("lib.command")
local Key = mock.loadModule("lib.key")

local function seq(lhs)
    return Key.strtoseq(lhs)
end

local function press(lhs)
    local keys = seq(lhs)
    for i = 1, #keys do
        Command.HandleKey(keys[i])
    end
end

local function clear_all_user_maps()
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
end

clear_all_user_maps()

local last
local raw_count = 0
Command.emit_raw = function()
    raw_count = raw_count + 1
end

-- user mapping shadows builtin
Command.nmap_builtin_callback(seq("x"), function()
    last = "builtin-x"
end)
Command.nmap_callback(seq("x"), function()
    last = "user-x"
end)
last = nil
press("x")
assert_eq("user mapping shadows builtin", last, "user-x")

-- unmap restores builtin
Command.unmap_keys("normal", seq("x"))
last = nil
press("x")
assert_eq("unmap restores builtin", last, "builtin-x")

-- mapclear preserves builtins
Command.nmap_callback(seq("y"), function()
    last = "user-y"
end)
Command.clear_mappings("normal")
last = nil
press("x")
assert_eq("mapclear preserves builtin mapping", last, "builtin-x")
raw_count = 0
press("y")
assert_eq("mapclear removed user mapping", raw_count, 1)

-- buffer-local user shadow + clear behavior
Command.nmap_builtin_callback(seq("z"), function()
    last = "builtin-z"
end)
Command.nmap_callback(seq("z"), function()
    last = "global-z"
end)
Command.nmap_callback(seq("z"), function()
    last = "local-z"
end, { buffer_local = true })

last = nil
press("z")
assert_eq("buffer-local user shadows global user", last, "local-z")

Command.clear_mappings("normal", { buffer_local = true })
last = nil
press("z")
assert_eq("clearing local user restores global user", last, "global-z")

Command.unmap_keys("normal", seq("z"))
last = nil
press("z")
assert_eq("clearing global user restores builtin", last, "builtin-z")

-- builtin operator survives unrelated user unmap/mapclear
local op_calls = 0
local op_motion = nil
Command.nmap_builtin_operator_with_motions(seq("d"), function(_, motion_name)
    op_calls = op_calls + 1
    op_motion = motion_name
end, {
    word = seq("w"),
})

Command.nmap_callback(seq("q"), function() end)
Command.unmap_keys("normal", seq("q"))
press("dw")
assert_eq("builtin operator survives unrelated unmap", op_calls, 1)
assert_eq("builtin operator motion name after unmap", op_motion, "word")

Command.nmap_callback(seq("r"), function() end)
Command.clear_mappings("normal")
press("dw")
assert_eq("builtin operator survives mapclear", op_calls, 2)
assert_eq("builtin operator motion name after mapclear", op_motion, "word")

print("command builtin precedence tests: OK")
