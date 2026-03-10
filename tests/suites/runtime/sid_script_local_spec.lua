return {
    id = "runtime.sid_script_local",
    description = "Ports <SID> expression calls and mapping expansion through sourced Vimscript and maparg().",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local expr_script = Assert.temp_path(backend, "sid-expr-runtime", ".vim")
        local map_script = Assert.temp_path(backend, "sid-map-runtime", ".vim")

        Assert.write_file(backend, expr_script, [[
function! s:NetrwGetWord()
  return 'target'
endfunction
function! s:NetrwBrowseChgDir(p1, p2, p3)
  return [a:p1, a:p2, a:p3]
endfunction
function! s:LocalBrowseCheck(x)
  let g:sid_expr_probe = a:x
endfunction
function! s:NetrwSortStyle(flag)
  let g:sid_sort_probe = a:flag
endfunction
call s:LocalBrowseCheck(<SID>NetrwBrowseChgDir(1, <SID>NetrwGetWord(), 1))
call <SID>NetrwSortStyle(7)
let g:sid_direct_word = <SID>NetrwGetWord()
]])

        Assert.write_file(backend, map_script, [[
function! s:MapRhs()
endfunction
nnoremap <buffer> <SID>MapLhs :call <SID>MapRhs()<CR>
let g:sid_expand = expand('<SID>')
let g:sid_map = maparg('<SID>MapLhs', 'n', 0, 1)
let g:sid_map_plain = maparg('<SID>MapLhs', 'n')
nunmap <buffer> <SID>MapLhs
let g:sid_after_unmap = maparg('<SID>MapLhs', 'n')
]])

        local result = Assert.eval_block(backend, "sid script-local scenarios", string.format([=[
            vim.cmd("enew!")
            vim.cmd("source " .. vim.fn.fnameescape(%q))
            vim.cmd("source " .. vim.fn.fnameescape(%q))

            return {
                vim.g.sid_expr_probe,
                vim.g.sid_sort_probe,
                vim.g.sid_direct_word,
                vim.g.sid_expand,
                vim.g.sid_map.lhs,
                vim.g.sid_map.rhs,
                vim.g.sid_map.sid,
                vim.g.sid_map.buffer,
                vim.g.sid_map.noremap,
                vim.g.sid_map_plain,
                vim.g.sid_after_unmap,
            }
        ]=], expr_script, map_script))

        Assert.table_eq("sid nested expression returns list", result[1], { 1, "target", 1 })
        Assert.eq("sid direct :call works", result[2], 7)
        Assert.eq("sid direct expression call works", result[3], "target")
        Assert.truthy("expand('<SID>') returns script-local prefix", result[4]:match("^<SNR>%d+_$") ~= nil, result[4])
        Assert.truthy("map lhs keeps expanded sid suffix", result[5]:match("^<SNR>%d+_MapLhs$") ~= nil, result[5])
        Assert.eq("maparg dict rhs preserves <SID>", result[6], ":call <SID>MapRhs()<CR>")
        Assert.eq("maparg dict sid matches expand('<SID>')", tonumber(result[4]:match("^<SNR>(%d+)_$")), result[7])
        Assert.eq("buffer-local mapping stays buffer-local", result[8], 1)
        Assert.eq("nnoremap keeps noremap flag", result[9], 1)
        Assert.eq(
            "plain maparg expands rhs to concrete <SNR>",
            result[10],
            string.format(":call <SNR>%d_MapRhs()<CR>", result[7])
        )
        Assert.eq("nunmap removes expanded <SID> mapping", result[11], "")
    end,
}
