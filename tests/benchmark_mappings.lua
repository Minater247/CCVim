local script = debug.getinfo(1, "S").source:gsub("^@", "")
local repo_root = script:match("^(.*)/tests/[^/]+$") or "."
package.path = repo_root .. "/?.lua;" .. repo_root .. "/?/init.lua;" .. package.path

local MockEnv = require("tests.test_mocks")

local function parse_args(argv)
    local opts = {
        root = rawget(_G, "__CCVIM_TEST_ROOT") or ".",
        iterations = 2000,
        mappings = 600,
    }
    for i = 1, #argv do
        local key, value = tostring(argv[i]):match("^%-%-([%w%-]+)=(.*)$")
        if key == "root" then
            opts.root = value
        elseif key == "iterations" then
            opts.iterations = math.max(1, math.floor(tonumber(value) or opts.iterations))
        elseif key == "mappings" then
            opts.mappings = math.max(1, math.floor(tonumber(value) or opts.mappings))
        else
            error("Unknown option: " .. tostring(argv[i]))
        end
    end
    return opts
end

local function mapping_name(index)
    local first = (index - 1) % 26
    local second = math.floor((index - 1) / 26) % 26
    local third = math.floor((index - 1) / (26 * 26)) % 26
    return string.char(string.byte("a") + first)
        .. string.char(string.byte("a") + second)
        .. string.char(string.byte("a") + third)
end

local function main(argv)
    local opts = parse_args(argv)
    local mock = MockEnv.setup({ ccvim_path = opts.root })
    local ok, result = pcall(function()
        local Command = mock.loadModule("lib.command", { immediate = true })
        local Key = mock.loadModule("lib.key", { immediate = true })
        mock.loadModule("lib.mappings", { immediate = true })

        Command.clear_mappings("normal")
        for i = 1, opts.mappings do
            Command.map_callback("normal", Key.strtoseq(mapping_name(i)), function() end)
        end

        local hits = 0
        local target = Key.strtoseq("<F12>")
        Command.map_callback("normal", target, function()
            hits = hits + 1
        end)

        for _ = 1, 50 do
            Command.execute_normal_keys(target, { remap = true })
        end
        collectgarbage("collect")

        local started = os.clock()
        for _ = 1, opts.iterations do
            Command.execute_normal_keys(target, { remap = true })
        end
        local elapsed = os.clock() - started
        assert(hits == opts.iterations + 50, "mapping callback count mismatch")
        return elapsed
    end)
    mock.cleanup()
    if not ok then
        error(result)
    end

    io.write(("root=%s\n"):format(opts.root))
    io.write(("mappings=%d iterations=%d\n"):format(opts.mappings, opts.iterations))
    io.write(("elapsed=%.3f ms per-key=%.3f us\n"):format(
        result * 1000,
        result * 1000000 / opts.iterations
    ))
end

main(arg)
