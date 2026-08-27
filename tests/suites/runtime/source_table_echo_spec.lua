return {
    id = "runtime.source_table_echo",
    description = "Sources Vimscript that echoes lists and dictionaries without Lua table addresses.",

    run = function(ctx)
        local Assert = ctx.assert
        local source = Assert.temp_path(ctx.backend, "source-table-echo", ".vim")
        Assert.write_file(ctx.backend, source, table.concat({
            "echo [1, {'two': 2}]",
            "echo {'one': [1, 2]}",
            "function! SourceTableEcho(value)",
            "  echo l:",
            "  echo a:",
            "endfunction",
            "call SourceTableEcho('value')",
            "let g:source_table_echo = [1, 2]",
        }, "\n"))

        local values = Assert.eval_vim(
            ctx.backend,
            "source renders table values",
            "g:source_table_echo",
            { setup = "source " .. source }
        )
        Assert.deep_eq("source leaves table values intact", values, { 1, 2 })

        local invalid_scope = Assert.temp_path(ctx.backend, "source-invalid-scope", ".vim")
        Assert.write_file(ctx.backend, invalid_scope, "echo l:\n")
        local value, err = ctx.backend:eval_vimscript("1", { setup = "source " .. invalid_scope })
        Assert.eq("source local scope result", value, nil)
        Assert.top_error_code("source local scope error", err, "E121")
    end,
}
