return {
    id = "api.require_vararg",
    description = "Ports runtimepath Lua module loading where require passes the module name as a vararg.",
    
    run = function(ctx)
        local backend = ctx.backend
        local Assert = ctx.assert
        local editor_root = Assert.temp_path(backend, "require-vararg", "")
        local editor_lua_dir = editor_root .. "/lua"
        local editor_modpath = editor_lua_dir .. "/varargmod.lua"
        Assert.ensure_dir(backend, editor_lua_dir)
        Assert.write_file(backend, editor_modpath, "return (...)")

        local result = Assert.eval_block(backend, string.format("require vararg from %s", editor_root), string.format([[
            local old_rtp = vim.go.runtimepath
            vim.go.runtimepath = %q
            package.loaded.varargmod = nil
            local ok, got = pcall(require, "varargmod")
            vim.go.runtimepath = old_rtp
            package.loaded.varargmod = nil
            return { ok, got }
        ]], editor_root))

        Assert.table_eq("require passes module name via vararg", result, { true, "varargmod" })
    end,
}
