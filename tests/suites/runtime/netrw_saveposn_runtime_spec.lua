return {
    id = "runtime.netrw_saveposn",
    description = "Ports netrw SavePosn list reuse behavior through real Vimscript function execution.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local result = Assert.eval_vim(
            backend,
            "netrw SavePosn reuse",
            "[g:arg_exists_history, g:count_after_first, g:count_after_second]",
            {
            script_ctx = "/tmp/netrw_saveposn_runtime.vim",
            setup = [[
                enew!
                file /tmp/a
                call setline(1, 'line1')
                function! s:SavePosn(posndict)
                  if !exists('g:arg_exists_history')
                    let g:arg_exists_history = []
                  endif
                  call add(g:arg_exists_history, exists("a:posndict[bufnr('%')]"))
                  if !exists("a:posndict[bufnr('%')]")
                    let a:posndict[bufnr('%')] = []
                  endif
                  call add(g:arg_exists_history, exists("a:posndict[bufnr('%')]"))
                  call add(a:posndict[bufnr('%')], {'lnum': 1})
                  return a:posndict
                endfunction

                let g:netrw_posn = {}
                call s:SavePosn(g:netrw_posn)
                let g:count_after_first = len(g:netrw_posn[bufnr('%')])
                call s:SavePosn(g:netrw_posn)
                let g:count_after_second = len(g:netrw_posn[bufnr('%')])
            ]],
            }
        )

        local history = result[1]
        Assert.eq("exists() history length", #history, 4)
        Assert.eq("exists() before first set is false", history[1], 0)
        Assert.eq("exists() after first set is true", history[2], 1)
        Assert.eq("exists() before second set is true", history[3], 1)
        Assert.eq("exists() after second set is true", history[4], 1)
        Assert.eq("first save adds one entry", result[2], 1)
        Assert.eq("second save appends to same list", result[3], 2)
    end,
}
