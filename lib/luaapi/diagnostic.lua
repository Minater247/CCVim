local diagnostic = {}
local api = loadModule("vim.lib.luaapi.api")

diagnostic.severity = {
    "ERROR",
    "WARN",
    "INFO",
    "HINT",
    E = 1,
    ERROR = 1,
    W = 2,
    WARN = 2,
    I = 3,
    INFO = 3,
    N = 4,
    HINT = 4,
}

-- TODO: stubbed for lualine
function diagnostic.get()
    return {}
end

function diagnostic.reset(namespace, bufnr)
    if type(namespace) ~= "number" then
        error(("namespace: expected number, got %s"):format(type(namespace)), 2)
    end

    local target = bufnr
    if target == 0 then
        target = api.nvim_get_current_buf()
    end

    if target ~= nil then
        if api.nvim_buf_is_valid(target) then
            api.nvim_buf_clear_namespace(target, namespace, 0, -1)
        end
        return
    end

    for _, buf in ipairs(api.nvim_list_bufs()) do
        if api.nvim_buf_is_valid(buf) then
            api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
        end
    end
end


return diagnostic
