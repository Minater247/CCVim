local ffi = {}

function ffi.cdef(_)
    return nil
end

local function unavailable()
    error("LuaJIT FFI is unavailable in the CCVim compatibility runtime", 2)
end

ffi.new = unavailable
ffi.cast = unavailable
ffi.load = unavailable
ffi.C = setmetatable({}, { __index = unavailable })

return ffi
