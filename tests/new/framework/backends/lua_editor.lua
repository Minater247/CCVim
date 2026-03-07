local LuaEditorBackend = {}

function LuaEditorBackend.new(opts)
    opts = opts or {}

    local MockEnv = require("vim.tests.test_mocks")
    local mock = MockEnv.setup({
        ccvim_path = opts.ccvim_path or "vim",
        module_stubs = opts.module_stubs,
        on_pull_event = opts.on_pull_event,
        bootstrap_default_editor = false,
    })

    local backend = {
        name = "lua_editor",
        mock = mock,
    }

    function backend:api_build()
        local ApiBuild = self.mock.loadModule("lib.luaapi.apibuild")
        local result = ApiBuild.Build()
        return result
    end

    function backend:cleanup()
        if self.mock.finish then
            self.mock.finish()
        end
        self.mock.cleanup()
    end

    return backend
end

return LuaEditorBackend
