return {
    id = "api.lpeg_parity",
    description = "Ports LPeg compatibility checks by comparing CCVim's bundled implementation with the reference lpeg module.", -- luacheck: ignore 631
    
    run = function(ctx)
        local Assert = ctx.assert

        local ref = require("lpeg")
        local impl = dofile("lib/luaapi/lpeg.lua")

        local function pack(...)
            return { n = select("#", ...), ... }
        end

        local function normalize_error(msg)
            return tostring(msg):gsub("^.-:%d+: ", "")
        end

        local function deep_equal(a, b)
            if type(a) ~= type(b) then
                return false
            end

            if type(a) ~= "table" then
                return a == b
            end

            if a.n ~= nil or b.n ~= nil then
                if a.n ~= b.n then
                    return false
                end
                for i = 1, a.n do
                    if not deep_equal(a[i], b[i]) then
                        return false
                    end
                end
                return true
            end

            for k, v in pairs(a) do
                if not deep_equal(v, b[k]) then
                    return false
                end
            end
            for k, v in pairs(b) do
                if not deep_equal(v, a[k]) then
                    return false
                end
            end

            return true
        end

        local function run_case(mod, fn)
            local ok, result = pcall(function()
                return pack(fn(mod))
            end)

            if ok then
                return {
                    ok = true,
                    vals = result,
                }
            end

            return {
                ok = false,
                err = normalize_error(result),
            }
        end

        local function assert_same(name, fn)
            local a = run_case(ref, fn)
            local b = run_case(impl, fn)

            Assert.eq(name .. " success parity", a.ok, b.ok)

            if a.ok then
                Assert.truthy(name .. " return parity", deep_equal(a.vals, b.vals))
                return
            end

            Assert.eq(name .. " error parity", a.err, b.err)
        end

        Assert.eq("version parity", impl.version(), "1.1.0")
        Assert.eq("type(pattern) parity", impl.type(impl.P("x")), "pattern")
        Assert.eq("type(non-pattern) parity", impl.type("x"), nil)

        local parity_cases = {
            { name = "literal match", fn = function(M) return M.match(M.P("abc"), "abcdef") end },
            { name = "literal anchored fail", fn = function(M) return M.match(M.P("bc"), "abc") end },
            { name = "init negative index", fn = function(M) return M.match(M.P("c"), "abc", -1) end },
            { name = "boolean true pattern", fn = function(M) return M.match(M.P(true), "abc") end },
            { name = "boolean false pattern", fn = function(M) return M.match(M.P(false), "abc") end },
            { name = "set match", fn = function(M) return M.match(M.S("+-*/"), "*") end },
            { name = "range repetition", fn = function(M) return M.match(M.R("az") ^ 1 * M.P(-1), "hello") end },
            { name = "ordered choice", fn = function(M) return M.match((M.P("ab") + M.P("a")) * M.P(-1), "ab") end },
            { name = "sequence", fn = function(M) return M.match(M.P("a") * M.P("b") * M.P(-1), "ab") end },
            { name = "subtraction success", fn = function(M) return M.match(M.P("ab") - M.P("c"), "ab") end },
            { name = "subtraction fail", fn = function(M) return M.match(M.P("ab") - M.P("a"), "ab") end },
            { name = "negative predicate", fn = function(M) return M.match(-M.P("a") * M.P(1), "b") end },
            { name = "and predicate", fn = function(M) return M.match(#M.P("a") * M.P("a"), "a") end },
            { name = "repetition possessive", fn = function(M) return M.match((M.P(1) ^ 0) * M.P("b"), "ab") end },
            { name = "optional repetition", fn = function(M) return M.match((M.P("a") ^ -1) * M.P(-1), "a") end },
            { name = "bounded repetition", fn = function(M) return M.match((M.P("a") ^ -2) * M.P(-1), "aa") end },
            { name = "pow fractional error", fn = function(M) return (M.P("a") ^ 1.5):match("a") end },
            { name = "lookbehind", fn = function(M) return M.match(M.B("a") * M.P("b"), "ab", 2) end },
            {
                name = "grammar recursion named start",
                fn = function(M) return M.match(M.P({ "S", S = M.P("a") * M.V("S") + M.P("") }), "aaa") end,
            },
            {
                name = "grammar recursion numeric start",
                fn = function(M) return M.match(M.P({ M.P("a") * M.V(1) + M.P("") }), "aaa") end,
            },
            {
                name = "grammar missing initial rule error",
                fn = function(M) return M.match(M.C({ "missing" }), "x") end,
            },
            {
                name = "simple capture with nested captures",
                fn = function(M) return M.match(M.C(M.P("ab") * M.Cc(9)), "ab") end,
            },
            { name = "constant capture nil slot", fn = function(M) return M.match(M.Cc(nil, "x"), "") end },
            { name = "anonymous group no inner capture", fn = function(M) return M.match(M.Cg(M.P("ab")), "ab") end },
            {
                name = "anonymous group with inner captures",
                fn = function(M) return M.match(M.Cg(M.Cc(1) * M.Cc(2)), "") end,
            },
            {
                name = "named group and backref with whole match",
                fn = function(M) return M.match(M.Cg(M.P("ab"), "k") * M.Cb("k"), "ab") end,
            },
            { name = "position capture", fn = function(M) return M.match(M.Cp() * M.P("a"), "a") end },
            { name = "argument capture nil value", fn = function(M) return M.match(M.Carg(2), "", 1, nil) end },
            { name = "argument capture missing error", fn = function(M) return M.match(M.Carg(3), "", 1, nil) end },
            { name = "backref missing error", fn = function(M) return M.match(M.Cb("missing"), "") end },
            {
                name = "fold capture",
                fn = function(M)
                    return M.match(M.Cf(M.Cc(1) * M.Cc(2) * M.Cc(3), function(a, b)
                        return a + b
                    end), "")
                end,
            },
            {
                name = "accumulator capture",
                fn = function(M)
                    return M.match(M.Cc(1) * (M.Cc(2) % function(a, b)
                        return a + b
                    end), "")
                end,
            },
            {
                name = "accumulator missing previous value error",
                fn = function(M)
                    return M.match((M.Cc(1) * M.Cc(2)) % function(a, b)
                        return a + b
                    end, "")
                end,
            },
            {
                name = "table capture anonymous and named",
                fn = function(M)
                    local t = M.match(M.Ct(M.Cc(1) * M.Cg(M.Cc("v"), "x")), "")
                    return t[1], t.x
                end,
            },
            {
                name = "match-time capture with extra",
                fn = function(M)
                    return M.match(M.Cmt(M.Cc("x"), function(_s, i, c)
                        return i, c .. "!"
                    end), "")
                end,
            },
            {
                name = "runtime function pattern",
                fn = function(M)
                    return M.match(M.P(function(_s, i)
                        return i + 1
                    end), "a")
                end,
            },
            {
                name = "division function nil capture value",
                fn = function(M)
                    return M.match((M.P("x") / function()
                        return nil
                    end) * M.Cc("ok"), "x")
                end,
            },
            {
                name = "division function no capture values",
                fn = function(M)
                    return M.match((M.P("x") / function() end) * M.Cc("ok"), "x")
                end,
            },
            {
                name = "division function false capture value",
                fn = function(M)
                    return M.match((M.P("x") / function()
                        return false
                    end) * M.Cc("ok"), "x")
                end,
            },
            {
                name = "division table miss",
                fn = function(M)
                    return M.match((M.C(M.R("09") ^ 1) / { ["34"] = "hit" }) * M.Cc("ok"), "12")
                end,
            },
            { name = "division number no capture error", fn = function(M) return M.match(M.P("ab") / 2, "ab") end },
            {
                name = "division string capture index error",
                fn = function(M) return M.match(M.P("ab") / "[%1]", "ab") end,
            },
            { name = "division string %0", fn = function(M) return M.match(M.P("ab") / "<%0>", "ab") end },
            {
                name = "substitution capture basic",
                fn = function(M)
                    return M.match(M.Cs((M.P("x") / "y" + 1) ^ 0), "abx")
                end,
            },
            {
                name = "substitution capture suppress nested replacement",
                fn = function(M)
                    return M.match(M.Cs(M.C(M.P("ab") * M.Cc(9))), "ab")
                end,
            },
            {
                name = "substitution capture invalid nil replacement",
                fn = function(M)
                    return M.match(M.Cs((M.P("x") / function()
                        return nil
                    end + 1) ^ 0), "abx")
                end,
            },
            {
                name = "substitution capture invalid table replacement",
                fn = function(M)
                    return M.match(M.Cs(M.Ct(M.Cc("a"))), "")
                end,
            },
            {
                name = "substitution capture keeps raw text on empty replacement list",
                fn = function(M)
                    return M.match(M.Cs((M.P("x") / function() end + 1) ^ 0), "abx")
                end,
            },
            {
                name = "substitution capture with Cmt no extra",
                fn = function(M)
                    return M.match(M.Cs(M.Cmt(M.P("a"), function(_s, i)
                        return i
                    end)), "a")
                end,
            },
            {
                name = "locale alnum class",
                fn = function(M)
                    local loc = M.locale()
                    return M.match(loc.alnum ^ 1 * M.P(-1), "A9")
                end,
            },
        }

        for i = 1, #parity_cases do
            assert_same(parity_cases[i].name, parity_cases[i].fn)
        end
    end,
}
