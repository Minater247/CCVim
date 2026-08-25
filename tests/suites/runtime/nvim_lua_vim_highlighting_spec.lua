return {
    id = "runtime.nvim_lua_vim_highlighting",
    description = "Ports nvim.lua syntax contains and cluster highlighting regressions through the Vim syntax engine runtime; lua-editor-only because it asserts CCVim syntax_engine internals rather than editor-visible Vimscript parity.", -- luacheck: ignore 631
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

            local function read_lines(path)
                local lines = {}
                for line in io.lines(path) do
                    lines[#lines + 1] = line
                end
                return lines
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

            local function find_luaapi_in_nvim(lines)
                local needle = 'loadModule("lib.luaapi.scopes")'
                for i = 1, #lines do
                    if lines[i]:find(needle, 1, true) then
                        local s, e = lines[i]:find("luaapi", 1, true)
                        if s and e then
                            return i, s, e
                        end
                    end
                end
                error("could not locate luaapi token in nvim.lua")
            end

            local function assert_fg_range(label, blit, s, e, want)
                for col = s, e do
                    local attrs = screen.hl_attrs(blit.hl[col]) or {}
                    Assert.eq(label .. " col " .. tostring(col), attrs.fg, want)
                end
            end

            local source_lines = read_lines("nvim.lua")
            local target_line, token_start, token_end = find_luaapi_in_nvim(source_lines)
            local buf = mk_buf(source_lines)
            local error_fg = Highlight.For("Error")[1]

            do
                local ctx_state = mk_ctx({
                    "match Error /luaapi/ contained",
                    "region Comment start=/\\(/ end=/\\)/ contains=TOP,Error",
                })
                local blit = Runtime.line_to_blit(ctx_state, buf, target_line)
                Assert.truthy("TOP+group nvim.lua blit exists", blit ~= nil)
                assert_fg_range("TOP+group highlights contained token", blit, token_start, token_end, error_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "match Error /luaapi/ contained",
                    "cluster LegacyTop contains=TOP,Error",
                    "region Comment start=/\\(/ end=/\\)/ contains=@LegacyTop",
                })
                local blit = Runtime.line_to_blit(ctx_state, buf, target_line)
                Assert.truthy("cluster TOP+group nvim.lua blit exists", blit ~= nil)
                assert_fg_range("cluster TOP+group highlights contained token", blit, token_start, token_end, error_fg)
            end

            do
                local ctx_state = mk_ctx({
                    "match Error /luaapi/",
                    "region Comment start=/\\(/ end=/\\)/ contains=CONTAINED,Error",
                })
                local blit = Runtime.line_to_blit(ctx_state, buf, target_line)
                Assert.truthy("CONTAINED+group nvim.lua blit exists", blit ~= nil)
                assert_fg_range("CONTAINED+group highlights top-level token", blit, token_start, token_end, error_fg)
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
