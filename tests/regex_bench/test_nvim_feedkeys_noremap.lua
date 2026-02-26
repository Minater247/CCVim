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

print("nvim_feedkeys noremap tests: OK")
