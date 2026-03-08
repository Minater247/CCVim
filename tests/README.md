# Test Suite

Integration tests for the CCVim editor.

## Architecture

**Test Harness:** Each suite runs in an isolated mock CraftOS environment (`tests/test_mocks.lua`) that provides CraftOS primitives (`term`, `fs`, `os`, `keys`, etc.).

The mock environment intentionally avoids no-op stubs. If a test calls an API in a way which causes issues, it must fail immediately rather than silently passing with broken behavior. A stub creates a gap in the testing harness where such a failure may slip through.

**Backends:**
- `lua_editor` (default): Loads the full CCVim codebase through the mock harness. Tests actual editor behavior.
- `headless_nvim`: Runs equivalent tests against `nvim --headless` for API parity verification. Only works for tests that don't depend on CCVim-specific internals.

## Test Philosophy

**Neovim is the reference implementation.** All tests should pass against `headless_nvim` when that backend is supported. If a test passes on `headless_nvim` and fails on `lua_editor`, that exposes a CCVim divergence.

## Directory Structure

```text
tests/
├── README.md
├── framework/
│   ├── assert.lua
│   ├── runner.lua
│   └── backends/
│       ├── lua_editor.lua
│       └── headless_nvim.lua
├── suites/
│   ├── api/
│   └── runtime/
├── old/
├── in_editor/
├── run.lua
├── runall.sh
└── test_mocks.lua
```

## Running

From the repository root (`vim/`):

```sh
./tests/runall.sh
```

Or directly:

```sh
lua tests/run.lua
```

Run specific suites:

```sh
lua tests/run.lua tests/suites/api/vim_list_slice_spec.lua
```

Use the Neovim parity backend:

```sh
lua tests/run.lua --backend=headless_nvim
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

Useful helpers:
- `backend:eval_lua(...)`
- `backend:eval_vimscript(...)`
- `backend:eval_block(...)`
- `Assert.eq(...)`
- `Assert.truthy(...)`
- `Assert.table_eq(...)`

For CCVim-internal runtime tests, `backend.mock` remains available when there is no sensible Neovim parity path.
