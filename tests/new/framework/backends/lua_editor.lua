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

    function backend:get_empty_dict_mt()
        return self:api_build().vim._empty_dict_mt
    end

    backend.EMPTY_DICT_MT = backend:get_empty_dict_mt()

    function backend:eval_lua(lua_expr)
        local vimapi = self:api_build().vim
        local env = setmetatable({ vim = vimapi }, { __index = _G })

        local chunk, err = load("return " .. lua_expr, "lua_editor_eval", "t", env)
        if not chunk then
            return nil, err
        end

        local ok, rv = pcall(chunk)
        if not ok then
            return nil, rv
        end

        return rv, nil
    end

    function backend:eval_vimscript(vimscript_expr, options)
        if type(vimscript_expr) ~= "string" then
            return nil, "eval_vimscript expects a string expression"
        end

        options = options or {}
        local setup = options.setup
        local script_ctx = options.script_ctx

        if setup ~= nil or script_ctx ~= nil then
            local Runtime = self.mock.loadModule("lib.excmd.runtime")
            local Scopes = self.mock.loadModule("lib.luaapi.scopes")
            local durable = Runtime.CaptureDurableScriptState({ script_ctx = script_ctx })
                or { g = Scopes._g, s = {}, funcs = {} }
            durable.g = durable.g or Scopes._g
            if type(script_ctx) == "string" and script_ctx ~= "" then
                durable.script_ctx = script_ctx
            end

            if setup ~= nil then
                if type(setup) ~= "string" then
                    return nil, "eval_vimscript setup must be a string"
                end
                local ok_setup, setup_err = Runtime.run(setup, {
                    durable = durable,
                    script_ctx = script_ctx,
                })
                if not ok_setup then
                    return nil, setup_err
                end
            end

            local ok_eval, result = Runtime.EvalExpression(vimscript_expr, {
                durable = durable,
                script_ctx = script_ctx,
            })
            if not ok_eval then
                return nil, result
            end
            return result, nil
        end

        local VimXpr = self.mock.loadModule("lib.excmd.vimxpr")
        local result = VimXpr.evaluate(vimscript_expr, { funcs = {} })
        if type(result) == "table" and result.IsError then
            return nil, tostring(result)
        end
        return result, nil
    end

    function backend:eval_block(code)
        if type(code) ~= "string" then
            return nil, "eval_block expects a string containing Lua code"
        end

        local vimapi = self:api_build().vim
        local env = setmetatable({ vim = vimapi }, { __index = _G })
        local chunk, err = load(code, "lua_editor_eval_block", "t", env)
        if not chunk then
            return nil, err
        end

        local ok, rv = pcall(chunk)
        if not ok then
            return nil, rv
        end

        return rv, nil
    end

    function backend:is_empty_dict(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        return getmetatable(tbl) == self:get_empty_dict_mt()
    end

    function backend:is_list(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        if self:is_empty_dict(tbl) then
            return false
        end
        -- Check if it's an array-like table
        local n = 0
        for k, _ in pairs(tbl) do
            if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
                return false
            end
            if k > n then
                n = k
            end
        end
        -- Verify no gaps
        for i = 1, n do
            if tbl[i] == nil then
                return false
            end
        end
        return true
    end

    function backend:is_dict(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        -- Empty dict has the marker metatable
        if self:is_empty_dict(tbl) then
            return true
        end
        -- Otherwise, it's a dict if it's not a list
        return not self:is_list(tbl)
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
