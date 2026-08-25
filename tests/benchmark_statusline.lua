local script = debug.getinfo(1, "S").source:gsub("^@", "")
local repo_root = script:match("^(.*)/tests/[^/]+$") or "."
package.path = repo_root .. "/?.lua;" .. repo_root .. "/?/init.lua;" .. package.path

local MockEnv = require("tests.test_mocks")

local function parse_args(argv)
    local opts = {
        root = rawget(_G, "__CCVIM_TEST_ROOT") or ".",
        iterations = 5000,
    }
    for i = 1, #argv do
        local key, value = tostring(argv[i]):match("^%-%-([%w%-]+)=(.*)$")
        if key == "root" then
            opts.root = value
        elseif key == "iterations" then
            opts.iterations = math.max(1, math.floor(tonumber(value) or opts.iterations))
        else
            error("Unknown option: " .. tostring(argv[i]))
        end
    end
    return opts
end

local function main(argv)
    local opts = parse_args(argv)
    local mock = MockEnv.setup({ ccvim_path = opts.root })
    local ok, elapsed, checksum = pcall(function()
        local Statusline = mock.loadModule("lib.statusline", { immediate = true })
        local Scopes = mock.loadModule("lib.luaapi.scopes", { immediate = true })
        local win = windows[curwin]
        win.frame = win.frame or {}
        win.frame.width = 80
        Scopes._g.statusline_bench = "ready"
        local fmt = "%f %m %= %{g:statusline_bench} %l:%c"

        for _ = 1, 50 do
            Statusline.RenderInfo(fmt, win, 80)
        end
        collectgarbage("collect")

        local started = os.clock()
        local checksum = 0
        for _ = 1, opts.iterations do
            local rendered = Statusline.RenderInfo(fmt, win, 80)
            checksum = checksum + #rendered.spans
        end
        return os.clock() - started, checksum
    end)
    mock.cleanup()
    if not ok then
        error(elapsed)
    end
    assert(checksum > 0, "statusline render checksum mismatch")
    io.write(("root=%s\n"):format(opts.root))
    io.write(("iterations=%d elapsed=%.3f ms per-render=%.3f us\n"):format(
        opts.iterations,
        elapsed * 1000,
        elapsed * 1000000 / opts.iterations
    ))
end

main(arg)
