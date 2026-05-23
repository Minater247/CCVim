return {
    id = "runtime.jit_pipeline",
    description = "Verifies CCVim-internal JIT output shape and compile-cache reuse; this cannot run on headless Neovim because it inspects generated CCVim Lua, loads CCVim internal modules through MockEnv, and monkeypatches Compiler.compile_script to count CCVim-only JIT compiles.",
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()
        local ok, err = pcall(function()
            local Runtime = mock.loadModule("lib.excmd.runtime")
            local Compiler = mock.loadModule("lib.excmd.compiler")
            local Scopes = mock.loadModule("lib.luaapi.scopes")

            Runtime.ClearCompiledScriptCache()

            do
                local durable = Runtime.CaptureDurableScriptState({
                    script_ctx = "/tmp/jit_pipeline_compile_shape.vim",
                }) or { s = {}, funcs = {} }
                durable.g = durable.g or Scopes._g
                local state = Runtime.MakeRuntimeState(durable)
                state.g = durable.g

                local code, compile_err = Compiler.compile_script([[
echo 'hello'
let g:jit_pipeline_shape = 7
                ]], { state = state })
                Assert.truthy("compile succeeds", code ~= nil, compile_err)
                Assert.truthy(
                    "compiler hoists static nodes",
                    code:find("local __nodes = {", 1, true) ~= nil,
                    code
                )
                Assert.truthy(
                    "generic commands dispatch through precompiled nodes",
                    code:find("runtime:invoke_precompiled_node(__nodes[1])", 1, true) ~= nil,
                    code
                )
                Assert.truthy(
                    "special commands reuse hoisted cursor metadata",
                    code:find("runtime:set_exec_cursor_from(__nodes[2])", 1, true) ~= nil,
                    code
                )
            end

            do
                local compile_calls = 0
                local orig_compile = Compiler.compile_script
                Compiler.compile_script = function(...)
                    compile_calls = compile_calls + 1
                    return orig_compile(...)
                end

                local script = "let g:jit_pipeline_cache = get(g:, 'jit_pipeline_cache', 0) + 1"
                local ok1, err1 = Runtime.run(script, { script_ctx = "/tmp/jit_pipeline_cache_a.vim" })
                local ok2, err2 = Runtime.run(script, { script_ctx = "/tmp/jit_pipeline_cache_b.vim" })

                Compiler.compile_script = orig_compile

                Assert.eq("first run succeeds", ok1, true)
                Assert.eq("second run succeeds", ok2, true)
                Assert.eq("compile happens once for identical script text", compile_calls, 1)
                Assert.eq("cached script still executes twice", Scopes._g.jit_pipeline_cache, 2)
                Assert.eq("first run error", err1, nil)
                Assert.eq("second run error", err2, nil)
            end

            do
                local code, err = Compiler.compile_script([[
if 1
  echo "ok"
else
elseif 1
  echo "bad"
endif
                ]])
                Assert.eq("elseif after else rejects compile", code, nil)
                Assert.top_error_code("elseif after else uses E581", err:toString(), "E581")

                code, err = Compiler.compile_script([[
try
  echo "ok"
finally
catch /.*/
  echo "bad"
endtry
                ]])
                Assert.eq("catch after finally rejects compile", code, nil)
                Assert.top_error_code("catch after finally uses E603", err:toString(), "E603")

                code, err = Compiler.compile_script([[
for in [1, 2, 3]
  echo "bad"
endfor
                ]])
                Assert.eq("malformed for rejects compile", code, nil)
                Assert.top_error_code("malformed for uses E474", err:toString(), "E474")
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
