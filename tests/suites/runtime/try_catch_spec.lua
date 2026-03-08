return {
    id = "runtime.try_catch",
    description = "Ports try/catch/finally and loop control semantics through real Vimscript execution.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.eval_vim_eq(
            backend,
            "try catch E492 executes catch body",
            "g:tc_caught",
            1,
            {
                script_ctx = "/tmp/trycatch_492.vim",
                setup = [[
try
  nosuchcommand
catch /E492/
  let g:tc_caught = 1
endtry
                ]],
            }
        )

        local finally_result = Assert.eval_vim(
            backend,
            "try finally runs and success skips catch",
            "[g:tc_finally, g:tc_path]",
            {
                script_ctx = "/tmp/tryfinally.vim",
                setup = [[
let g:tc_finally = 0
try
  let g:tc_path = 'ok'
catch /E492/
  let g:tc_path = 'caught'
finally
  let g:tc_finally = 1
endtry
                ]],
            }
        )
        Assert.table_eq("try finally runs and success skips catch", finally_result, { 1, "ok" })

        Assert.expect_error_code_vim(
            backend,
            "unmatched catch propagates error",
            "1",
            "E492",
            {
                script_ctx = "/tmp/trycatch_miss.vim",
                setup = [[
try
  nosuchcommand
catch /E118/
  let g:tc_wrong_catch = 1
endtry
                ]],
            }
        )

        Assert.eval_vim_eq(
            backend,
            "break inside try exits loop",
            "g:tc_loop_break",
            1,
            {
                script_ctx = "/tmp/try_loop_break.vim",
                setup = [[
let g:tc_loop_break = 0
while 1
  try
    let g:tc_loop_break = g:tc_loop_break + 1
    break
  catch /.*/
    let g:tc_loop_break = -99
  endtry
endwhile
                ]],
            }
        )

        local continue_result = Assert.eval_vim(
            backend,
            "continue inside try continues loop",
            "[g:tc_loop_n, g:tc_loop_continue_hits]",
            {
                script_ctx = "/tmp/try_loop_continue.vim",
                setup = [[
let g:tc_loop_n = 0
let g:tc_loop_continue_hits = 0
while g:tc_loop_n < 3
  let g:tc_loop_n = g:tc_loop_n + 1
  try
    if g:tc_loop_n < 3
      continue
    endif
  catch /.*/
    let g:tc_loop_continue_hits = -99
  endtry
  let g:tc_loop_continue_hits = g:tc_loop_continue_hits + 1
endwhile
                ]],
            }
        )
        Assert.table_eq("continue inside try continues loop", continue_result, { 3, 1 })

        Assert.eval_vim_eq(
            backend,
            "regular catch in loop still works",
            "g:tc_loop_catch",
            1,
            {
                script_ctx = "/tmp/try_loop_regular_catch.vim",
                setup = [[
let g:tc_loop_catch = 0
while 1
  try
    nosuchcommand
  catch /E492/
    let g:tc_loop_catch = g:tc_loop_catch + 1
    break
  endtry
endwhile
                ]],
            }
        )
    end,
}
