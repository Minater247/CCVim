return {
    id = "runtime.heredoc_compile",
    description = "Ports heredoc list compilation and list merging through real Vimscript execution.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert

        Assert.eval_vim_eq(
            backend,
            "heredoc list merged and joined",
            "g:heredoc_joined",
            "alpha|beta|gamma",
            {
                script_ctx = "/tmp/heredoc_compile.vim",
                setup = [[
let s:aria =<< trim END
  alpha
  beta
END
let s:aria_deprecated =<< trim END
  gamma
END
call extend(s:aria, s:aria_deprecated)
let g:heredoc_joined = s:aria->join('|')
                ]],
            }
        )
    end,
}
