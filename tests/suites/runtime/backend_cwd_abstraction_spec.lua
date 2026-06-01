return {
    id = "runtime.backend_cwd_abstraction",
    description = "Routes cwd and :cd path handling through the backend abstraction instead of directly calling shell APIs.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local mock = ctx.backend.mock
        local globals = mock.globals()
        local Backend = mock.loadModule("lib.backend")
        local Fn = mock.loadModule("lib.luaapi.fn")
        local VimFs = mock.loadModule("lib.luaapi.fs")

        globals.shell.setDir("tmp/project")
        Assert.eq("backend cwd reflects shell cwd", Backend.cwd(), "/tmp/project")
        Assert.eq("abspath resolves against backend cwd", VimFs.abspath("file.txt"), "/tmp/project/file.txt")

        globals.fs.makeDir("/tmp/other")
        Fn.fn.chdir("/tmp/other")

        Assert.eq("backend chdir updates cwd", Backend.cwd(), "/tmp/other")
        Assert.eq("abspath follows backend chdir", VimFs.abspath("nested.lua"), "/tmp/other/nested.lua")
    end,
}
