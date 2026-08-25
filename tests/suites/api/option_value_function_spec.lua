return {
    id = "api.option_value_function",
    description = "Ports function-valued option behavior for set/function()/funcref()/lambda and script-local calls.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local options_result = Assert.eval_vim(
            backend,
            "function option forms",
            "g:option_function_results",
            {
                script_ctx = "/tmp/option_value_function_forms.vim",
                setup = [[
function! MyFunc(...)
  return a:0
endfunction
let g:option_function_results = []
for [name, alias] in [
      \ ['completefunc', 'cfu'],
      \ ['findfunc', 'ffu'],
      \ ['omnifunc', 'ofu'],
      \ ['operatorfunc', 'opfunc'],
      \ ['quickfixtextfunc', 'qftf'],
      \ ['tagfunc', 'tfu'],
      \ ['thesaurusfunc', 'tsrfu'],
      \ ]
  execute 'set ' . alias . '=MyFunc'
  call add(g:option_function_results, eval('&' . name))

  execute 'set ' . alias . '=function(''MyFunc'')'
  call add(g:option_function_results, eval('&' . name))

  execute 'set ' . alias . '=funcref(''MyFunc'')'
  call add(g:option_function_results, eval('&' . name))

  execute 'set ' . alias . '={a\ ->\ a}'
  call add(g:option_function_results, eval('&' . name))

  execute 'set ' . alias . '='
  call add(g:option_function_results, eval('&' . name))
endfor
                ]],
            }
        )

        local expected = {}
        for _ = 1, 7 do
            expected[#expected + 1] = "MyFunc"
            expected[#expected + 1] = "function('MyFunc')"
            expected[#expected + 1] = "funcref('MyFunc')"
            expected[#expected + 1] = "{a -> a}"
            expected[#expected + 1] = ""
        end

        Assert.table_eq("option result values", options_result, expected)

        local script_a = Assert.eval_vim(
            backend,
            "script A function options",
            "[&operatorfunc, &tagfunc, call(function(&operatorfunc), [])]",
            {
                script_ctx = "/tmp/option_value_function_script_a.vim",
                setup = [[
function! s:LocalScope(...)
  return 11
endfunction
set operatorfunc=s:LocalScope
set tagfunc=function('s:LocalScope')
                ]],
            }
        )

        local script_b = Assert.eval_vim(
            backend,
            "script B function options",
            "[&quickfixtextfunc, call(function(&quickfixtextfunc), [0, []])]",
            {
                script_ctx = "/tmp/option_value_function_script_b.vim",
                setup = [[
function! s:LocalScope(...)
  return 22
endfunction
set quickfixtextfunc=s:LocalScope
                ]],
            }
        )

        Assert.table_eq(
            "script A function options",
            script_a,
            { "s:LocalScope", "function('s:LocalScope')", 11 }
        )
        Assert.table_eq("script B function options", script_b, { "s:LocalScope", 22 })
    end,
}
