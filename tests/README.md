# Test Suite

Integration tests for the CCVim editor.

## Architecture

**Test Harness:** Each suite runs in an isolated mock CraftOS environment (`tests/test_mocks.lua`) that provides CraftOS primitives (`term`, `fs`, `os`, `keys`, etc.).

The mock environment intentionally avoids no-op stubs. If a test calls an API in a way which causes issues, it must fail immediately rather than silently passing with broken behavior. A stub creates a gap in the testing harness where such a failure may slip through.

**Backends:**
- `lua_editor` (default): Loads the full CCVim codebase through the mock harness. Tests actual editor behavior.
- `headless_nvim`: Runs equivalent tests against `nvim --headless` for API parity verification. Only works for tests that don't depend on CCVim-specific internals.
- `parity`: Runs enabled suites first on headless Neovim and then in the Lua editor, comparing their returned data. The two phases keep native process access outside the CraftOS mock environment.

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

Run dual-engine comparison suites:

```sh
lua tests/run.lua --backend=parity
```

Run benchmark suites:

```sh
lua tests/run.lua --benchmarks
```

Run the runtime-wide highlighting parity benchmark directly:

```sh
lua tests/benchmark_runtime_highlighting.lua
```

## Writing Tests

Each test suite is a Lua file returning a table:

```lua
return {
    id = "category.test_name",
    description = "What this test validates",
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

Dual-engine suites return normalized comparison data and explicitly select only the parity runner:

```lua
return {
    id = "category.direct_parity",
    description = "Compares both engines; single-engine backends are disabled because neither can compare alone.", -- luacheck: ignore 631
    supports = { lua_editor = false, headless_nvim = false, parity = true },
    run = function(ctx)
        return ctx.assert.eval_block(ctx.backend, "comparison data", "return { vim.fn.mode() }")
    end,
}
```
