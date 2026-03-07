# Test Suite

Integration tests for the CCVim editor.

## Architecture

**Test Harness:** Each suite runs in an isolated mock CraftOS environment (`tests/test_mocks.lua`) that provides CraftOS primitives (`term`, `fs`, `os`, `keys`, etc.).

The mock environment intentionally avoids no-op stubs. If a test calls an API in a way which causes issues, it must fail immediately rather than silently passing with broken behavior. A stub creates a gap in the testing harness where such a failure may slip through.

**Backends:**
- `lua_editor` (default): Loads the full CCVim codebase through the mock harness. Tests actual editor behavior.
- `headless_nvim`: Runs equivalent tests against `nvim --headless` for API parity verification. Only works for tests that don't depend on CCVim-specific internals.

## Test Philosophy

**Neovim is the reference implementation.** All tests should pass against `headless_nvim` backend when available. If a test fails on `headless_nvim`, the text expectations are flawed in some way, and the behavior of CCVim should be updated to match. If you believe there is an exception to this, that likely constitutes a bug report on the official Neovim repository.

When tests fail on `lua_editor` but pass on `headless_nvim`, this indicates a divergence in CCVim that should be fixed to match Neovim's behavior. The test suite serves as both validation and a specification of correct API behavior.

## Directory Structure

```
tests/
├── runall.sh                # Wrapper script
└── new/
    ├── run.lua              # Test runner entrypoint
    ├── README.md
    ├── framework/
    │   ├── assert.lua       # Test assertions
    │   ├── runner.lua       # Suite discovery and execution
    │   └── backends/
    │       ├── lua_editor.lua    # CCVim mock backend
    │       └── headless_nvim.lua # Real Neovim backend (WIP)
    └── suites/
        ├── api/             # vim.api.* function tests
        │   ├── vim_list_slice_spec.lua
        │   ├── vim_islist_spec.lua
        │   └── ...
        └── runtime/         # Editor behavior and integration tests
            ├── nvim_redraw_api_spec.lua
            └── ...
```

The `suites/` directory may be expanded as test coverage increases.

## Running

From the repository root (`vim/`):

```sh
./tests/runall.sh
```

Or directly with Lua from the repository root:

```sh
lua tests/new/run.lua
```

Run specific suites:

```sh
lua tests/new/run.lua tests/new/suites/api/vim_list_slice_spec.lua
```

Use the Neovim parity backend (for supported tests):

```sh
lua tests/new/run.lua --backend=headless_nvim
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

        local result, err = backend:eval_lua("vim.fn.abs(-5)")
        Assert.truthy("abs(-5) eval", result ~= nil, err)
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
- `backend:eval_lua(lua_expr)` - backend-independent translation layer; evaluates a Lua expression and returns the result as a Lua value (decoded from JSON) and error
- `backend:eval_vimscript(vimscript_expr)` - backend-independent Vimscript expression evaluator; returns the result as a Lua value and error
- `backend:eval_block(lua_code)` - executes a Lua code block and returns the block's explicit `return` value (or `nil`) and error
- `backend.EMPTY_DICT_MT` - metatable marker used to distinguish empty dictionaries `{}` from empty arrays `[]`; empty dicts have this metatable, empty arrays don't
- `backend:is_list(tbl)` - returns true if the table is an array (sequential integer keys starting from 1)
- `backend:is_dict(tbl)` - returns true if the table is a dictionary (has string keys, or is marked as empty dict)
- `backend:is_empty_dict(tbl)` - returns true if the table has the `EMPTY_DICT_MT` metatable (distinguishes `{}` from `[]`)

Example:

```lua
local result, err = backend:eval_vimscript("abs(-5)")
Assert.truthy("abs(-5) eval", result ~= nil, err)
Assert.eq("abs(-5)", result, 5)
```

Lua-editor-specific helpers exist for deep integration tests that need direct mock access:
- `backend.mock.loadModule(name)`
- `backend.mock.create_buffer(...)`
- `backend.mock.create_window(...)`

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
