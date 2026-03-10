return {
    id = "runtime.stage4_syntax_engine",
    description = "Ports stage 4 syntax engine runtime coverage against the real parser and highlighting runtime; lua-editor-only because it exercises CCVim's internal syntax_engine parser/compiler/runtime modules directly.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()

        local ok, err = pcall(function()
            local Runtime = mock.loadModule("lib.syntax_engine.runtime")
            local Parser = mock.loadModule("lib.syntax_engine.command_parser")
            local Compiler = mock.loadModule("lib.syntax_engine.compiler")
            local State = mock.loadModule("lib.syntax_engine.state")
            local Highlight = mock.loadModule("lib.highlight")
            local Buffer = mock.loadModule("layout.buffer")

            local function mk_ctx(commands)
                local parsed = {}
                for i = 1, #commands do
                    parsed[i] = Parser.parse(commands[i])
                end

                local ctx_state = State.new_context({
                    syntax = "test",
                    synmaxcol = 3000,
                })
                ctx_state.syntax_commands = parsed
                ctx_state.syntax_ir = Compiler.compile(parsed)
                ctx_state.syntax_ir_dirty = false
                return ctx_state
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

            do
                local ctx_state = mk_ctx({ "keyword String test" })
                local buf = mk_buf({ "a test z" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.truthy("keyword blit exists", blit ~= nil)
                Assert.eq("keyword start fg", fg_at(blit, 3), string_fg)
                Assert.eq("keyword middle fg", fg_at(blit, 5), string_fg)
                Assert.eq("keyword outside fg", fg_at(blit, 1), normal_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "match Comment /foo/",
                    "match String /foo/",
                })
                local buf = mk_buf({ "foo" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("same-start match priority (later wins)", fg_at(blit, 1), string_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "keyword String foo",
                    "match Comment /foo/",
                })
                local buf = mk_buf({ "foo" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("keyword over match priority", fg_at(blit, 1), string_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "case ignore",
                    "keyword Comment foo",
                    "case match",
                    "keyword String foo",
                })
                local buf = mk_buf({ "foo" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("keyword case-sensitive over ignore-case", fg_at(blit, 1), string_fg)
            end

            do
                local ctx_state = mk_ctx({ 'match Comment "--.*$"' })
                local buf = mk_buf({ "-- hello" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("quoted punctuation pattern", fg_at(blit, 1), comment_fg)
            end

            do
                local ctx_state = mk_ctx({ 'match String "\\<foo\\>"' })
                local buf = mk_buf({ "foo" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("quoted backslash pattern", fg_at(blit, 1), string_fg)
            end

            do
                local parsed = Parser.parse('match String "\\<\\d\\+\\%([eE][-+]\\=\\d\\+\\)\\="')
                Assert.truthy(
                    "quoted pattern with equals is not dropped",
                    parsed.pattern ~= nil and parsed.pattern ~= ""
                )

                local ctx_state = mk_ctx({
                    'match Comment "--.*$"',
                    'match String "\\<\\d\\+\\%([eE][-+]\\=\\d\\+\\)\\="',
                })
                local buf = mk_buf({ "-- hello" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("quoted pattern with equals does not starve comment match", fg_at(blit, 1), comment_fg)
            end

            do
                local parsed = Parser.parse("region Comment start=+foo bar+ skip=+x y + end=+tail+")
                Assert.eq("region start assignment keeps spaces", parsed.patterns.start[1].pattern, "+foo bar+")
                Assert.eq("region skip assignment keeps spaces", parsed.patterns.skip[1].pattern, "+x y +")
                Assert.eq("region end assignment keeps spaces", parsed.patterns["end"][1].pattern, "+tail+")
            end

            do
                local parsed = Parser.parse('match Comment "[^"]\\+"')
                Assert.eq("quoted delimiter inside [] class is preserved", parsed.pattern, '"[^"]\\+"')
            end

            do
                local parsed = Parser.parse("region Comment start=+[,+ ]+ end=+tail+")
                Assert.eq("delimiter inside [] class is preserved", parsed.patterns.start[1].pattern, "+[,+ ]+")
            end

            do
                local ctx_state = mk_ctx({ "match Comment +[ab+]+" })
                local buf = mk_buf({ "+" })
                local ok_blit, blit = pcall(Runtime.line_to_blit, ctx_state, buf, 1)
                Assert.truthy("delimiter inside [] class does not crash runtime", ok_blit == true)
                if ok_blit then
                    Assert.eq("delimiter inside [] class matches", fg_at(blit, 1), comment_fg)
                end
            end

            do
                local ctx_state = mk_ctx({
                    "region Comment matchgroup=Error start=/>/ end=/^[^ \\t]/me=e-1 end=/^</",
                })
                local buf = mk_buf({ ">vim", "<" })
                Runtime.line_to_blit(ctx_state, buf, 1)
                local blit2 = Runtime.line_to_blit(ctx_state, buf, 2)
                Assert.eq("region end tie-break prefers later end= pattern", fg_at(blit2, 1), error_fg)
            end

            do
                local ctx_state = mk_ctx({ "keyword String hello contained" })
                local buf = mk_buf({ "hello" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("contained top-level no highlight", fg_at(blit, 1), normal_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "region Comment start=/\"/ end=/\"/ contains=String",
                    "keyword String hello contained",
                })
                local buf = mk_buf({ "\"hello\"" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("region start quote", fg_at(blit, 1), comment_fg)
                Assert.eq("contained inside region", fg_at(blit, 2), string_fg)
                Assert.eq("contained inside region tail", fg_at(blit, 6), string_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "match Comment /foo/ nextgroup=String skipwhite",
                    "match String /bar/ contained",
                })
                local buf = mk_buf({ "foo   bar" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("nextgroup foo", fg_at(blit, 1), comment_fg)
                Assert.eq("nextgroup bar", fg_at(blit, 7), string_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "region Comment start=/{/ end=/}/ contains=TOP",
                    "match Structure /a/ nextgroup=String",
                    "match String /b/ contained",
                })
                local buf = mk_buf({ "{ab}" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("nextgroup contained target inside TOP container", fg_at(blit, 3), string_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "match Comment /foo/ nextgroup=String",
                    "match String /[^\\\\]w/lc=1 contained",
                })
                local buf = mk_buf({ "foow" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("lc nextgroup anchor comment", fg_at(blit, 1), comment_fg)
                Assert.eq("lc nextgroup anchor string", fg_at(blit, 4), string_fg)
            end

            do
                local ctx_state = mk_ctx({ "region Comment start=/\\/\\*/ end=/\\*\\//" })
                local buf = mk_buf({ "/* one", "two */", "tail" })

                local blit2 = Runtime.line_to_blit(ctx_state, buf, 2)
                Assert.eq("region carries to line2", fg_at(blit2, 1), comment_fg)

                buf.lines[1] = "xx one"
                State.mark_dirty(ctx_state, 1)

                local blit2_after = Runtime.line_to_blit(ctx_state, buf, 2)
                Assert.eq("region removed after edit", fg_at(blit2_after, 1), normal_fg)
            end

            do
                local ctx_state = mk_ctx({
                    'region Comment start=+^[ \\t:]*\\zs".*$+ skip=+\\n\\s*\\\\\\|\\n\\s*"\\\\ + end="$"',
                })
                local buf = mk_buf({ '" one', "", "if x", '" two', "let y = 1" })

                local blit1 = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("line comment first line", fg_at(blit1, 1), comment_fg)

                local blit3 = Runtime.line_to_blit(ctx_state, buf, 3)
                Assert.eq("line comment does not leak across blank line", fg_at(blit3, 1), normal_fg)

                local blit4 = Runtime.line_to_blit(ctx_state, buf, 4)
                Assert.eq("line comment second block", fg_at(blit4, 1), comment_fg)

                local blit5 = Runtime.line_to_blit(ctx_state, buf, 5)
                Assert.eq("line comment does not leak after second block", fg_at(blit5, 1), normal_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "match Error /}/",
                    "region Structure start=/{/ end=/}/",
                })
                local buf = mk_buf({ "{}" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("region end beats same-pos match", fg_at(blit, 2), structure_fg)
                Assert.truthy("region end not Error background", bg_at(blit, 2) ~= error_bg)
            end

            do
                local ctx_state = mk_ctx({
                    "region Structure start=/{/ end=/}/",
                    "match Error /}/",
                })
                local buf = mk_buf({ "{}" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("region end beats same-pos match (older region)", fg_at(blit, 2), structure_fg)
                Assert.truthy("region end (older region) not Error background", bg_at(blit, 2) ~= error_bg)
            end

            do
                local ctx_state = mk_ctx({
                    "region Comment start=/\\<if\\>/ end=/\\<then\\>/me=e-4 nextgroup=String",
                    "match String /\\<then\\>/ contained",
                })
                local buf = mk_buf({ "if then" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("region me offset preserves nextgroup hand-off", fg_at(blit, 4), string_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "region Comment transparent matchgroup=Structure start=/{/ end=/}/",
                })
                local buf = mk_buf({ "{}" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("transparent matchgroup start delimiter", fg_at(blit, 1), structure_fg)
                Assert.eq("transparent matchgroup end delimiter", fg_at(blit, 2), structure_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "region Comment transparent start=/{/ end=/}/",
                })
                local buf = mk_buf({ "{}" })
                local blit = Runtime.line_to_blit(ctx_state, buf, 1)
                Assert.eq("transparent plain start stays Normal", fg_at(blit, 1), normal_fg)
                Assert.eq("transparent plain end stays Normal", fg_at(blit, 2), normal_fg)
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
