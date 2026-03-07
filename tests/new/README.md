# Test Suite

Integration tests for the CCVim editor.

## Architecture

**Test Harness:** Each suite runs in an isolated mock CraftOS environment (`tests/test_mocks.lua`) that provides CraftOS primitives (`term`, `fs`, `os`, `keys`, etc.).

The mock environment intentionally avoids no-op stubs. If a test calls an API in a way which causes issues, it must fail immediately rather than silently passing with broken behavior. A stub creates a gap in the testing harness where such a failure may slip through.

**Backends:**
- `lua_editor` (default): Loads the full CCVim codebase through the mock harness. Tests actual editor behavior.
- `headless_nvim`: Runs equivalent tests against `nvim --headless` for API parity verification. Only works for tests that don't depend on CCVim-specific internals.

## Directory Structure

```
tests/new/
├── run.lua                  # Test runner entrypoint
├── runall.sh                # Wrapper script
├── README.md
├── framework/
│   ├── assert.lua           # Test assertions
│   ├── runner.lua           # Suite discovery and execution
│   └── backends/
│       ├── lua_editor.lua   # CCVim mock backend
│       └── headless_nvim.lua # Real Neovim backend (WIP)
└── suites/
    ├── api/                 # vim.api.* function tests
    │   ├── vim_list_slice_spec.lua
    │   ├── vim_islist_spec.lua
    │   └── ...
    └── runtime/             # Editor behavior and integration tests
        ├── nvim_redraw_api_spec.lua
        └── ...
```

The `suites/` directory may be expanded as test coverage increases.

## Running

From the workspace root:

```sh
./vim/tests/runall.sh
```

Or directly with Lua from the workspace root:

```sh
lua vim/tests/new/run.lua
```

Run specific suites:

```sh
lua vim/tests/new/run.lua vim/tests/new/suites/api/vim_list_slice_spec.lua
```

Use the Neovim parity backend (for supported tests):

```sh
lua vim/tests/new/run.lua --backend=headless_nvim
```

## Writing Tests

Each test suite is a Lua file returning a table:

```lua
return {
    id = "category.test_name",
    description = "What this test validates",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        
        -- Test code here
        local result = backend:api_build().vim.fn.abs(-5)
        Assert.eq("abs(-5)", result, 5)
    end,
}
```

**Assertions available:**
- `Assert.eq(label, got, want)` - exact equality
- `Assert.truthy(label, cond, detail)` - check truthiness
- `Assert.table_eq(label, got, want)` - array equality (length + elements)
- `Assert.contains_pair(label, rows, key, value)` - check for key-value pair in list

**Backend interface:**
- `backend.mock.loadModule(name)` - load a CCVim module
- `backend.mock.create_buffer(...)` - create mock buffer
- `backend.mock.create_window(...)` - create mock window
- `backend:api_build()` - get the full `vim` API table
- `backend:cleanup()` - teardown (called automatically)

## Mock Environment

The test harness (`tests/test_mocks.lua`) provides:

- **CraftOS APIs:** Full `term`, `fs`, `os`, `shell`, `colors`, `keys`, `textutils` implementations using real host filesystem operations under `/tmp/nvim-test-<TIMESTAMP>-<PID>`
- **Editor globals:** `windows`, `buffers`, `tabpages`, `curwin`, `curtp`, `need_redraw`, `what_redraw`, `vimmode`
- **Logging stubs:** `LOG_DEBUG`, `LOG_ERROR`, `LOG_INTERNAL` (silent in tests)

Key differences from real runtime:
- Terminal I/O is captured (no actual screen rendering)
- Filesystem operations use temporary directories
- `os.sleep()` returns immediately (non-blocking)
- Event loop (`os.pullEvent`) returns dummy events to prevent hangs

## Notes

- Each test runs with a fresh mock environment to prevent context leakage between tests.

