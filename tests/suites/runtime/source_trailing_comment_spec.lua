return {
    id = "runtime.source_trailing_comment",
    description = "Ports :source path parsing with spaced and adjacent trailing comments.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local editor_spaced = Assert.temp_path(backend, "source-trailing-comment-spaced", ".vim")
        local editor_adjacent = Assert.temp_path(backend, "source-trailing-comment-adjacent", ".vim")
        Assert.write_file(backend, editor_spaced, "let g:source_comment_spaced = 1\n")
        Assert.write_file(backend, editor_adjacent, "let g:source_comment_adjacent = 1\n")

        Assert.eval_vim_eq(
            backend,
            "source with spaced trailing comment succeeds",
            "g:source_comment_spaced",
            1,
            {
                script_ctx = "/tmp/source_trailing_comment_spaced.vim",
                setup = string.format(
                    [[source %s " Nvim: revert to Vim default color scheme]],
                    editor_spaced
                ),
            }
        )

        Assert.eval_vim_eq(
            backend,
            "source with adjacent trailing comment succeeds",
            "g:source_comment_adjacent",
            1,
            {
                script_ctx = "/tmp/source_trailing_comment_adjacent.vim",
                setup = string.format([[source %s"comment]], editor_adjacent),
            }
        )
    end,
}
