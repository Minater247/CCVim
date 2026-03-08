return {
    id = "runtime.autocmd_script_state",
    description = "Ports script-local autocmd state and related script parsing behavior through sourced Vimscript.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        local script_a = Assert.temp_path(backend, "autocmd-script-state-a", ".vim")
        local script_b = Assert.temp_path(backend, "autocmd-script-state-b", ".vim")

        Assert.write_file(backend, script_a, [[
let s:val = 1
augroup ScriptStateSpec
  autocmd!
  autocmd User ScriptStateTest let s:val = s:val + 1 | let g:autocmd_seen = s:val
augroup END
let s:val = 2

if "x" ==# "x"
  let g:expr_string_head_ok = 1
endif

command! -nargs=* Vim9X let g:digit_cmd_qargs = <q-args>
Vim9X "abc"

let g:scope_probe = 12
let g:scope_get = get(g:, 'scope_probe', -1)
let g:scope_missing = get(g:, 'scope_probe_missing', 77)

let bare_scope_probe = 42
let g:bare_scope_exists = exists('bare_scope_probe')
let g:bare_scope_read = bare_scope_probe
let s:bare_script_only = 99
let g:bare_scope_script_hidden = exists('bare_script_only')

function! s:Helper()
  return 'A'
endfunction

function! g:CallScriptA()
  return s:Helper()
endfunction

function! ArgUnder(tutor_name)
  let g:underscore_arg_type = type(a:tutor_name)
  let g:underscore_arg_value = a:tutor_name
endfunction

call ArgUnder('abc')
]])

        Assert.write_file(backend, script_b, [[
function! s:Helper()
  return 'B'
endfunction

let g:script_local_call_ctx = g:CallScriptA()
unlet bare_scope_probe
let g:bare_scope_after_unlet = exists('bare_scope_probe')
]])

        local result = Assert.eval_block(backend, "autocmd script state scenarios", string.format([[
            vim.cmd("source " .. vim.fn.fnameescape(%q))
            vim.cmd("doautocmd User ScriptStateTest")
            local seen_1 = vim.g.autocmd_seen
            vim.cmd("doautocmd User ScriptStateTest")
            local seen_2 = vim.g.autocmd_seen
            vim.cmd("source " .. vim.fn.fnameescape(%q))

            return {
                seen_1,
                seen_2,
                vim.g.expr_string_head_ok,
                vim.g.digit_cmd_qargs,
                vim.g.scope_get,
                vim.g.scope_missing,
                vim.g.bare_scope_exists,
                vim.g.bare_scope_read,
                vim.g.bare_scope_script_hidden,
                vim.g.bare_scope_after_unlet,
                vim.g.script_local_call_ctx,
                vim.g.underscore_arg_type,
                vim.g.underscore_arg_value,
            }
        ]], script_a, script_b))

        Assert.eq("autocmd run #1 sees latest script-local state", result[1], 3)
        Assert.eq("autocmd run #2 keeps persistent script-local state", result[2], 4)
        Assert.eq("if expression can start with string literal", result[3], 1)
        Assert.eq("user command names accept digits", result[4], [["abc"]])
        Assert.eq("get(g:, key, default)", result[5], 12)
        Assert.eq("get(g:, missing, default)", result[6], 77)
        Assert.eq("exists() sees bare global", result[7], 1)
        Assert.eq("bare expression reads global", result[8], 42)
        Assert.eq("bare name does not read s: vars", result[9], 0)
        Assert.eq("bare unlet clears global", result[10], 0)
        Assert.eq("callee keeps defining script-local context", result[11], "A")
        Assert.eq("underscore arg type is string", result[12], 1)
        Assert.eq("underscore arg value is preserved", result[13], "abc")

        Assert.remove_path(backend, script_a)
        Assert.remove_path(backend, script_b)
    end,
}
