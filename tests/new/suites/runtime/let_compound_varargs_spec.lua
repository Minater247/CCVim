return {
    id = "runtime.let_compound_varargs",
    description = "Ports compound let += and function vararg semantics through real Vimscript execution.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local result = Assert.eval_vim(
            backend,
            "compound let and varargs",
            "[g:collect, g:noarg, g:witharg]",
            {
                script_ctx = "/tmp/let_compound_varargs.vim",
                setup = [[
function! s:Collect()
  let r = []
  for filename in ['a', 'b']
    let r += [filename]
  endfor
  return r
endfunction

function! s:Pick(...)
  let f = a:0 > 0 ? a:1 : 0
  return [a:0, a:000, f]
endfunction

let g:collect = s:Collect()
let g:noarg = s:Pick()
let g:witharg = s:Pick(42, 99)
                ]],
            }
        )

        Assert.table_eq("list += appends values", result[1], { "a", "b" })
        Assert.eq("a:0 on noarg call is zero", result[2][1], 0)
        Assert.truthy("a:000 on noarg call is empty list", backend:is_list(result[2][2]), result[2][2])
        Assert.eq("a:000 on noarg call length", #result[2][2], 0)
        Assert.eq("ternary fallback uses zero", result[2][3], 0)
        Assert.eq("a:0 on vararg call counts extras", result[3][1], 2)
        Assert.table_eq("a:000 captures extras", result[3][2], { 42, 99 })
        Assert.eq("ternary picks first extra", result[3][3], 42)
    end,
}
