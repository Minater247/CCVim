local MockEnv = require("vim.tests.test_mocks")
local mock = MockEnv.setup()

local Runtime = mock.loadModule("vim.lib.syntax_engine.runtime")
local Parser = mock.loadModule("vim.lib.syntax_engine.command_parser")
local Compiler = mock.loadModule("vim.lib.syntax_engine.compiler")
local State = mock.loadModule("vim.lib.syntax_engine.state")
local Highlight = mock.loadModule("vim.lib.highlight")
local Buffer = mock.loadModule("vim.layout.buffer")

local function assert_eq(label, a, b)
    if a ~= b then
        error(("FAIL %s: expected %s, got %s"):format(label, tostring(b), tostring(a)))
    end
end

local function assert_true(label, cond)
    if not cond then
        error(("FAIL %s: expected true, got false"):format(label))
    end
end

local function mk_ctx(commands)
    local parsed = {}
    for i = 1, #commands do
        parsed[i] = Parser.parse(commands[i])
    end

    local ctx = State.new_context({
        syntax = "test",
        synmaxcol = 3000,
    })
    ctx.syntax_commands = parsed
    ctx.syntax_ir = Compiler.compile(parsed)
    ctx.syntax_ir_dirty = false
    return ctx
end

local function mk_buf(lines)
    local buf = Buffer(false, false, true)
    local copied = {}
    for i = 1, #lines do
        copied[i] = lines[i]
    end
    if #copied == 0 then
        copied[1] = ""
    end
    buf.lines = copied
    buf.loaded = true
    return buf
end

local function fg_at(blit, idx)
    return blit.fg:sub(idx, idx)
end

local function bg_at(blit, idx)
    return blit.bg:sub(idx, idx)
end

local normal_fg = colors.toBlit(Highlight.For("Normal")[1])
local string_fg = colors.toBlit(Highlight.For("String")[1])
local comment_fg = colors.toBlit(Highlight.For("Comment")[1])
local structure_fg = colors.toBlit(Highlight.For("Structure")[1])
local error_fg = colors.toBlit(Highlight.For("Error")[1])
local error_bg = colors.toBlit(Highlight.For("Error")[2])

-- keyword baseline
do
    local ctx = mk_ctx({
        "keyword String test",
    })
    local buf = mk_buf({ "a test z" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_true("keyword blit exists", blit ~= nil)
    assert_eq("keyword start fg", fg_at(blit, 3), string_fg)
    assert_eq("keyword middle fg", fg_at(blit, 5), string_fg)
    assert_eq("keyword outside fg", fg_at(blit, 1), normal_fg)
end

-- same-start Match/Region items: later-defined has priority
do
    local ctx = mk_ctx({
        "match Comment /foo/",
        "match String /foo/",
    })
    local buf = mk_buf({ "foo" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("same-start match priority (later wins)", fg_at(blit, 1), string_fg)
end

-- keyword has priority over match/region at the same position
do
    local ctx = mk_ctx({
        "keyword String foo",
        "match Comment /foo/",
    })
    local buf = mk_buf({ "foo" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("keyword over match priority", fg_at(blit, 1), string_fg)
end

-- for equal-start keywords, case-sensitive keyword wins over ignore-case
do
    local ctx = mk_ctx({
        "case ignore",
        "keyword Comment foo",
        "case match",
        "keyword String foo",
    })
    local buf = mk_buf({ "foo" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("keyword case-sensitive over ignore-case", fg_at(blit, 1), string_fg)
end

-- quoted patterns that start with punctuation must be treated as literal regex,
-- not as delimiter-form syntax.
do
    local ctx = mk_ctx({
        'match Comment "--.*$"',
    })
    local buf = mk_buf({ "-- hello" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("quoted punctuation pattern", fg_at(blit, 1), comment_fg)
end

-- quoted patterns that start with backslash (word boundaries, etc.) must also
-- remain literal regex.
do
    local ctx = mk_ctx({
        'match String "\\<foo\\>"',
    })
    local buf = mk_buf({ "foo" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("quoted backslash pattern", fg_at(blit, 1), string_fg)
end

-- Quoted regex patterns that contain '=' (like \= in Vim regex atoms) must
-- not be misparsed as key=value options. If misparsed, an empty regex is
-- created and can starve real matches.
do
    local parsed = Parser.parse('match String "\\<\\d\\+\\%([eE][-+]\\=\\d\\+\\)\\="')
    assert_true("quoted pattern with equals is not dropped", parsed.pattern ~= nil and parsed.pattern ~= "")

    local ctx = mk_ctx({
        'match Comment "--.*$"',
        'match String "\\<\\d\\+\\%([eE][-+]\\=\\d\\+\\)\\="',
    })
    local buf = mk_buf({ "-- hello" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("quoted pattern with equals does not starve comment match", fg_at(blit, 1), comment_fg)
end

-- Delimiter-form assignment patterns may include spaces (e.g. [ \t:] classes).
-- Tokenization must keep these values intact instead of splitting at whitespace.
do
    local parsed = Parser.parse("region Comment start=+foo bar+ skip=+x y + end=+tail+")
    assert_eq("region start assignment keeps spaces", parsed.patterns.start[1].pattern, "+foo bar+")
    assert_eq("region skip assignment keeps spaces", parsed.patterns.skip[1].pattern, "+x y +")
    assert_eq("region end assignment keeps spaces", parsed.patterns["end"][1].pattern, "+tail+")
end

-- Quoted delimiter-form patterns may contain the quote delimiter inside [].
-- Tokenization must not terminate at quote characters that are part of the class.
do
    local parsed = Parser.parse('match Comment "[^"]\\+"')
    assert_eq("quoted delimiter inside [] class is preserved", parsed.pattern, '"[^"]\\+"')
end

-- Delimiter-form patterns may contain the delimiter literally inside [] classes.
-- Parser tokenization must not terminate on that inner delimiter.
do
    local parsed = Parser.parse("region Comment start=+[,+ ]+ end=+tail+")
    assert_eq("delimiter inside [] class is preserved", parsed.patterns.start[1].pattern, "+[,+ ]+")
end

-- Runtime delimiter splitting must also ignore delimiters inside [] classes.
-- Otherwise a pattern like +[ab+]+ gets truncated to [ab and crashes string.find.
do
    local ctx = mk_ctx({
        "match Comment +[ab+]+",
    })
    local buf = mk_buf({ "+" })
    local ok, blit = pcall(Runtime.line_to_blit, ctx, buf, 1)
    assert_true("delimiter inside [] class does not crash runtime", ok == true)
    if ok then
        assert_eq("delimiter inside [] class matches", fg_at(blit, 1), comment_fg)
    end
end

-- For equal-start region end patterns, later-defined end= specs should win.
-- help.vim uses this to ensure the "^<" end pattern is used over a broader
-- "^[^ \\t]" match with me=e-1 at the same position.
do
    local ctx = mk_ctx({
        "region Comment matchgroup=Error start=/>/ end=/^[^ \\t]/me=e-1 end=/^</",
    })
    local buf = mk_buf({ ">vim", "<" })
    Runtime.line_to_blit(ctx, buf, 1)
    local blit2 = Runtime.line_to_blit(ctx, buf, 2)
    assert_eq("region end tie-break prefers later end= pattern", fg_at(blit2, 1), error_fg)
end

-- contained keyword only inside container region
do
    local ctx = mk_ctx({
        "keyword String hello contained",
    })
    local buf = mk_buf({ "hello" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("contained top-level no highlight", fg_at(blit, 1), normal_fg)
end

do
    local ctx = mk_ctx({
        "region Comment start=/\"/ end=/\"/ contains=String",
        "keyword String hello contained",
    })
    local buf = mk_buf({ "\"hello\"" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("region start quote", fg_at(blit, 1), comment_fg)
    assert_eq("contained inside region", fg_at(blit, 2), string_fg)
    assert_eq("contained inside region tail", fg_at(blit, 6), string_fg)
end

-- nextgroup + skipwhite
do
    local ctx = mk_ctx({
        "match Comment /foo/ nextgroup=String skipwhite",
        "match String /bar/ contained",
    })
    local buf = mk_buf({ "foo   bar" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("nextgroup foo", fg_at(blit, 1), comment_fg)
    assert_eq("nextgroup bar", fg_at(blit, 7), string_fg)
end

-- nextgroup should permit contained targets even when the current container
-- doesn't include them via contains=.
do
    local ctx = mk_ctx({
        "region Comment start=/{/ end=/}/ contains=TOP",
        "match Structure /a/ nextgroup=String",
        "match String /b/ contained",
    })
    local buf = mk_buf({ "{ab}" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("nextgroup contained target inside TOP container", fg_at(blit, 3), string_fg)
end

-- lc= offsets should set match start and allow anchored nextgroup matches to
-- step back into leading context.
do
    local ctx = mk_ctx({
        "match Comment /foo/ nextgroup=String",
        "match String /[^\\\\]w/lc=1 contained",
    })
    local buf = mk_buf({ "foow" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("lc nextgroup anchor comment", fg_at(blit, 1), comment_fg)
    assert_eq("lc nextgroup anchor string", fg_at(blit, 4), string_fg)
end

-- cross-line region state invalidation
do
    local ctx = mk_ctx({
        "region Comment start=/\\/\\*/ end=/\\*\\//",
    })
    local buf = mk_buf({ "/* one", "two */", "tail" })

    local blit2 = Runtime.line_to_blit(ctx, buf, 2)
    assert_eq("region carries to line2", fg_at(blit2, 1), comment_fg)

    buf.lines[1] = "xx one"
    State.mark_dirty(ctx, 1)

    local blit2_after = Runtime.line_to_blit(ctx, buf, 2)
    assert_eq("region removed after edit", fg_at(blit2_after, 1), normal_fg)
end

-- Regions with start patterns that consume to EOL and end="$" must not leak
-- to following lines, including across blank lines.
do
    local ctx = mk_ctx({
        'region Comment start=+^[ \\t:]*\\zs".*$+ skip=+\\n\\s*\\\\\\|\\n\\s*"\\\\ + end="$"',
    })
    local buf = mk_buf({ '" one', "", "if x", '" two', "let y = 1" })

    local blit1 = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("line comment first line", fg_at(blit1, 1), comment_fg)

    local blit3 = Runtime.line_to_blit(ctx, buf, 3)
    assert_eq("line comment does not leak across blank line", fg_at(blit3, 1), normal_fg)

    local blit4 = Runtime.line_to_blit(ctx, buf, 4)
    assert_eq("line comment second block", fg_at(blit4, 1), comment_fg)

    local blit5 = Runtime.line_to_blit(ctx, buf, 5)
    assert_eq("line comment does not leak after second block", fg_at(blit5, 1), normal_fg)
end

-- region end pattern should win over same-position match when region is newer
do
    local ctx = mk_ctx({
        "match Error /}/",
        "region Structure start=/{/ end=/}/",
    })
    local buf = mk_buf({ "{}" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("region end beats same-pos match", fg_at(blit, 2), structure_fg)
    assert_true("region end not Error background", bg_at(blit, 2) ~= error_bg)
end

-- region end pattern should also win when region is older than the match item
do
    local ctx = mk_ctx({
        "region Structure start=/{/ end=/}/",
        "match Error /}/",
    })
    local buf = mk_buf({ "{}" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("region end beats same-pos match (older region)", fg_at(blit, 2), structure_fg)
    assert_true("region end (older region) not Error background", bg_at(blit, 2) ~= error_bg)
end

-- when end offsets move match end before the raw end, nextgroup should start
-- from the adjusted match end boundary (not raw end).
do
    local ctx = mk_ctx({
        "region Comment start=/\\<if\\>/ end=/\\<then\\>/me=e-4 nextgroup=String",
        "match String /\\<then\\>/ contained",
    })
    local buf = mk_buf({ "if then" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("region me offset preserves nextgroup hand-off", fg_at(blit, 4), string_fg)
end

-- transparent regions should still highlight start/end when matchgroup is set
do
    local ctx = mk_ctx({
        "region Comment transparent matchgroup=Structure start=/{/ end=/}/",
    })
    local buf = mk_buf({ "{}" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("transparent matchgroup start delimiter", fg_at(blit, 1), structure_fg)
    assert_eq("transparent matchgroup end delimiter", fg_at(blit, 2), structure_fg)
end

-- transparent regions without matchgroup should not paint delimiters
do
    local ctx = mk_ctx({
        "region Comment transparent start=/{/ end=/}/",
    })
    local buf = mk_buf({ "{}" })
    local blit = Runtime.line_to_blit(ctx, buf, 1)
    assert_eq("transparent plain start stays Normal", fg_at(blit, 1), normal_fg)
    assert_eq("transparent plain end stays Normal", fg_at(blit, 2), normal_fg)
end

print("Stage 4 runtime tests: OK")
