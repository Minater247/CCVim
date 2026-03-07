local function script_dir()
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        src = src:sub(2)
    end
    return src:match("^(.*)/") or "."
end

local function join(a, b)
    if a:sub(-1) == "/" then
        return a .. b
    end
    return a .. "/" .. b
end

local function parse_args(argv)
    local opts = {
        scale = 1,
        engine = nil,
        compare = nil,
    }

    for i = 1, #argv do
        local arg = argv[i]
        local k, v = arg:match("^%-%-(%w+)%=(.+)$")
        if k == "engine" then
            opts.engine = v
        elseif k == "compare" then
            opts.compare = v
        elseif k == "scale" then
            opts.scale = tonumber(v) or 1
            if opts.scale <= 0 then opts.scale = 1 end
        else
            io.stderr:write("Unknown arg: " .. tostring(arg) .. "\n")
            os.exit(2)
        end
    end

    local dir = script_dir()
    opts.engine = opts.engine or join(dir, "../../lib/excmd/vim_regex.lua")

    return opts
end

local function load_engine(path)
    local chunk, lerr = loadfile(path)
    if not chunk then
        error("Failed to load engine from " .. tostring(path) .. ": " .. tostring(lerr))
    end

    local ok, mod = pcall(chunk)
    if not ok then
        error("Engine init failed for " .. tostring(path) .. ": " .. tostring(mod))
    end

    if type(mod) ~= "table" or type(mod.compile) ~= "function" or type(mod.find_compiled) ~= "function" then
        error("Engine at " .. tostring(path) .. " does not expose expected API")
    end

    return mod
end

local function case_definitions(scale)
    local long_text = ("noise token1234 more noise token9876 end "):rep(120)
    local mix_text = ("aaaaa foo zzzzzz bar zzz baz zzz qux "):rep(96)
    local grouped_text = ("foobaz x barbaz y zz "):rep(150)

    local function scaled(n)
        return math.max(1, math.floor(n * scale))
    end

    return {
        {
            name = "find_compiled_case_sensitive",
            iters = scaled(120000),
            setup = function(R)
                local compiled = assert(select(1, R.compile("\\<token\\d\\+\\>")))
                return function()
                    return R.find_compiled(long_text, compiled, true)
                end
            end,
        },
        {
            name = "find_compiled_ignore_case",
            iters = scaled(90000),
            setup = function(R)
                local compiled = assert(select(1, R.compile("\\<Token\\d\\+\\>")))
                return function()
                    return R.find_compiled(long_text, compiled, false)
                end
            end,
        },
        {
            name = "find_compile_each_call",
            iters = scaled(50000),
            setup = function(R)
                return function()
                    return R.find(mix_text, "foo\\|bar\\|baz", true)
                end
            end,
        },
        {
            name = "group_alternation_find",
            iters = scaled(70000),
            setup = function(R)
                local compiled = assert(select(1, R.compile("\\(foo\\|bar\\)baz")))
                return function()
                    return R.find_compiled(grouped_text, compiled, true)
                end
            end,
        },
        {
            name = "compile_cached_hot",
            iters = scaled(120000),
            setup = function(R)
                if type(R.clear_cache) == "function" then R.clear_cache() end
                return function()
                    return R.compile("\\<Token\\d\\+\\>")
                end
            end,
        },
        {
            name = "compile_cold_unique",
            iters = scaled(30000),
            setup = function(R)
                local i = 0
                if type(R.clear_cache) == "function" then R.clear_cache() end
                return function()
                    i = i + 1
                    return R.compile("tok" .. tostring(i) .. "\\d\\+")
                end
            end,
        },
    }
end

local function run_suite(engine_path, scale)
    local R = load_engine(engine_path)
    local defs = case_definitions(scale)
    local results = {
        order = {},
        stats = {},
    }

    for i = 1, #defs do
        local d = defs[i]
        local fn = d.setup(R)
        local warmup = math.min(1500, d.iters)

        for _ = 1, warmup do fn() end
        collectgarbage("collect")

        local t0 = os.clock()
        for _ = 1, d.iters do fn() end
        local dt = os.clock() - t0

        results.order[#results.order + 1] = d.name
        results.stats[d.name] = {
            iters = d.iters,
            total = dt,
            us = (dt / d.iters) * 1e6,
            ops = d.iters / dt,
        }
    end

    return results
end

local function print_suite(label, suite)
    print("")
    print(label)
    print(string.rep("-", #label))

    for i = 1, #suite.order do
        local name = suite.order[i]
        local s = suite.stats[name]
        print(string.format("%-27s total=%7.4fs  iter=%8.2fus  ops/s=%10.0f", name, s.total, s.us, s.ops))
    end
end

local function print_compare(base_label, base_suite, cmp_label, cmp_suite)
    print("")
    print("Comparison (lower iter us is faster)")
    print("-------------------------------------")
    print(string.format("base=%s", base_label))
    print(string.format("cmp =%s", cmp_label))

    for i = 1, #base_suite.order do
        local name = base_suite.order[i]
        local a = base_suite.stats[name]
        local b = cmp_suite.stats[name]
        if a and b then
            local speedup = a.us / b.us
            print(string.format("%-27s x%6.2f", name, speedup))
        end
    end
end

local opts = parse_args(arg or {})

print("Regex benchmark harness")
print("engine=" .. opts.engine)
print("scale=" .. tostring(opts.scale))

local base_suite = run_suite(opts.engine, opts.scale)
print_suite("Engine: " .. opts.engine, base_suite)

if opts.compare then
    print("compare=" .. opts.compare)
    local cmp_suite = run_suite(opts.compare, opts.scale)
    print_suite("Engine: " .. opts.compare, cmp_suite)
    print_compare(opts.engine, base_suite, opts.compare, cmp_suite)
end
