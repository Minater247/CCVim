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

Runner.run({
    "vim/tests/new/suites/api/vim_list_slice_spec.lua",
    "vim/tests/new/suites/api/vim_islist_spec.lua",
    "vim/tests/new/suites/api/vim_str_index_spec.lua",
    "vim/tests/new/suites/api/vimscript_eval_spec.lua",
    "vim/tests/new/suites/api/vim_iter_spec.lua",
    "vim/tests/new/suites/api/vim_fs_joinpath_spec.lua",
    "vim/tests/new/suites/api/table_type_helpers_spec.lua",
    "vim/tests/new/suites/runtime/nvim_redraw_api_spec.lua",
    "vim/tests/new/suites/runtime/vimxpr_slice_spec.lua",
})
