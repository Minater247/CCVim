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
    }

    for i = 1, #argv do
        local arg = argv[i]
        local k, v = arg:match("^%-%-(%w+)%=(.+)$")
        if k == "engine" then
            opts.engine = v
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

local function scaled(base, factor)
    return math.max(1, math.floor(base * factor))
end

local function case_definitions(scale)
    return {
        {
            name = "vm_lookahead",
            pat = "\\%(foo\\)\\@=foo",
            text = ("foo bar baz foo qux "):rep(72),
            iters = scaled(60000, scale),
        },
        {
            name = "vm_lookbehind",
            pat = "\\%(foo\\)\\@<=bar",
            text = ("xxfoobarxx yy "):rep(96),
            iters = scaled(60000, scale),
        },
        {
            name = "vm_zs_ze",
            pat = "foo\\zsbar\\zequx",
            text = ("fooqux .. foobarqux .. "):rep(84),
            iters = scaled(60000, scale),
        },
        {
            name = "vm_ext_backref",
            pat = "\\z(a\\+\\)b\\z1",
            text = ("aaabaaa zz "):rep(96),
            iters = scaled(20000, scale),
        },
        {
            name = "vm_pct_opt",
            pat = "clea\\%[r]",
            text = ("clear clea clearx "):rep(96),
            iters = scaled(80000, scale),
        },
        {
            name = "vm_underscore",
            pat = "a\\_sb",
            text = ("a\nb xx "):rep(160),
            iters = scaled(80000, scale),
        },
        {
            name = "simple_reference",
            pat = "\\<token\\d\\+\\>",
            text = ("noise token1234 more noise token9876 end "):rep(120),
            iters = scaled(120000, scale),
        },
    }
end

local function run_suite(engine_path, scale)
    local R = load_engine(engine_path)
    local defs = case_definitions(scale)
    local out = {
        order = {},
        stats = {},
    }

    for i = 1, #defs do
        local d = defs[i]
        local compiled, emsg = R.compile(d.pat)
        if not compiled then
            error(("compile failed for %s: %s"):format(d.name, tostring(emsg)))
        end

        local warm = math.min(2000, d.iters)
        for _ = 1, warm do
            R.find_compiled(d.text, compiled, true)
        end
        collectgarbage("collect")

        local t0 = os.clock()
        for _ = 1, d.iters do
            R.find_compiled(d.text, compiled, true)
        end
        local dt = os.clock() - t0

        out.order[#out.order + 1] = d.name
        out.stats[d.name] = {
            iters = d.iters,
            total = dt,
            us = (dt / d.iters) * 1e6,
            ops = d.iters / dt,
            mode = compiled.mode or "simple",
        }
    end

    return out
end

local function print_suite(label, suite)
    print("")
    print(label)
    print(string.rep("-", #label))

    for i = 1, #suite.order do
        local name = suite.order[i]
        local s = suite.stats[name]
        print(string.format("%-20s mode=%-6s total=%7.4fs  iter=%8.2fus  ops/s=%10.0f",
            name, s.mode, s.total, s.us, s.ops))
    end
end

local opts = parse_args(arg or {})
print("Regex Stage 3 VM benchmark")
print("engine=" .. opts.engine)
print("scale=" .. tostring(opts.scale))

local suite = run_suite(opts.engine, opts.scale)
print_suite("Engine: " .. opts.engine, suite)
