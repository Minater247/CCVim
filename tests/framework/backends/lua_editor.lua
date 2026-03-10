local LuaEditorBackend = {}
local NIL = setmetatable({}, {
    __tostring = function()
        return "vim.NIL"
    end,
})

local function stringify_error(err)
    if type(err) == "table" and type(err.toString) == "function" then
        local ok, msg = pcall(err.toString, err)
        if ok and msg ~= nil then
            return tostring(msg)
        end
    end
    return tostring(err)
end

local function ensure_host_dir(path)
    local lfs = require("lfs")
    if path == nil or path == "" or path == "/" then
        return true, nil
    end
    if lfs.attributes(path, "mode") == "directory" then
        return true, nil
    end
    local parent = path:match("^(.*)/[^/]+$")
    if parent and parent ~= path then
        local ok_parent, parent_err = ensure_host_dir(parent)
        if not ok_parent then
            return false, parent_err
        end
    end
    local ok, err = lfs.mkdir(path)
    if ok or lfs.attributes(path, "mode") == "directory" then
        return true, nil
    end
    return false, err
end

function LuaEditorBackend.new(opts)
    opts = opts or {}
    local ccvim_path = opts.ccvim_path
    if ccvim_path == nil or ccvim_path == "" then
        ccvim_path = rawget(_G, "__CCVIM_TEST_ROOT") or "."
    end

    local MockEnv = require("vim.tests.test_mocks")
    local mock = MockEnv.setup({
        ccvim_path = ccvim_path,
        module_stubs = opts.module_stubs,
        on_pull_event = opts.on_pull_event,
        bootstrap_default_editor = false,
    })

    local backend = {
        name = "lua_editor",
        mock = mock,
        NIL = NIL,
    }
    local command_bootstrapped = false

    function backend:api_build()
        if not command_bootstrapped then
            local Event = self.mock.loadModule("lib.event")
            Event.LoadCommandModule()
            self.mock.loadModule("lib.mappings", { immediate = true })
            command_bootstrapped = true
        end
        local ApiBuild = self.mock.loadModule("lib.luaapi.apibuild")
        local result = ApiBuild.Build()
        return result
    end

    function backend:host_path_for_editor_path(editor_path)
        editor_path = tostring(editor_path or "")
        if editor_path == "" then
            return self.mock.tmp_root()
        end
        if editor_path:sub(1, 1) ~= "/" then
            return editor_path
        end
        return self.mock.tmp_root() .. editor_path
    end

    function backend:make_temp_path(prefix, suffix)
        local name = table.concat({
            tostring(prefix or "nvim-test"),
            tostring(os.time()),
            tostring(math.random(1000, 9999)),
        }, "-")
        return "/tmp/" .. name .. tostring(suffix or "")
    end

    function backend:ensure_dir(editor_path)
        return ensure_host_dir(self:host_path_for_editor_path(editor_path))
    end

    function backend:write_file(editor_path, content)
        local host_path = self:host_path_for_editor_path(editor_path)
        local parent = host_path:match("^(.*)/[^/]+$")
        local ok_dir, dir_err = ensure_host_dir(parent)
        if not ok_dir then
            return false, dir_err
        end
        local f, err = io.open(host_path, "w")
        if not f then
            return false, err
        end
        f:write(tostring(content or ""))
        f:close()
        return true, nil
    end

    function backend:remove_path(editor_path)
        local lfs = require("lfs")
        local host_path = self:host_path_for_editor_path(editor_path)
        local attr = lfs.attributes(host_path, "mode")
        if not attr then
            return true, nil
        end
        if attr == "directory" then
            local ok, err = lfs.rmdir(host_path)
            return ok or false, ok and nil or err
        end
        if os and type(os.remove) == "function" then
            local ok, err = os.remove(host_path)
            if ok then
                return true, nil
            end
            return false, err
        end
        return true, nil
    end

    function backend:get_empty_dict_mt()
        return self:api_build().vim._empty_dict_mt
    end

    backend.EMPTY_DICT_MT = backend:get_empty_dict_mt()

    local function normalize_result(value, vim_nil, seen)
        if value == vim_nil then
            return backend.NIL
        end
        if type(value) ~= "table" then
            return value
        end

        seen = seen or {}
        if seen[value] then
            return value
        end
        seen[value] = true

        local replacements = {}
        for k, v in pairs(value) do
            local nk = normalize_result(k, vim_nil, seen)
            local nv = normalize_result(v, vim_nil, seen)
            if nk ~= k or nv ~= v then
                replacements[#replacements + 1] = { k = k, nk = nk, nv = nv }
            end
        end

        for i = 1, #replacements do
            local item = replacements[i]
            value[item.k] = nil
            value[item.nk] = item.nv
        end

        return value
    end

    function backend:eval_lua(lua_expr)
        local api = self:api_build()
        local env = setmetatable({
            vim = api.vim,
            _G = api,
        }, { __index = api })

        local chunk, err = load("return " .. lua_expr, "lua_editor_eval", "t", env)
        if not chunk then
            return nil, err
        end

        local ok, rv = pcall(chunk)
        if not ok then
            return nil, rv
        end

        return normalize_result(rv, api.vim.NIL), nil
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
                    return nil, stringify_error(setup_err)
                end
            end

            local ok_eval, result = Runtime.EvalExpression(vimscript_expr, {
                durable = durable,
                script_ctx = script_ctx,
            })
            if not ok_eval then
                return nil, stringify_error(result)
            end
            return normalize_result(result, self:api_build().vim.NIL), nil
        end

        local VimXpr = self.mock.loadModule("lib.excmd.vimxpr")
        local result = VimXpr.evaluate(vimscript_expr, { funcs = {} })
        if type(result) == "table" and result.IsError then
            return nil, stringify_error(result)
        end
        return normalize_result(result, self:api_build().vim.NIL), nil
    end

    function backend:eval_block(code)
        if type(code) ~= "string" then
            return nil, "eval_block expects a string containing Lua code"
        end

        local api = self:api_build()
        local env = setmetatable({
            vim = api.vim,
            _G = api,
        }, { __index = api })
        local chunk, err = load(code, "lua_editor_eval_block", "t", env)
        if not chunk then
            return nil, err
        end

        local ok, rv = pcall(chunk)
        if not ok then
            return nil, rv
        end

        return normalize_result(rv, api.vim.NIL), nil
    end

    function backend:is_nil(value)
        return value == self.NIL
    end

    function backend:is_empty_dict(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        if self:is_nil(tbl) then
            return false
        end
        return getmetatable(tbl) == self:get_empty_dict_mt()
    end

    function backend:is_list(tbl)
        if type(tbl) ~= "table" then
            return false
        end
        if self:is_nil(tbl) then
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
        if self:is_nil(tbl) then
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
