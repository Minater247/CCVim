local MockEnv = require("vim.tests.test_mocks")

local mock = MockEnv.setup({
    vimmode = "insert",
})

local Command = mock.loadModule("lib.command")
local api = mock.loadModule("lib.luaapi.api")
local Key = mock.loadModule("lib.key")

local function assert_eq(label, got, want)
    if got ~= want then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(want), tostring(got)))
    end
end

local buf = mock.create_buffer(1, "/tmp/nvim-feedkeys-noremap-test", { "" })
buf.refcount = 1
local win = {
    winnr = 1,
    buffer = buf,
}
windows[1] = win
curwin = 1
tabpages[1].windows = { win }

local raw = {}
Command.emit_raw = function(seq)
    for i = 1, #seq do
        raw[#raw + 1] = seq[i]:emittable()
    end
end

local callback_hits = 0
Command.imap_callback(Key.strtoseq("<CR>"), function()
    callback_hits = callback_hits + 1
end)

local cr = api.nvim_replace_termcodes("<CR>", true, false, true)

raw = {}
api.nvim_feedkeys(cr, "mx", true)
assert_eq("remap mode triggers callback mapping", callback_hits, 1)
assert_eq("remap mode does not emit raw key", #raw, 0)

raw = {}
api.nvim_feedkeys(cr, "nx", true)
assert_eq("noremap mode skips callback mapping", callback_hits, 1)
assert_eq("noremap mode emits one raw key", #raw, 1)
assert_eq("noremap mode emits raw enter", raw[1], "\n")

-- Normal mode: noremap should bypass user mappings but still run builtin mappings.
vimmode = "normal"

local user_hits = 0
local builtin_hits = 0
Command.nmap_callback(Key.strtoseq("h"), function()
    user_hits = user_hits + 1
end)
Command.nmap_builtin_callback(Key.strtoseq("h"), function()
    builtin_hits = builtin_hits + 1
end)

raw = {}
api.nvim_feedkeys("h", "mx", true)
assert_eq("normal remap prefers user mapping", user_hits, 1)
assert_eq("normal remap does not run builtin mapping", builtin_hits, 0)
assert_eq("normal remap emits no raw", #raw, 0)

raw = {}
api.nvim_feedkeys("h", "nx", true)
assert_eq("normal noremap skips user mapping", user_hits, 1)
assert_eq("normal noremap runs builtin mapping", builtin_hits, 1)
assert_eq("normal noremap emits no raw when builtin consumed key", #raw, 0)

-- Operator motions: noremap should still execute builtin operator motions.
options = options or {}
options.get = options.get or function(name)
    if name == "timeout" then return false end
    if name == "timeoutlen" then return 1000 end
    return nil
end

local user_d_hits = 0
local builtin_op_hits = 0
local builtin_motion = nil

Command.nmap_callback(Key.strtoseq("d"), function()
    user_d_hits = user_d_hits + 1
end)

Command.nmap_builtin_operator_with_motions(Key.strtoseq("d"), function(_, motion_name)
    builtin_op_hits = builtin_op_hits + 1
    builtin_motion = motion_name
end, {
    word = Key.strtoseq("w"),
})

raw = {}
api.nvim_feedkeys("dw", "mx", true)
assert_eq("operator remap uses user map on operator key", user_d_hits, 1)
assert_eq("operator remap does not run builtin operator", builtin_op_hits, 0)

raw = {}
api.nvim_feedkeys("dw", "nx", true)
assert_eq("operator noremap skips user operator map", user_d_hits, 1)
assert_eq("operator noremap runs builtin operator", builtin_op_hits, 1)
assert_eq("operator noremap motion name", builtin_motion, "word")

print("nvim_feedkeys noremap tests: OK")
