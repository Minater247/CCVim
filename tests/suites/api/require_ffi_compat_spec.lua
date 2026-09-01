return {
    id = "api.require_ffi_compat",
    description = "Validates the explicit CraftOS LuaJIT/FFI compatibility boundary and fallback behavior.",
    supports = { headless_nvim = false },

    run = function(ctx)
        local Assert = ctx.assert
        local result = Assert.eval_block(ctx.backend, "require ffi compatibility", [[
            local ffi = require("ffi")
            local def_ok = pcall(ffi.cdef, "typedef int ccvim_test_int;")
            local new_ok, new_err = pcall(ffi.new, "int[1]")
            local c_ok = pcall(function() return ffi.C.clock_gettime end)
            return {
                type(jit.version),
                jit.os,
                type(ffi.cdef),
                def_ok,
                new_ok,
                tostring(new_err),
                c_ok,
            }
        ]])

        Assert.eq("jit version capability is present", result[1], "string")
        Assert.eq("jit platform remains CraftOS", result[2], "CraftOS")
        Assert.eq("ffi cdef surface exists", result[3], "function")
        Assert.eq("ffi declarations are accepted for fallback callers", result[4], true)
        Assert.eq("ffi allocation fails for fallback callers", result[5], false)
        Assert.truthy("ffi allocation explains limitation", result[6]:find("unavailable", 1, true) ~= nil)
        Assert.eq("ffi C access fails for fallback callers", result[7], false)
    end,
}
