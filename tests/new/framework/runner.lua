local Assert = require("vim.tests.new.framework.assert")
local LuaEditorBackend = require("vim.tests.new.framework.backends.lua_editor")
local HeadlessNvimBackend = require("vim.tests.new.framework.backends.headless_nvim")

local Runner = {}

-- Recursively discover test files (files ending in _spec.lua)
local function discover_test_files(dir_path)
    local files = {}
    
    local handle = io.popen("find " .. dir_path .. " -type f -name '*_spec.lua' 2>/dev/null | sort")
    if not handle then
        return files
    end
    
    for line in handle:lines() do
        files[#files + 1] = line
    end
    handle:close()
    
    return files
end

Runner.discover = discover_test_files

local function read_suite_paths(default_paths)
    local out = {}
    if #arg > 0 then
        for i = 1, #arg do
            if arg[i] ~= "--backend=lua_editor" and arg[i] ~= "--backend=headless_nvim" then
                out[#out + 1] = arg[i]
            end
        end
    end
    if #out == 0 then
        for i = 1, #default_paths do
            out[#out + 1] = default_paths[i]
        end
    end
    return out
end

local function read_backend()
    for i = 1, #arg do
        if arg[i] == "--backend=headless_nvim" then
            return "headless_nvim"
        end
    end
    return "lua_editor"
end

local function new_backend(name)
    if name == "headless_nvim" then
        return HeadlessNvimBackend.new()
    end
    return LuaEditorBackend.new({ ccvim_path = "vim" })
end

function Runner.run(default_paths)
    local backend_name = read_backend()
    local paths = read_suite_paths(default_paths)

    local total = 0
    local failed = 0
    local skipped = 0

    for i = 1, #paths do
        local path = paths[i]
        local ok_load, suite_or_err = pcall(dofile, path)
        if not ok_load then
            io.stderr:write(string.format("FAIL load %s: %s\n", path, tostring(suite_or_err)))
            failed = failed + 1
            total = total + 1
        else
            local suite = suite_or_err
            if suite.supports and suite.supports[backend_name] == false then
                print(string.format("SKIP %s (%s unsupported)", suite.id, backend_name))
                skipped = skipped + 1
                total = total + 1
            else
                local backend = new_backend(backend_name)
                local ok_run, run_err = pcall(function()
                    suite.run({ backend = backend, assert = Assert })
                end)
                backend:cleanup()
                total = total + 1
                if ok_run then
                    print(string.format("PASS %s (%s)", suite.id, backend_name))
                else
                    failed = failed + 1
                    io.stderr:write(string.format("FAIL %s (%s): %s\n", suite.id, backend_name, tostring(run_err)))
                end
            end
        end
    end

    print(string.format("Summary: %d total, %d failed, %d skipped", total, failed, skipped))
    if failed > 0 then
        os.exit(1)
    end
end

return Runner
