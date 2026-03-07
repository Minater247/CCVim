-- luacheck: ignore 631
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
        line_len = 8192,
        very_line_len = 32768,
        include_very_long = true,
    }

    for i = 1, #argv do
        local arg = argv[i]
        local k, v = arg:match("^%-%-([%w%-]+)=(.+)$")
        if k == "engine" then
            opts.engine = v
        elseif k == "compare" then
            opts.compare = v
        elseif k == "scale" then
            opts.scale = tonumber(v) or 1
            if opts.scale <= 0 then opts.scale = 1 end
        elseif k == "line-len" then
            opts.line_len = tonumber(v) or opts.line_len
            if opts.line_len < 64 then opts.line_len = 64 end
        elseif k == "very-line-len" then
            opts.very_line_len = tonumber(v) or opts.very_line_len
            if opts.very_line_len < 64 then opts.very_line_len = 64 end
        elseif k == "include-very-long" then
            opts.include_very_long = not (v == "0" or v == "false")
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

local function scaled(n, scale)
    return math.max(1, math.floor(n * scale))
end

local function line_with_tail(len, tail)
    tail = tostring(tail or "")
    if #tail >= len then
        return tail
    end
    return ("x"):rep(len - #tail) .. tail
end

local function make_payloads(len)
    return {
        none = ("x"):rep(len),
        foo_tail = line_with_tail(len, "foo"),
        foobar_tail = line_with_tail(len, "foobar"),
        foobarqux_tail = line_with_tail(len, "foobarqux"),
        aaabaaa_tail = line_with_tail(len, "aaabaaa"),
        clear_tail = line_with_tail(len, "clear"),
        token_tail = line_with_tail(len, " token1234"),
        baz_tail = line_with_tail(len, "baz"),
        newline_tail = line_with_tail(len, "a\nb"),
    }
end

local function definition_specs()
    return {
        { name = "vm_lookahead_end",     pat = "\\%(foo\\)\\@=foo",          key = "foo_tail",       iters = 5000,  stage3 = true },
        { name = "vm_lookbehind_end",    pat = "\\%(foo\\)\\@<=bar",         key = "foobar_tail",    iters = 5000,  stage3 = true },
        { name = "vm_zs_ze_end",         pat = "foo\\zsbar\\zequx",          key = "foobarqux_tail", iters = 5000,  stage3 = true },
        { name = "vm_ext_backref_end",   pat = "\\z(a\\+\\)b\\z1",           key = "aaabaaa_tail",   iters = 2500,  stage3 = true },
        { name = "vm_complex_end",       pat = "\\%(foo\\)\\@<=bar\\zequx",  key = "foobarqux_tail", iters = 4000,  stage3 = true },
        { name = "vm_lookbehind_miss",   pat = "\\%(foo\\)\\@<=bar",         key = "none",           iters = 3500,  stage3 = true },
        { name = "vm_pct_opt_end",       pat = "clea\\%[r]",                 key = "clear_tail",     iters = 7000,  stage3 = true },
        { name = "vm_underscore_end",    pat = "a\\_sb",                     key = "newline_tail",   iters = 7000,  stage3 = true },
        { name = "simple_token_end",     pat = "\\<token\\d\\+\\>",          key = "token_tail",     iters = 30000, stage3 = false },
        { name = "simple_alt_end",       pat = "\\(foo\\|bar\\|baz\\)",      key = "baz_tail",       iters = 30000, stage3 = false },
        { name = "simple_nomatch_long",  pat = "qqqqqq\\d\\+",               key = "none",           iters = 30000, stage3 = false },
    }
end

local function add_cases(cases, specs, payloads, suffix, scale, iter_factor)
    for i = 1, #specs do
        local s = specs[i]
        local iters = scaled(math.max(1, math.floor(s.iters * iter_factor)), scale)
        cases[#cases + 1] = {
            name = s.name .. "_" .. suffix,
            pat = s.pat,
            text = payloads[s.key],
            iters = iters,
            case_sensitive = true,
            stage3 = s.stage3,
        }
    end
end

local function case_definitions(opts)
    local specs = definition_specs()
    local cases = {}

    local long_payloads = make_payloads(opts.line_len)
    add_cases(cases, specs, long_payloads, "L" .. tostring(opts.line_len), opts.scale, 1.0)

    if opts.include_very_long then
        local very_payloads = make_payloads(opts.very_line_len)
        add_cases(cases, specs, very_payloads, "L" .. tostring(opts.very_line_len), opts.scale, 0.25)
    end

    return cases
end

local function run_suite(engine_path, opts)
    local R = load_engine(engine_path)
    local defs = case_definitions(opts)
    local results = {
        order = {},
        stats = {},
    }

    for i = 1, #defs do
        local d = defs[i]
        local entry = {
            iters = d.iters,
            line_len = #d.text,
            stage3 = d.stage3,
        }

        local compiled, emsg = R.compile(d.pat)
        if not compiled then
            entry.unsupported = tostring(emsg)
            results.order[#results.order + 1] = d.name
            results.stats[d.name] = entry
            goto continue
        end

        entry.mode = compiled.mode or "simple"

        local fn = function()
            return R.find_compiled(d.text, compiled, d.case_sensitive)
        end

        local warmup = math.min(1500, d.iters)
        for _ = 1, warmup do fn() end
        collectgarbage("collect")

        local t0 = os.clock()
        for _ = 1, d.iters do fn() end
        local dt = os.clock() - t0

        entry.total = dt
        entry.us = (dt / d.iters) * 1e6
        entry.ops = d.iters / dt

        results.order[#results.order + 1] = d.name
        results.stats[d.name] = entry

        ::continue::
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
        if s.unsupported then
            print(string.format("%-31s unsupported (%s)", name, s.unsupported))
        else
            print(string.format("%-31s mode=%-6s len=%6d  iter=%8.2fus  ops/s=%10.0f",
                name, s.mode, s.line_len, s.us, s.ops))
        end
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
            if a.unsupported or b.unsupported then
                local am = a.unsupported and "unsupported" or "ok"
                local bm = b.unsupported and "unsupported" or "ok"
                print(string.format("%-31s %s vs %s", name, am, bm))
            elseif a.stage3 and ((a.mode ~= "vm") or (b.mode ~= "vm")) then
                print(string.format("%-31s non-equivalent modes (%s vs %s)", name, tostring(a.mode), tostring(b.mode)))
            else
                local speedup = a.us / b.us
                print(string.format("%-31s x%6.2f", name, speedup))
            end
        end
    end
end

local opts = parse_args(arg or {})

print("Regex long-line benchmark")
print("engine=" .. opts.engine)
print("scale=" .. tostring(opts.scale))
print("line_len=" .. tostring(opts.line_len))
print("very_line_len=" .. tostring(opts.very_line_len))
print("include_very_long=" .. tostring(opts.include_very_long))

local base_suite = run_suite(opts.engine, opts)
print_suite("Engine: " .. opts.engine, base_suite)

if opts.compare then
    print("compare=" .. opts.compare)
    local cmp_suite = run_suite(opts.compare, opts)
    print_suite("Engine: " .. opts.compare, cmp_suite)
    print_compare(opts.engine, base_suite, opts.compare, cmp_suite)
end
