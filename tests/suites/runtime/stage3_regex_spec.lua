return {
    id = "runtime.stage3_regex",
    description = "Ports stage 3 Vim regex engine coverage against the real compiled regex implementation.",
    
    run = function(ctx)
        local Assert = ctx.assert

        local function load_engine(path)
            local chunk, lerr = loadfile(path)
            if not chunk then
                error("Failed to load engine from " .. tostring(path) .. ": " .. tostring(lerr))
            end

            local ok, mod = pcall(chunk)
            if not ok then
                error("Engine init failed for " .. tostring(path) .. ": " .. tostring(mod))
            end

            return mod
        end

        local function assert_match(label, R, text, pat, case_sensitive, exp_s, exp_e)
            local s, e, emsg = R.find(text, pat, case_sensitive)
            if emsg then
                error(("%s: regex error: %s"):format(label, tostring(emsg)))
            end
            Assert.eq(label .. " start", s, exp_s)
            Assert.eq(label .. " end", e, exp_e)
        end

        local function assert_no_match(label, R, text, pat, case_sensitive)
            local s, e, emsg = R.find(text, pat, case_sensitive)
            if emsg then
                error(("%s: regex error: %s"):format(label, tostring(emsg)))
            end
            Assert.eq(label .. " start", s, nil)
            Assert.eq(label .. " end", e, nil)
        end

        local R = load_engine("lib/excmd/vim_regex.lua")

        assert_match("lookahead positive", R, "foobar", "\\%(foo\\)\\@=foo", true, 1, 3)
        assert_match("lookahead negative", R, "bar", "\\%(foo\\)\\@!bar", true, 1, 3)
        assert_match("lookbehind positive", R, "foobar", "\\%(foo\\)\\@<=bar", true, 4, 6)
        assert_match("lookbehind negative", R, "xxbar", "\\%(foo\\)\\@<!bar", true, 3, 5)
        assert_match("counted lookbehind positive", R, "hi! link", "\\a\\@1<=!", true, 3, 3)
        assert_match("counted lookbehind width", R, "end do label", "\\%(end\\s*do\\s\\+\\)\\@11<=label", true, 8, 12)
        assert_match(
            "vm escaped counted repeat branch",
            R,
            "- x", "\\%(\\t\\| \\{0,4\\}\\)[-*+]\\%(\\s\\+\\S\\)\\@=",
            true,
            1,
            1
        )
        assert_match("vm counted repeat unescaped close", R, "&lt;", "&#\\=[0-9A-Za-z]\\{1,32};", true, 1, 4)

        assert_match("zs/ze span", R, "foobarqux", "foo\\zsbar\\zequx", true, 4, 6)

        assert_match("external capture/backref", R, "aaabaaa", "\\z(a\\+\\)b\\z1", true, 1, 7)
        assert_no_match("external capture/backref mismatch", R, "aaabxaaa", "\\z(a\\+\\)b\\z1", true)

        assert_match("percent group", R, "foobaz", "\\%(foo\\|bar\\)baz", true, 1, 6)
        assert_match("percent optional short", R, "clea", "clea\\%[r]", true, 1, 4)
        assert_match("percent optional full", R, "clear", "clea\\%[r]", true, 1, 5)
        assert_match("percent column greater", R, "abc", "\\%>1c", true, 2, 1)
        assert_match("percent column less", R, "abc", "\\%<2c", true, 1, 0)
        assert_match("percent column exact", R, "abc", "\\%2c", true, 2, 1)
        assert_match("matchit current-token column guard", R, "(x)", "(\\(\\%>1c.*$\\)\\@=", true, 1, 1)
        assert_no_match("matchit current-token column guard after current token", R, "(x)", "(\\(\\%>2c.*$\\)\\@=", true)
        assert_match("underscore class newline", R, "a\nb", "a\\_sb", true, 1, 3)
        assert_match("identifier classes i/I", R, "::cont::", "::\\I\\i*::", true, 1, 8)
        assert_match("alternation earliest branch position", R, "x .. +", "[+]\\|\\.\\{2,3}", true, 3, 4)
        assert_match("simple ignore-case", R, "token123", "\\<Token\\d\\+\\>", false, 1, 8)
        do
            local compiled, emsg = R.compile("^foo")
            if not compiled then
                error("FAIL compile bol anchor: " .. tostring(emsg))
            end
            local s, e = R.find_compiled("xxfoo", compiled, true, 3)
            Assert.eq("bol anchor mid-search start", s, nil)
            Assert.eq("bol anchor mid-search end", e, nil)
        end
        assert_no_match("bclass percent literal", R, "if exists", "#\\d\\+\\|[#%]<\\>", true)
        assert_match("counted repeat open upper", R, "aab", "a\\{2,}", true, 1, 2)
        assert_match("help option pattern repeat", R, "'textwidth'", "'[a-z]\\{2,\\}'", true, 1, 11)
        do
            local matchit_pat =
                "\\%(\\%((\\|)\\|{\\|}\\|\\\\\\\\[\\|\\]\\|<\\|>\\|\\/\\*\\|\\*\\/\\|#\\s*if\\%(n\\=def\\)\\=\\|#\\s*else\\>\\|#\\s*elif\\%(n\\=def\\)\\=\\>\\|#\\s*endif\\>\\)\\)$"
            local compiled, emsg = R.compile(matchit_pat)
            Assert.truthy("matchit matchpairs pattern compiles", compiled ~= nil, emsg)
        end

        do
            local compiled, emsg = R.compile("[abc")
            Assert.eq("unterminated [] class compile result", compiled, nil)
            Assert.truthy(
                "unterminated [] class error text",
                tostring(emsg or ""):find("Unterminated [] class", 1, true) ~= nil,
                tostring(emsg)
            )
        end

        assert_match(
            "engine selector no-op",
            R,
            "=~#",
            "\\%#=1\\%(==\\|!=\\|>=\\|<=\\|=\\~\\|!\\~\\|>\\|<\\)[?#]\\=",
            true,
            1,
            3
        )

        local long_tail = ("x"):rep(32768 - 10) .. " token1234"
        local long_none = ("x"):rep(32768)

        local token_compiled, token_err = R.compile("\\<token\\d\\+\\>")
        if not token_compiled then
            error("FAIL compile token pattern: " .. tostring(token_err))
        end
        Assert.eq("token compiled mode", token_compiled.mode, "simple")
        local ts, te, temsg = R.find_compiled(long_tail, token_compiled, true)
        if temsg then
            error("FAIL long token find: " .. tostring(temsg))
        end
        Assert.eq("long token start", ts, #long_tail - 8)
        Assert.eq("long token end", te, #long_tail)

        local miss_compiled, miss_err = R.compile("qqqqqq\\d\\+")
        if not miss_compiled then
            error("FAIL compile miss pattern: " .. tostring(miss_err))
        end
        Assert.eq("miss compiled mode", miss_compiled.mode, "simple")
        local ms, me, memsg = R.find_compiled(long_none, miss_compiled, true)
        if memsg then
            error("FAIL long miss find: " .. tostring(memsg))
        end
        Assert.eq("long miss start", ms, nil)
        Assert.eq("long miss end", me, nil)

        local off = R.parse_syntax_offsets("ms=s+1,me=e-1,hs=s+1,he=e,rs=s,re=e-1,lc=2")
        Assert.eq("offset ms anchor", off.ms.anchor, "s")
        Assert.eq("offset me anchor", off.me.anchor, "e")
        Assert.eq("offset lc", off.lc, 2)

        local applied = R.apply_syntax_offsets(10, 20, off)
        Assert.eq("applied ms", applied.ms, 11)
        Assert.eq("applied me", applied.me, 19)
        Assert.eq("applied rs", applied.rs, 10)
        Assert.eq("applied re", applied.re, 19)

        local off_lc = R.parse_syntax_offsets("lc=1")
        local applied_lc = R.apply_syntax_offsets(6, 7, off_lc)
        Assert.eq("applied lc sets ms", applied_lc.ms, 7)
    end,
}
