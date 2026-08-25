return {
    id = "runtime.mock_root_mount_paths",
    description = "Verifies the lua-editor mock mounts the repo at editor root for loadfile and :runtime resolution; lua-editor-only because it targets the test harness path wrapper.", -- luacheck: ignore 631
    supports = { headless_nvim = false },
    run = function(ctx)
        local Assert = ctx.assert
        local MockEnv = require("vim.tests.test_mocks")

        local mock = MockEnv.setup({ bootstrap_default_editor = false })

        local ok, err = pcall(function()
            local nvim_chunk, nvim_err = loadfile("nvim.lua")
            Assert.truthy("nvim.lua loadfile succeeds", nvim_chunk ~= nil, nvim_err)
            Assert.eq("nvim.lua reports editor-root chunkname", debug.getinfo(nvim_chunk, "S").source, "@/nvim.lua")

            local shared_chunk, shared_err = loadfile("/runtime/lua/vim/shared.lua")
            Assert.truthy("runtime absolute loadfile succeeds", shared_chunk ~= nil, shared_err)
            Assert.eq(
                "runtime absolute loadfile keeps editor-root chunkname",
                debug.getinfo(shared_chunk, "S").source,
                "@/runtime/lua/vim/shared.lua"
            )

            Assert.eq("repo-mounted runtime file exists", fs.exists("/runtime/syntax/synload.vim"), true)

            local syntax_dir = fs.list("/runtime/syntax")
            local found_synload = false
            for i = 1, #syntax_dir do
                if syntax_dir[i] == "synload.vim" then
                    found_synload = true
                    break
                end
            end
            Assert.eq("repo-mounted runtime dir lists synload", found_synload, true)

            local Runtime = mock.loadModule("lib.excmd.runtime")
            local Options = mock.loadModule("lib.options")
            local Autocmd = mock.loadModule("lib.autocmd")

            Options.set("runtimepath", "/runtime,/runtime/after", false, nil, nil, true)

            local ok_runtime, runtime_err = Runtime.run("runtime syntax/synload.vim")
            Assert.eq("runtime command succeeds", ok_runtime, true)
            Assert.eq("runtime command has no error", runtime_err, nil)
            Assert.truthy(
                "runtime command installs Syntax autocmds",
                #Autocmd.GetAutocommands({ event = "Syntax" }) > 0
            )
        end)

        mock.cleanup()

        if not ok then
            error(err)
        end
    end,
}
