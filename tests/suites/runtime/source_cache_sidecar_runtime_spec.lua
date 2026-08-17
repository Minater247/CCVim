return {
    id = "runtime.source_cache_sidecar",
    description = "Verifies CCVim's sourced-Vimscript sidecar cache files; this cannot run on headless Neovim because `.ccvim` caching is CCVim-specific, uses MockEnv to patch `fs.attributes`, and monkeypatches `Compiler.compile_script` to observe CCVim's internal compile path.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup()
        local orig_attributes
        local orig_open
        local orig_compile
        local orig_no_cache
        local ok, err = pcall(function()
            local ScriptSource = mock.loadModule("lib.scriptsource")
            local Compiler = mock.loadModule("lib.excmd.compiler")
            local Scopes = mock.loadModule("lib.luaapi.scopes")

            local source_path = "/tmp/source_cache_sidecar.vim"
            local cache_path = "/tmp/source_cache_sidecar.ccvim"

            local function write(path, data)
                local f = fs.open(path, "w")
                Assert.truthy("open " .. path, f ~= nil, path)
                f.write(data)
                f.close()
            end

            local function read(path)
                local f = fs.open(path, "r")
                Assert.truthy("read " .. path, f ~= nil, path)
                local data = f.readAll()
                f.close()
                return data
            end

            write(
                source_path,
                "let g:source_cache_hits = get(g:, 'source_cache_hits', 0) + 1"
                    .. " | let g:source_cache_stage = 'first'"
            )

            local mtimes = {
                [source_path] = 100,
            }
            orig_attributes = fs.attributes
            fs.attributes = function(path)
                local attrs = orig_attributes(path)
                if type(attrs) ~= "table" then
                    return attrs
                end
                local modified = mtimes[path]
                if type(modified) == "number" then
                    attrs.modified = modified
                    attrs.modification = modified
                end
                return attrs
            end

            local compile_calls = 0
            orig_compile = Compiler.compile_script
            Compiler.compile_script = function(...)
                compile_calls = compile_calls + 1
                return orig_compile(...)
            end
            orig_no_cache = rawget(_G, "no_cache")

            local ok1, err1 = ScriptSource.source(source_path)
            Assert.eq("first source succeeds", ok1, true)
            Assert.eq("first source error", err1, nil)
            Assert.eq("first source compiles", compile_calls, 1)
            Assert.eq("first stage executed", Scopes._g.source_cache_stage, "first")
            Assert.eq("first hit count", Scopes._g.source_cache_hits, 1)
            Assert.eq("cache file created", fs.exists(cache_path), true)

            mtimes[cache_path] = 100
            local cached_code = read(cache_path)
            Assert.truthy(
                "cache file has compiled chunk",
                cached_code:find("return function", 1, true) ~= nil,
                cached_code
            )

            orig_open = fs.open
            fs.open = function(path, mode)
                if path == source_path and (mode == nil or mode == "r") then
                    error("source file should not be read when sidecar cache is fresh")
                end
                return orig_open(path, mode)
            end

            local ok2, err2 = ScriptSource.source(source_path)
            fs.open = orig_open
            orig_open = nil
            Assert.eq("second source succeeds", ok2, true)
            Assert.eq("second source error", err2, nil)
            Assert.eq("fresh cache avoids recompiling", compile_calls, 1)
            Assert.eq("second source still executes script", Scopes._g.source_cache_hits, 2)
            Assert.eq("second source reuses cached stage", Scopes._g.source_cache_stage, "first")

            write(
                source_path,
                "let g:source_cache_hits = get(g:, 'source_cache_hits', 0) + 1"
                    .. " | let g:source_cache_stage = 'second'"
            )
            mtimes[source_path] = 200
            mtimes[cache_path] = 100

            local ok3, err3 = ScriptSource.source(source_path)
            Assert.eq("stale cache source succeeds", ok3, true)
            Assert.eq("stale cache source error", err3, nil)
            Assert.eq("newer source recompiles", compile_calls, 2)
            Assert.eq("recompiled source executes updated body", Scopes._g.source_cache_stage, "second")
            Assert.eq("recompiled source increments hits", Scopes._g.source_cache_hits, 3)

            local stale_cached_code = read(cache_path)

            write(
                source_path,
                "let g:source_cache_hits = get(g:, 'source_cache_hits', 0) + 1"
                    .. " | let g:source_cache_stage = 'third'"
            )
            mtimes[source_path] = 300
            mtimes[cache_path] = 300
            _G.no_cache = true

            local ok4, err4 = ScriptSource.source(source_path)
            Assert.eq("no-cache source succeeds", ok4, true)
            Assert.eq("no-cache source error", err4, nil)
            Assert.eq("no-cache forces recompilation", compile_calls, 3)
            Assert.eq("no-cache executes updated body", Scopes._g.source_cache_stage, "third")
            Assert.eq("no-cache increments hits", Scopes._g.source_cache_hits, 4)
            Assert.truthy("no-cache rewrites cache file", read(cache_path) ~= stale_cached_code)

            local legacy_source = "/tmp/source_cache_legacy.vim"
            local legacy_cache = "/tmp/source_cache_legacy.ccvim"
            write(legacy_source, "let g:source_cache_legacy = 'recompiled'")
            write(legacy_cache, "return function(state) state.g.source_cache_legacy = 'legacy' end")
            mtimes[legacy_source] = 400
            mtimes[legacy_cache] = 400
            _G.no_cache = false

            local ok5, err5 = ScriptSource.source(legacy_source)
            Assert.eq("legacy cache source succeeds", ok5, true)
            Assert.eq("legacy cache source error", err5, nil)
            Assert.eq("legacy cache is recompiled", compile_calls, 4)
            Assert.eq("legacy cache body is not executed", Scopes._g.source_cache_legacy, "recompiled")
            Assert.truthy(
                "rewritten cache carries current version",
                read(legacy_cache):find(Compiler.CACHE_HEADER, 1, true) == 1
            )
        end)

        if orig_compile then
            local Compiler = mock.loadModule("lib.excmd.compiler")
            Compiler.compile_script = orig_compile
        end
        if orig_attributes then
            fs.attributes = orig_attributes
        end
        if orig_open then
            fs.open = orig_open
        end
        _G.no_cache = orig_no_cache
        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
