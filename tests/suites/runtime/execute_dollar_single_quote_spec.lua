return {
    id = "runtime.execute_dollar_single_quote",
    description = "Ports execute $'...' interpolation coverage through the Vimscript runner.",
    supports = { lua_editor = true, headless_nvim = true },
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.eval_vim_eq(
            backend,
            "execute $'...' interpolates expressions",
            "g:interp_exec",
            42,
            {
                script_ctx = "/tmp/execute_interp.vim",
                setup = [[
let s_val = 42
execute $'let g:interp_exec = {s_val}'
                ]],
            }
        )

        Assert.eval_vim_eq(
            backend,
            "execute mixed args with $'...' runs",
            "substitute(g:exec_multi, '^\\n', '', '')",
            "@helpExampleHighlight_vim syntax/vim.vim",
            {
                script_ctx = "/tmp/execute_interp_multi_args.vim",
                setup = [[
let s_lang = 'vim'
let s_syntax = 'vim'
redir => g:exec_multi
execute 'echo' $'"@helpExampleHighlight_{s_lang}"' $'"syntax/{s_syntax}.vim"'
redir END
                ]],
            }
        )

        Assert.eval_vim_eq(
            backend,
            "execute help.vim interpolation pattern runs",
            "g:exec_help_repro",
            1,
            {
                script_ctx = "/tmp/execute_interp_help_repro.vim",
                setup = [[
if !exists('g:help_example_languages')
  let g:help_example_languages = #{ vim: 'vim' }
endif
for [s:lang, s:syntax] in g:help_example_languages->items()
  execute 'silent! syn include' $'@helpExampleHighlight_{s:lang}' $'syntax/{s:syntax}.vim'
endfor
let g:exec_help_repro = 1
                ]],
            }
        )
    end,
}
