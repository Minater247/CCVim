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

local function assert_eq(label, a, b)
    if a ~= b then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(b), tostring(a)))
    end
end

local function assert_match(label, R, text, pat, case_sensitive, exp_s, exp_e)
    local s, e, emsg = R.find(text, pat, case_sensitive)
    if emsg then
        error(("FAIL %s: regex error: %s"):format(label, tostring(emsg)))
    end
    assert_eq(label .. " start", s, exp_s)
    assert_eq(label .. " end", e, exp_e)
end

local function assert_no_match(label, R, text, pat, case_sensitive)
    local s, e, emsg = R.find(text, pat, case_sensitive)
    if emsg then
        error(("FAIL %s: regex error: %s"):format(label, tostring(emsg)))
    end
    assert_eq(label .. " start", s, nil)
    assert_eq(label .. " end", e, nil)
end

local dir = script_dir()
local engine_path = join(dir, "../../lib/excmd/vim_regex.lua")
local R = load_engine(engine_path)

-- Lookahead / lookbehind
assert_match("lookahead positive", R, "foobar", "\\%(foo\\)\\@=foo", true, 1, 3)
assert_match("lookahead negative", R, "bar", "\\%(foo\\)\\@!bar", true, 1, 3)
assert_match("lookbehind positive", R, "foobar", "\\%(foo\\)\\@<=bar", true, 4, 6)
assert_match("lookbehind negative", R, "xxbar", "\\%(foo\\)\\@<!bar", true, 3, 5)

-- \zs / \ze span markers
assert_match("zs/ze span", R, "foobarqux", "foo\\zsbar\\zequx", true, 4, 6)

-- external capture + backref: \z(...) and \z1
assert_match("external capture/backref", R, "aaabaaa", "\\z(a\\+\\)b\\z1", true, 1, 7)
assert_no_match("external capture/backref mismatch", R, "aaabxaaa", "\\z(a\\+\\)b\\z1", true)

-- \%(...) non-capturing group
assert_match("percent group", R, "foobaz", "\\%(foo\\|bar\\)baz", true, 1, 6)

-- \%[...] optional fragment
assert_match("percent optional short", R, "clea", "clea\\%[r]", true, 1, 4)
assert_match("percent optional full", R, "clear", "clea\\%[r]", true, 1, 5)

-- generalized \_ classes include newline
assert_match("underscore class newline", R, "a\nb", "a\\_sb", true, 1, 3)

-- identifier classes used by Lua labels and similar constructs
assert_match("identifier classes i/I", R, "::cont::", "::\\I\\i*::", true, 1, 8)

-- alternation should return the earliest match across branches, not merely the
-- first branch that matches somewhere later.
assert_match("alternation earliest branch position", R, "x .. +", "[+]\\|\\.\\{2,3}", true, 3, 4)

-- still honors simple-path behavior + ignore-case
assert_match("simple ignore-case", R, "token123", "\\<Token\\d\\+\\>", false, 1, 8)

-- Percent inside [] classes must be treated literally in Lua translation.
-- Otherwise classes like [#%] can overrun and match arbitrary text.
assert_no_match("bclass percent literal", R, "if exists", "#\\d\\+\\|[#%]<\\>", true)

-- Open-ended counted repeats must work in simple-mode patterns.
assert_match("counted repeat open upper", R, "aab", "a\\{2,}", true, 1, 2)
assert_match("help option pattern repeat", R, "'textwidth'", "'[a-z]\\{2,\\}'", true, 1, 11)

-- Unterminated [] classes should fail during compile, not crash later at match time.
do
    local compiled, emsg = R.compile("[abc")
    assert_eq("unterminated [] class compile result", compiled, nil)
    if not tostring(emsg or ""):find("Unterminated [] class", 1, true) then
        error(("FAIL unterminated [] class error text: got %s"):format(tostring(emsg)))
    end
end

-- Engine selector atoms are zero-width and should not affect matching.
assert_match(
    "engine selector no-op",
    R,
    "=~#",
    "\\%#=1\\%(==\\|!=\\|>=\\|<=\\|=\\~\\|!\\~\\|>\\|<\\)[?#]\\=",
    true,
    1,
    3
)

-- long-line simple-path behavior remains correct when VM fallback heuristics engage
local long_tail = ("x"):rep(32768 - 10) .. " token1234"
local long_none = ("x"):rep(32768)

local token_compiled, token_err = R.compile("\\<token\\d\\+\\>")
if not token_compiled then
    error("FAIL compile token pattern: " .. tostring(token_err))
end
assert_eq("token compiled mode", token_compiled.mode, "simple")
local ts, te, temsg = R.find_compiled(long_tail, token_compiled, true)
if temsg then
    error("FAIL long token find: " .. tostring(temsg))
end
assert_eq("long token start", ts, #long_tail - 8)
assert_eq("long token end", te, #long_tail)

local miss_compiled, miss_err = R.compile("qqqqqq\\d\\+")
if not miss_compiled then
    error("FAIL compile miss pattern: " .. tostring(miss_err))
end
assert_eq("miss compiled mode", miss_compiled.mode, "simple")
local ms, me, memsg = R.find_compiled(long_none, miss_compiled, true)
if memsg then
    error("FAIL long miss find: " .. tostring(memsg))
end
assert_eq("long miss start", ms, nil)
assert_eq("long miss end", me, nil)

-- syntax offset hooks
local off = R.parse_syntax_offsets("ms=s+1,me=e-1,hs=s+1,he=e,rs=s,re=e-1,lc=2")
assert_eq("offset ms anchor", off.ms.anchor, "s")
assert_eq("offset me anchor", off.me.anchor, "e")
assert_eq("offset lc", off.lc, 2)

local applied = R.apply_syntax_offsets(10, 20, off)
assert_eq("applied ms", applied.ms, 11)
assert_eq("applied me", applied.me, 19)
assert_eq("applied rs", applied.rs, 10)
assert_eq("applied re", applied.re, 19)

local off_lc = R.parse_syntax_offsets("lc=1")
local applied_lc = R.apply_syntax_offsets(6, 7, off_lc)
assert_eq("applied lc sets ms", applied_lc.ms, 7)

print("Stage 3 regex tests: OK")
