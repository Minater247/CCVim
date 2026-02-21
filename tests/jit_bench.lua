local function script_dir()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    return src:match("^(.*)/") or "."
end

local function read_all(path)
    local f, err = io.open(path, "rb")
    if not f then
        error("failed to read input: " .. tostring(err))
    end
    local data = f:read("*a")
    f:close()
    return data
end

local function write_all(path, data)
    local f, err = io.open(path, "wb")
    if not f then
        error("failed to write output: " .. tostring(err))
    end
    f:write(data)
    f:close()
end

local function parse_args(argv)
    local opts = {
        input = nil,
        iters = 100,
        warmup = 10,
        script_ctx = nil,
        out = nil,
        gc = true,
    }

    local i = 1
    while i <= #argv do
        local tok = argv[i]
        if tok == "--iters" then
            i = i + 1
            opts.iters = tonumber(argv[i]) or opts.iters
        elseif tok:match("^%-%-iters=") then
            opts.iters = tonumber(tok:match("^%-%-iters=(.+)$")) or opts.iters
        elseif tok == "--warmup" then
            i = i + 1
            opts.warmup = tonumber(argv[i]) or opts.warmup
        elseif tok:match("^%-%-warmup=") then
            opts.warmup = tonumber(tok:match("^%-%-warmup=(.+)$")) or opts.warmup
        elseif tok == "--script-ctx" then
            i = i + 1
            opts.script_ctx = argv[i]
        elseif tok:match("^%-%-script%-ctx=") then
            opts.script_ctx = tok:match("^%-%-script%-ctx=(.+)$")
        elseif tok == "--out" or tok == "-o" then
            i = i + 1
            opts.out = argv[i]
        elseif tok:match("^%-%-out=") then
            opts.out = tok:match("^%-%-out=(.+)$")
        elseif tok == "--no-gc" then
            opts.gc = false
        elseif tok:sub(1, 2) == "--" then
            io.stderr:write("unknown argument: " .. tostring(tok) .. "\n")
            os.exit(2)
        else
            if not opts.input then
                opts.input = tok
            else
                io.stderr:write("unexpected positional argument: " .. tostring(tok) .. "\n")
                os.exit(2)
            end
        end
        i = i + 1
    end

    if not opts.input then
        io.stderr:write("usage: lua vim/tests/jit_bench.lua path/to/file.vim [--iters N] [--warmup N] [--script-ctx CTX] [-o compiled.lua]\n")
        os.exit(2)
    end

    opts.iters = math.max(1, math.floor(opts.iters))
    opts.warmup = math.max(0, math.floor(opts.warmup))
    opts.script_ctx = opts.script_ctx or opts.input

    return opts
end

local function bench_case(name, iters, warmup, fn, with_gc)
    for _ = 1, warmup do
        fn()
    end

    if with_gc then
        collectgarbage("collect")
    end

    local t0 = os.clock()
    for _ = 1, iters do
        fn()
    end
    local dt = os.clock() - t0

    return {
        name = name,
        iters = iters,
        total = dt,
        us = (dt / iters) * 1e6,
        ops = iters / dt,
    }
end

local function print_result(r)
    print(string.format("%-28s total=%8.4fs iter=%9.2fus ops/s=%11.1f", r.name, r.total, r.us, r.ops))
end

local function main(argv)
    local opts = parse_args(argv)
    local input_path = opts.input
    local script = read_all(input_path)

    local mocks_path = script_dir() .. "/test_mocks.lua"
    local MockEnv = dofile(mocks_path)
    local mock = MockEnv.setup({})

    local Compiler = mock.loadModule("lib.excmd.compiler")
    local Runtime = mock.loadModule("lib.excmd.runtime")
    local Scopes = mock.loadModule("lib.luaapi.scopes")

    local durable = Runtime.CaptureDurableScriptState({ script_ctx = opts.script_ctx }) or { s = {}, funcs = {} }
    durable.g = durable.g or Scopes._g

    local code, cerr = Compiler.compile_script(script, { state = Runtime.MakeRuntimeState(durable) })
    if not code then
        error("compile failed: " .. tostring(cerr))
    end

    if opts.out and opts.out ~= "" then
        write_all(opts.out, code)
    end

    local chunk, lerr = load(code, "jit_bench_compiled", "t", _G)
    if not chunk then
        error("load failed: " .. tostring(lerr))
    end
    local compiled_fn = chunk()

    local results = {}

    results[#results + 1] = bench_case("compile_only", opts.iters, opts.warmup, function()
        local state = Runtime.MakeRuntimeState(durable)
        local ok_code, err = Compiler.compile_script(script, { state = state })
        if not ok_code then
            error(err)
        end
    end, opts.gc)

    results[#results + 1] = bench_case("compile_plus_load", opts.iters, opts.warmup, function()
        local state = Runtime.MakeRuntimeState(durable)
        local one_code, err = Compiler.compile_script(script, { state = state })
        if not one_code then
            error(err)
        end
        local one_chunk, one_lerr = load(one_code, "jit_bench_once", "t", _G)
        if not one_chunk then
            error(one_lerr)
        end
        one_chunk()
    end, opts.gc)

    results[#results + 1] = bench_case("runtime_run_end_to_end", opts.iters, opts.warmup, function()
        local ok = Runtime.run(script, { durable = durable, script_ctx = opts.script_ctx })
        if not ok then
            error("runtime.run failed")
        end
    end, opts.gc)

    results[#results + 1] = bench_case("precompiled_exec_fresh", opts.iters, opts.warmup, function()
        local state = Runtime.MakeRuntimeState(durable)
        local rt = Runtime.new(state)
        local ok, rv = pcall(function()
            return compiled_fn(state, rt)
        end)
        if not ok then
            error(rv)
        end
    end, opts.gc)

    do
        local state = Runtime.MakeRuntimeState(durable)
        local rt = Runtime.new(state)
        results[#results + 1] = bench_case("precompiled_exec_reuse", opts.iters, opts.warmup, function()
            local ok, rv = pcall(function()
                return compiled_fn(state, rt)
            end)
            if not ok then
                error(rv)
            end
        end, opts.gc)
    end

    print("Vimscript JIT benchmark")
    print("input=" .. tostring(input_path))
    print("script_ctx=" .. tostring(opts.script_ctx))
    print("iters=" .. tostring(opts.iters) .. " warmup=" .. tostring(opts.warmup) .. " gc=" .. tostring(opts.gc))
    print("")

    for i = 1, #results do
        print_result(results[i])
    end

    local e2e_us
    local pre_us
    for i = 1, #results do
        if results[i].name == "runtime_run_end_to_end" then
            e2e_us = results[i].us
        elseif results[i].name == "precompiled_exec_fresh" then
            pre_us = results[i].us
        end
    end

    if e2e_us and pre_us and pre_us > 0 then
        print("")
        print(string.format("speedup(precompiled_exec_fresh vs runtime_run_end_to_end)=x%.2f", e2e_us / pre_us))
    end
end

main(arg or {})
