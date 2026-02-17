local diagnostic = {}

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


return diagnostic