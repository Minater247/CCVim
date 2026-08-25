return {
    id = "runtime.jit_pipeline",
    description = "Verifies CCVim-internal JIT lowering and compile-cache reuse; this cannot run on headless Neovim because it inspects generated CCVim Lua, loads CCVim internal modules through MockEnv, and monkeypatches Compiler.compile_script to count CCVim-only JIT compiles.", -- luacheck: ignore 631
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

            local durable = Runtime.CaptureDurableScriptState({
                script_ctx = "/tmp/jit_pipeline_compile_shape.vim",
            }) or { s = {}, funcs = {} }
            durable.g = durable.g or Scopes._g
            local state = Runtime.MakeRuntimeState(durable)
            state.g = durable.g

            do
                local first = Runtime.new(Runtime.MakeRuntimeState(durable))
                local second = Runtime.new(Runtime.MakeRuntimeState(durable))
                Assert.eq("runtime methods live on the shared prototype", rawget(first, "eval_expr"), nil)
                Assert.eq("runtime instances reuse eval method", first.eval_expr, second.eval_expr)
                Assert.eq("runtime return helper is callable", type(first.return_exc), "function")
            end

            do
                local code, compile_err = Compiler.compile_script([[
echo 'hello'
let g:jit_pipeline_shape = 1 + 2 * 3
                ]], { state = state })
                Assert.truthy("compile succeeds", code ~= nil, compile_err)
                Assert.truthy("simple echo lowers directly", code:find("runtime:echo_values", 1, true) ~= nil, code)
                Assert.truthy(
                    "static g: assignment lowers to direct state access",
                    code:find("__g.jit_pipeline_shape =", 1, true) ~= nil,
                    code
                )
                Assert.eq(
                    "static g: assignment avoids string lvalue helper",
                    code:find('runtime:assign("g:jit_pipeline_shape"', 1, true),
                    nil
                )
                Assert.eq(
                    "simple arithmetic avoids expression evaluator",
                    code:find('runtime:eval_expr("1 + 2 * 3"', 1, true),
                    nil
                )
            end

            do
                local code, compile_err = Compiler.compile_script([[
function! JitLocalLowering()
  let x = 1
  let x += 2
  return x
endfunction
                ]], { state = state })
                Assert.truthy("local-lowering function compiles", code ~= nil, compile_err)
                Assert.truthy(
                    "safe Vimscript local lowers to Lua local",
                    code:find("local __l_x", 1, true) ~= nil,
                    code
                )
                Assert.eq(
                    "safe Vimscript local avoids runtime assignment",
                    code:find('runtime:assign("x"', 1, true),
                    nil
                )
                Assert.eq(
                    "safe Vimscript local avoids expression evaluator",
                    code:find('runtime:eval_expr("x"', 1, true),
                    nil
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
                Runtime.ClearCompiledScriptCache()
                local compile_calls = 0
                local orig_compile = Compiler.compile_script
                Compiler.compile_script = function(...)
                    compile_calls = compile_calls + 1
                    return orig_compile(...)
                end

                for i = 1, 257 do
                    local ran, run_err = Runtime.run("let g:jit_cache_eviction = " .. i)
                    Assert.eq("unique cached script runs", ran, true)
                    Assert.eq("unique cached script error", run_err, nil)
                end
                local reran, rerun_err = Runtime.run("let g:jit_cache_eviction = 1")
                Compiler.compile_script = orig_compile

                Assert.eq("evicted script runs", reran, true)
                Assert.eq("evicted script error", rerun_err, nil)
                Assert.eq("bounded cache evicts the oldest script", compile_calls, 258)
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

            do
                local code, err = Compiler.compile_script([[
function! JitNestedRegion()
  if 1
    try
      echo "try"
    catch /.*/
      echo "catch"
    endtry
  endif
  let g:jit_nested_region_after = 1
endfunction
                ]])
                Assert.truthy("nested try inside function compiles", code ~= nil, err)
                local loaded, load_err = load(code, "jit_nested_region", "t", _G)
                Assert.truthy("nested try compiled Lua loads", loaded ~= nil, load_err)
            end
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
