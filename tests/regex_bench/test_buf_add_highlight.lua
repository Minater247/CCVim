local MockEnv = require("vim.tests.test_mocks")

-- Minimal environment; we don't need most of the stubs used by the
-- extmark/sign rendering tests.
local mock = MockEnv.setup()
local api = mock.loadModule("lib.luaapi.api")

-- create a buffer we'll operate on
local buf = mock.create_buffer(1, "/tmp/highlight-test", {"first", "second"})
buf.refcount = 0

-- ensure namespace creation works
local ns1 = api.nvim_create_namespace("test1")
assert(ns1 > 0, "namespace should be positive")

-- add a highlight into that namespace and verify via extmarks
local ret = api.nvim_buf_add_highlight(buf.bufnr, ns1, "ErrorMsg", 0, 1, 2)
assert(ret == ns1, "returned ns_id must match")

local full_end = { #buf.lines - 1, -1 }
local ext = api.nvim_buf_get_extmarks(buf.bufnr, ns1, { 0, 0 }, full_end, { details = true })
assert(#ext == 1, "one extmark in namespace")
assert(ext[1][4].hl_group == "ErrorMsg")
assert(ext[1][4].end_col == 2)

-- ns_id = 0 should allocate a new namespace and return it
local ns2 = api.nvim_buf_add_highlight(buf.bufnr, 0, "Search", 0, 0, 1)
assert(ns2 > 0 and ns2 ~= ns1, "new namespace allocated")
local ext2 = api.nvim_buf_get_extmarks(buf.bufnr, ns2, { 0, 0 }, full_end, { details = true })
assert(#ext2 == 1 and ext2[1][4].hl_group == "Search")

-- empty hl_group returns namespace but does not add a mark
local ns3 = api.nvim_buf_add_highlight(buf.bufnr, 0, "", 0, 0, 1)
assert(ns3 > 0)
local ext3 = api.nvim_buf_get_extmarks(buf.bufnr, ns3, { 0, 0 }, full_end, {})
assert(#ext3 == 0, "no extmarks when hl_group is empty")

-- adding to ns_id -1 should create an ungrouped mark visible via -1 query
local before = api.nvim_buf_get_extmarks(buf.bufnr, -1, { 0, 0 }, full_end, {})
local count_before = #before
api.nvim_buf_add_highlight(buf.bufnr, -1, "WarningMsg", 1, 0, -1)
local after = api.nvim_buf_get_extmarks(buf.bufnr, -1, { 0, 0 }, full_end, {})
assert(#after == count_before + 1, "ungrouped highlights show up in -1 query")

print("test_buf_add_highlight.lua: PASS")
