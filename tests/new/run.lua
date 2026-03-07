-- Filter OSC terminal probes from test output.
do
    local function is_terminal_probe_chunk(s)
        s = tostring(s or "")
        return s:find("\27]11;?\7", 1, true) ~= nil
            or s:find("\27[0m\27[48;2;", 1, true) ~= nil
    end

    local real_io = io
    local stdout_proxy = setmetatable({}, { __index = real_io.stdout })
    function stdout_proxy:write(...)
        for i = 1, select("#", ...) do
            if is_terminal_probe_chunk(select(i, ...)) then
                return true
            end
        end
        return real_io.stdout:write(...)
    end

    local io_proxy = setmetatable({ stdout = stdout_proxy }, { __index = real_io })
    function io_proxy.write(...)
        for i = 1, select("#", ...) do
            if is_terminal_probe_chunk(select(i, ...)) then
                return true
            end
        end
        return real_io.write(...)
    end

    io = io_proxy -- luacheck: globals io
end

local Runner = require("vim.tests.new.framework.runner")

Runner.run(Runner.discover("vim/tests/new/suites"))
