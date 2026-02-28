-- vim/tests/test_mock_env.lua
-- Test that the mock environment sets up correctly

local MockEnv = require("vim.tests.test_mocks")

-- Setup the mock environment
local mock = MockEnv.setup()

-- Test that globals are set
assert(_G.LOG_DEBUG ~= nil, "LOG_DEBUG should be set")
assert(_G.LOG_ERROR ~= nil, "LOG_ERROR should be set")
assert(_G.LOG_INTERNAL ~= nil, "LOG_INTERNAL should be set")
assert(_G.loadModule ~= nil, "loadModule should be set")
assert(_G.buffers ~= nil, "buffers should be set")
assert(_G.windows ~= nil, "windows should be set")
assert(_G.tabpages ~= nil, "tabpages should be set")
assert(_G.fs ~= nil, "fs should be set")
assert(_G.colors ~= nil, "colors should be set")
assert(_G.term ~= nil, "term should be set")

print("✓ All basic globals set")

-- Test helper methods
local buf1 = mock.create_buffer(1, "/tmp/a", { "line1", "line2" })
assert(buf1.bufnr == 1, "Buffer should have correct bufnr")
assert(buf1.name == "/tmp/a", "Buffer should have correct name")
assert(#buf1.lines == 2, "Buffer should have correct number of lines")
assert(_G.buffers[1] == buf1, "Buffer should be accessible via _G.buffers")

local buf2 = mock.create_buffer(2, "/tmp/b")
assert(_G.buffers[2] == buf2, "Second buffer should be accessible")

local win1 = mock.create_window(1, buf1)
assert(win1.buffer == buf1, "Window should reference buffer")
assert(_G.windows[1] == win1, "Window should be accessible via _G.windows")

print("✓ Helper methods work")

-- Test metatable interfaces
mock.buffers[3] = { bufnr = 3, name = "/tmp/c", lines = { "" }, opts = {} }
assert(_G.buffers[3] ~= nil, "Setting via metatable should update _G.buffers")
assert(mock.buffers[3].bufnr == 3, "Reading via metatable should work")

print("✓ Metatable interfaces work")

-- Test that loadModule works
local package_module = mock.loadModule("lib.luaapi.package")
assert(package_module ~= nil, "Should be able to load vim.lib.luaapi.package")
print("✓ loadModule works")

-- Test that module is cached
local package_module2 = mock.loadModule("lib.luaapi.package")
assert(package_module == package_module2, "Module should be cached")
print("✓ Module caching works")

print("\nAll tests passed!")
