-- jit_bench_all.lua: Run jit_bench.lua on all .vim files in runtime, print aggregate stats
local function collect_vim_files(dir)
    local files = {}
    local p = io.popen('find "'..dir..'" -type f -name "*.vim"')
    if p then
        for file in p:lines() do
            files[#files+1] = file
        end
        p:close()
    end
    return files
end

local function parse_speedup(output)
    -- Match: speedup(precompiled_exec_fresh vs runtime_run_end_to_end)=x2.93
    local s = output:match("speedup%(.-%)=x([%d%.]+)")
    return tonumber(s)
end

local function median(t)
    table.sort(t)
    local n = #t
    if n == 0 then return 0 end
    if n % 2 == 1 then return t[(n+1)//2] end
    return (t[n//2] + t[n//2+1]) / 2
end

local runtime_dir = 'vim/runtime'
local bench_script = 'vim/tests/jit_bench.lua'
local files = collect_vim_files(runtime_dir)

local speedups = {}

for _, file in ipairs(files) do
    local cmd = string.format('lua "%s" "%s" --iters 100 --warmup 10 2>&1', bench_script, file)
    local f = io.popen(cmd)
    local out = f:read('*a')
    f:close()
    local speed = parse_speedup(out)
    if speed then
        speedups[#speedups+1] = speed
        print(string.format('%-40s speedup=x%.2f', file, speed))
    else
        print(string.format('%-40s (no speedup found)', file))
    end
end

print('\nAggregate JIT speedup stats:')
print(string.format('  Files measured: %d', #speedups))
if #speedups > 0 then
    print(string.format('  Median speedup: x%.2f', median(speedups)))
    print(string.format('  Min speedup:    x%.2f', math.min(table.unpack(speedups))))
    print(string.format('  Max speedup:    x%.2f', math.max(table.unpack(speedups))))
end
