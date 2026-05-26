local ok_benchmark, Benchmark = pcall(require, "vim.tests.runtime_highlight_benchmark")
if not ok_benchmark then
    Benchmark = require("tests.runtime_highlight_benchmark")
end

local function starts_with(s, prefix)
    return tostring(s or ""):sub(1, #prefix) == prefix
end

local function usage()
    io.write([[
Usage: lua tests/benchmark_runtime_highlighting.lua [options]

Options:
  --runtime-root=<path>  Runtime directory to scan (default: runtime).
  --limit=<n>           Compare only the first n files, for development.
  --max-failures=<n>    Number of failures to print (default: 20).
  --help                Show this help.

This benchmark compares every comparable file under runtime/ against Neovim
syntax groups. Files with no detected filetype or no CCVim syntax file are
reported as skipped.
]])
end

local function parse_args(argv)
    local opts = {
        runtime_root = "runtime",
        max_failures = 20,
    }

    for i = 1, #argv do
        local arg = tostring(argv[i])
        if arg == "--help" or arg == "-h" then
            usage()
            os.exit(0)
        elseif starts_with(arg, "--runtime-root=") then
            opts.runtime_root = arg:sub(16)
        elseif starts_with(arg, "--limit=") then
            opts.max_files = tonumber(arg:sub(9))
        elseif starts_with(arg, "--max-failures=") then
            opts.max_failures = tonumber(arg:sub(16)) or opts.max_failures
        else
            error("Unknown argument: " .. arg)
        end
    end

    return opts
end

local result = Benchmark.run(parse_args(arg or {}))
print(Benchmark.summary(result))

for i = 1, #result.failures do
    local failure = result.failures[i]
    if failure.error then
        print(string.format("FAIL %s: %s", failure.file, failure.error))
    else
        print(string.format(
            "DIFF %s ft=%s mismatch_lines=%d mismatch_cols=%d first_line=%s",
            failure.file,
            tostring(failure.filetype),
            failure.mismatch_lines,
            failure.mismatch_cols,
            tostring(failure.first_line)
        ))
    end
end

if result.failed > 0 then
    os.exit(1)
end
