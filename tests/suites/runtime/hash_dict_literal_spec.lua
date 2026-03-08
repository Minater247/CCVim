return {
    id = "runtime.hash_dict_literal",
    description = "Ports hash-dict literal runtime behavior through real Vimscript execution.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.eval_vim_eq(
            backend,
            "hash-dict literal populates missing variable",
            "g:help_example_languages.vim",
            "vim",
            {
                script_ctx = "/tmp/hash_dict_literal_runtime.vim",
                setup = [[
if !exists('g:help_example_languages')
  let g:help_example_languages = #{ vim: 'vim' }
endif
                ]],
            }
        )

        Assert.eval_vim_eq(
            backend,
            "hash-dict literal gate preserves existing value",
            "g:help_example_languages.vim",
            "kept",
            {
                script_ctx = "/tmp/hash_dict_literal_runtime_2.vim",
                setup = [[
let g:help_example_languages = { 'vim': 'kept' }
if !exists('g:help_example_languages')
  let g:help_example_languages = #{ vim: 'vim' }
endif
                ]],
            }
        )
    end,
}
