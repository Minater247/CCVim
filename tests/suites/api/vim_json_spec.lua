return {
    id = "api.vim_json",
    description = "Validates vim.json against Neovim object, array, null, escape, option, and error semantics.",
    supports = { lua_editor = true, headless_nvim = true },

    run = function(ctx)
        local result = ctx.assert.eval_block(ctx.backend, "vim.json scenarios", [[
            local decoded = vim.json.decode(
                '{"array":[],"object":{},"null":null,"number":-1.25e2,"text":"line\\n\\u00e9\\ud83d\\ude00"}'
            )
            local roundtrip = vim.json.decode(vim.json.encode({ value = "a/b", flag = true, null = vim.NIL }))
            local luanil = vim.json.decode('{"value":null}', { luanil = { object = true } })
            local recursive = {}
            recursive.self = recursive
            return {
                vim.islist(decoded.array),
                vim.islist(decoded.object),
                decoded.null == vim.NIL,
                decoded.number,
                decoded.text,
                roundtrip.value,
                roundtrip.flag,
                roundtrip.null == vim.NIL,
                luanil.value == nil,
                vim.json.encode("a/b", { escape_slash = true }),
                pcall(vim.json.decode, '{"bad":]'),
                (pcall(vim.json.encode, recursive)),
            }
        ]])
        ctx.assert.table_eq("vim.json behavior", result, {
            true, false, true, -125, "line\né😀", "a/b", true, true, true,
            '"a\\/b"', false, false,
        })
    end,
}
